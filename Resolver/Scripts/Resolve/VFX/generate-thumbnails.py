#!/usr/bin/env python3

import sys
import os
import importlib.util
import json
import time
import subprocess

# === Load JSON Payload ===
if len(sys.argv) < 2:
    print(json.dumps({"error": "Missing JSON input file path"}))
    sys.exit(1)

json_path = sys.argv[1]

if not os.path.exists(json_path):
    print(json.dumps({"error": f"JSON file not found: {json_path}"}))
    sys.exit(1)

try:
    with open(json_path, 'r') as f:
        data = json.load(f)
except Exception as e:
    print(json.dumps({"error": f"Failed to parse JSON: {e}"}))
    sys.exit(1)

# === Helper: Frames to TC ===
def frames_to_tc(frames, fps):
    try:
        if not fps or float(fps) == 0.0: return "00:00:00:00"
        fps_float = float(fps)
        total_seconds = frames / fps_float
        hours = int(total_seconds // 3600)
        minutes = int((total_seconds % 3600) // 60)
        seconds = int(total_seconds % 60)
        frame_part = int(frames % fps_float)
        return "{:02}:{:02}:{:02}:{:02}".format(hours, minutes, seconds, frame_part)
    except:
        return "00:00:00:00"

output_dir = data.get("outputDir")
clips = data.get("clips", [])
export_format = data.get("format", "jpg")
resize_height = int(data.get("resizeHeight", 512))

if not output_dir or not clips:
    print(json.dumps({"error": "Invalid JSON data (missing outputDir or clips)"}))
    sys.exit(1)

# Create Output Directory
if not os.path.exists(output_dir):
    try:
        os.makedirs(output_dir)
    except Exception as e:
        print(json.dumps({"error": f"Failed to create output directory: {e}"}))
        sys.exit(1)

# === Resolve API Setup ===
try:
    sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
    sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")
    
    spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
    dvr = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dvr)
    
    import DaVinciResolveScript as dvr
    print(json.dumps({"status": "debug", "message": "Connecting to Resolve..."}))
    resolve = dvr.scriptapp("Resolve")
    
    if not resolve:
        raise Exception("Could not connect to Resolve (scriptapp returned None)")

    print(json.dumps({"status": "debug", "message": "Getting Project Manager..."}))
    pm = resolve.GetProjectManager()
    if not pm:
        raise Exception("GetProjectManager() returned None")
        
    print(json.dumps({"status": "debug", "message": "Getting Current Project..."}))
    project = pm.GetCurrentProject()
    if not project:
         raise Exception("No active project")
         
    timeline = project.GetCurrentTimeline()
    if not timeline:
        raise Exception("No active timeline")

    # === Track Management (Before Switching Page) ===
    target_track_index = int(data.get("targetTrack", 1))
    track_states = {}
    track_count = timeline.GetTrackCount("video")

    try:
        # Store current track states
        for i in range(1, track_count + 1):
             try:
                 # API Check: Some versions use GetTrackEnable, others GetIsTrackEnabled
                 if hasattr(timeline, "GetIsTrackEnabled"):
                     state = timeline.GetIsTrackEnabled("video", i)
                 elif hasattr(timeline, "GetTrackEnable"):
                     state = timeline.GetTrackEnable("video", i)
                 else:
                     # Fallback or skip
                     state = True 
                 
                 track_states[i] = state
             except Exception as e:
                 print(json.dumps({"status": "warning", "message": f"Failed to read track state {i}: {e}"}))
                 track_states[i] = True # Assume enabled if read fails to be safe? Or ignore?

        # Solo Target Track
        for i in range(1, track_count + 1):
             should_enable = (i == target_track_index)
             if hasattr(timeline, "SetTrackEnable"):
                 timeline.SetTrackEnable("video", i, should_enable)
            
    except Exception as e:
        print(json.dumps({"status": "error", "message": f"Track Setup Failed: {e}"}))


    # === Switch to Color Page ===
    
    # WRAP EVERYTHING in try/finally to ensure tracks are restored
    try:
        print(json.dumps({"status": "debug", "message": "Switching to Color Page..."}))
        if not resolve.OpenPage("color"):
             print(json.dumps({"status": "debug", "message": "OpenPage returned False (might be already open or failed)"}))
        
        # === Gallery / Album Management ===
        print(json.dumps({"status": "debug", "message": "Getting Gallery..."}))
        gallery = project.GetGallery()
        if not gallery:
            raise Exception("Could not access Gallery (GetGallery returned None)")
    
        # Try to find or create "resolver_temp_stills"
        # Note: API might not support creating albums easily. We try to set it.
        # If SetCurrentStillAlbum returns False, it might not exist.
        # We will strive to use the CURRENT album if we can't create one, 
        # BUT we must be careful not to delete user stills.
        
        print(json.dumps({"status": "debug", "message": "Getting Current Still Album..."}))
        
        # === Album Management ===
        # 1. Log and Find valid albums
        albums = gallery.GetGalleryStillAlbums()
        target_album = None
        
        if albums:
            print(json.dumps({"status": "debug", "message": f"Found {len(albums)} albums: {[a.GetLabel() for a in albums]}"}))
            for album in albums:
                lbl = album.GetLabel()
                if lbl == "resolver_temp_stills":
                    gallery.SetCurrentStillAlbum(album)
                    target_album = album
                    break
        
        # 2. If no target yet, try to find ANY valid album (prefer "Stills" or just first valid)
        if not target_album and albums:
             for album in albums:
                 if album.GetLabel(): # Valid label
                     target_album = album
                     gallery.SetCurrentStillAlbum(album)
                     break
    
        # 3. Last Resort: Current
        if not target_album:
             current = gallery.GetCurrentStillAlbum()
             if current and current.GetLabel():
                 target_album = current
        
        # 4. Desperation Fallback: Just take the first one
        if not target_album and albums:
            print(json.dumps({"status": "warning", "message": "No labeled album found. Using first available album."}))
            target_album = albums[0]
    
        if not target_album:
            err_msg = "No valid Still Album found (and list is empty). Please create a 'Stills' album in Color Page."
            print(json.dumps({"status": "error", "message": err_msg}))
            raise Exception(err_msg) # Abort immediately
            # Let it continue to fail gracefully loop by loop? No, better warn.
             
     
        # === Main Loop ===
        success_count = 0
        processed_count = 0
        
        print(json.dumps({"status": "starting", "count": len(clips)}))
        
        for i, clip in enumerate(clips):
            name = clip["name"]
            try:
                frame_start = int(clip.get("frameStart", 0))
                frame_end = int(clip.get("frameEnd", 0))
                # name = clip.get("name", "unknown") # This line is removed
                
                # Get timeline frame rate
                # We need it for TC conversion
                # Note: timeline object is available
                fps = timeline.GetSetting("timelineFrameRate")
                
                # Revert to First Frame (User Request)
                # We use the provided 'tc' (which is Start TC) or calculate from frameStart
                
                target_tc = clip.get("tc", "")
                if not target_tc and frame_start > 0:
                     target_tc = frames_to_tc(frame_start, fps)
                
                if target_tc:
                     # print(json.dumps({"status": "debug", "message": f"Setting TC: {target_tc}"}))
                     timeline.SetCurrentTimecode(target_tc)
                     time.sleep(0.2) # Allow Resolve to seek
                
                # Force Switch to Target Album to ensure GrabStill puts it there
                if target_album:
                    gallery.SetCurrentStillAlbum(target_album)
    
                # Grab Still
                still = timeline.GrabStill()
                time.sleep(0.05) # Brief pause to ensures still is ready
                
                if not still:
                    # Retry once immediately without sleep
                    still = timeline.GrabStill()
                    
                if still:
                    # Clean up existing files for this clip name to prevent duplicates/stale files
                    # Resolve might export as name.jpg, name.1.1.1.jpg etc.
                    # We want to remove anything starting with 'name' and ending with our format
                    # === ROBUST EXPORT STRATEGY ===
                    
                    # 1. Snapshot valid files before
                    files_before = set(os.listdir(output_dir))
                    
                    # 2. Export with UNIQUE Name (UUID) to avoid collisions/overwriting
                    import uuid
                    temp_export_name = str(uuid.uuid4())
                    
                    # === EXPORT STRATEGY: BRUTE FORCE ===
                    # GrabStill puts the still somewhere. If we can't find it in Current, check ALL albums.
                    
                    success = False
                    export_album = None
                    
                    # Build list of albums to try (Current first, then others)
                    albums_to_try = []
                    
                    current = gallery.GetCurrentStillAlbum()
                    if current and current.GetLabel(): # Ensure label is valid
                        albums_to_try.append(current)
                        
                    all_albums = gallery.GetGalleryStillAlbums()
                    if all_albums:
                        for a in all_albums:
                            # Avoid duplicates and check label
                            lbl = a.GetLabel()
                            if not lbl: continue # Skip invalid albums
                            
                            if current and lbl == current.GetLabel(): continue
                            albums_to_try.append(a)
                    
                    # Fallback
                    if not albums_to_try and target_album:
                        albums_to_try.append(target_album)
                        
                    # Debug: Print Albums we are trying
                    album_names = [a.GetLabel() for a in albums_to_try]
                    # print(json.dumps({"status": "debug", "message": f"Attempting export from albums: {album_names}"}))
                    
                    # Try Export
                    for album in albums_to_try:
                        # Validate output dir access
                        if not os.access(output_dir, os.W_OK):
                             print(json.dumps({"status": "error", "message": f"Output dir not writable: {output_dir}"}))
                        
                        if album.ExportStills([still], output_dir, temp_export_name, export_format):
                            success = True
                            export_album = album
                            break
                        else:
                             pass
                    
                    if not success:
                        # FATAL ERROR - Abort Script
                        err_msg = f"FATAL: ExportStills failed from ALL {len(albums_to_try)} albums for {name}. Albums: {album_names} Dir: {output_dir}"
                        print(json.dumps({"status": "error", "message": err_msg}))
                        
                        # Try to cleanup the still so it doesn't pile up
                        try:
                            # We don't know which album it's in, but we can try to delete from 'current' or 'target'
                            if current: current.DeleteStills([still])
                            elif target_album: target_album.DeleteStills([still])
                        except:
                            pass
                            
                        raise Exception(err_msg) # Abort processing
                    else:
                        # Cleanup success
                        export_album.DeleteStills([still])
                    
                    # 3. Snapshot files after
                    files_after = set(os.listdir(output_dir))
                    new_files = list(files_after - files_before)
                    
                    # Filter for our export format
                    image_files = [f for f in new_files if f.lower().endswith(f".{export_format}")]
                    
                    if len(image_files) >= 1:
                        # We found a new file!
                        # It might be named `temp_export_name.jpg` OR `SceneName.jpg` (if Resolve ignored us).
                        # In ANY case, we rename it to what we want: `vfxName.jpg`.
                        
                        # Use the first new file found (should be only one per iteration usually)
                        exported_filename = image_files[0]
                        exported_path = os.path.join(output_dir, exported_filename)
                        
                        # Target
                        target_filename = f"{name}.{export_format}"
                        target_path = os.path.join(output_dir, target_filename)
                        
                        if exported_filename != target_filename:
                            try:
                                if os.path.exists(target_path):
                                    os.remove(target_path)
                                os.rename(exported_path, target_path)
                            except Exception as mv_err:
                                print(json.dumps({"status": "warning", "message": f"Failed to rename {exported_filename}: {mv_err}"}))
                                target_path = exported_path
                        
                        # 4. Resize
                        try:
                            result = subprocess.run(
                                ["sips", "--resampleHeight", str(resize_height), target_path], 
                                capture_output=True, 
                                text=True,
                                check=False
                            )
                        except Exception as sips_err:
                                print(json.dumps({"status": "warning", "message": f"Sips error: {sips_err}"}))
    
                    else:
                         print(json.dumps({"status": "warning", "message": f"No new image file detected for {name} (Export requested as {temp_export_name})."}))
    
                    processed_count += 1
                    
                    # === Progress Update ===
                    print(f"PROGRESS: {processed_count}/{len(clips)}")
                    sys.stdout.flush()
                else:
                    print(json.dumps({"status": "debug", "message": "GrabStill returned None"}))
                    
            except Exception as ex:
                 print(json.dumps({"status": "error", "message": f"Error processing {clip.get('name')}: {ex}"}))
                 # Re-raise FATAL errors to stop the loop
                 if "FATAL" in str(ex):
                     raise
                 
                 import traceback
                 traceback.print_exc()
                 # Continue to next
    finally:
        # Restore Tracks
        print(json.dumps({"status": "debug", "message": "Restoring tracks..."}))
        for i, state in track_states.items():
            if hasattr(timeline, "SetTrackEnable"):
                timeline.SetTrackEnable("video", i, state)
             
    # === Cleanup .drx files ===
    # Resolve exports .drx files with stills (grading data). We only want the PNGs.
    try:
        if os.path.exists(output_dir):
            for filename in os.listdir(output_dir):
                if filename.lower().endswith(".drx"):
                    file_path = os.path.join(output_dir, filename)
                    os.remove(file_path)
    except Exception as cleanup_Ex:
        print(f"Warning: Failed to cleanup .drx files: {cleanup_Ex}")

    print(json.dumps({"status": "success", "processed": processed_count, "folder": output_dir}))

except Exception as e:
    print(json.dumps({"error": f"Script Error: {str(e)}"}))
