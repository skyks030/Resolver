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
    current_album = gallery.GetCurrentStillAlbum()
    if not current_album:
         print(json.dumps({"status": "debug", "message": "GetCurrentStillAlbum returned None. Using fallback logic?"}))
         # If current album is None, we might not be able to proceed unless we find one.
         
    target_album = current_album # Default fallback
    
    # Try to find "resolver_temp_stills" in existing albums
    found_album = False
    albums = gallery.GetGalleryStillAlbums()
    
    if albums:
        for album in albums:
            if album.GetLabel() == "resolver_temp_stills":
                gallery.SetCurrentStillAlbum(album)
                target_album = album
                found_album = True
                break
    
    # Logic for creation is missing in standard API (Verify??)
    # If not found, we use current but warn? 
    # User Request: "Dieser Stills-Ordner soll heißen: 'resolver_temp_stills'"
    # If we can't create, we might have to just use the current one and be careful.
    


    # === Processing ===
    processed_count = 0
    
    print(json.dumps({"status": "starting", "count": len(clips)}))
    
    try:
        for clip in clips:
            try:
                frame_start = int(clip.get("frameStart", 0))
                frame_end = int(clip.get("frameEnd", 0))
                name = clip.get("name", "unknown")
                
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
                
                # Grab Still
                # print(json.dumps({"status": "debug", "message": "Grabbing Still..."}))
                
                # Verify what is at the current timecode on the target track
                # This helps debug why GrabStill might return None (e.g. empty space)
                # Note: This is an expensive check, so only do it if we are debugging or having issues?
                # For now, let's just log the TC we are jumping to.
                
                still = timeline.GrabStill()
                
                if not still:
                    # Retry once immediately without sleep
                    still = timeline.GrabStill()
                    
                if not still:
                     # One more try after moving slightly?
                     pass
                     
                if still:
                    # Clean up existing files for this clip name to prevent duplicates/stale files
                    # Resolve might export as name.jpg, name.1.1.1.jpg etc.
                    # We want to remove anything starting with 'name' and ending with our format
                    try:
                        existing_files = [f for f in os.listdir(output_dir) if f.startswith(name) and f.lower().endswith(f".{export_format}")]
                        for ef in existing_files:
                            os.remove(os.path.join(output_dir, ef))
                    except Exception as clean_err:
                        print(json.dumps({"status": "warning", "message": f"Failed to clean old files for {name}: {clean_err}"}))

                    # Export
                    target_album.ExportStills([still], output_dir, name, export_format)
                    target_album.DeleteStills([still])
                    
                    # Resize using sips
                    # Resolve might append suffixes (e.g. name.1.1.1.jpg)
                    # Let's find the file we just exported.
                    found_files = [f for f in os.listdir(output_dir) if f.startswith(name) and f.lower().endswith(f".{export_format}")]
                    
                    if found_files:
                        # Use the most recent or matching file
                        img_path = os.path.join(output_dir, found_files[0])
                        # print(json.dumps({"status": "debug", "message": f"Resizing {img_path}..."}))
                        
                        try:
                            result = subprocess.run(
                                ["sips", "--resampleHeight", str(resize_height), img_path], 
                                capture_output=True, 
                                text=True,
                                check=False
                            )
                            if result.returncode != 0:
                                print(json.dumps({"status": "warning", "message": f"Sips failed for {name}: {result.stderr}"}))
                            # else:
                            #    print(json.dumps({"status": "debug", "message": f"Sips success: {result.stdout}"}))
                        except Exception as sips_err:
                             print(json.dumps({"status": "warning", "message": f"Sips execution error: {sips_err}"}))
                    else:
                        print(json.dumps({"status": "warning", "message": f"Could not find exported image for {name} to resize."}))
                        # print(json.dumps({"status": "debug", "message": f"Dir content: {os.listdir(output_dir)}"}))

                    processed_count += 1
                    
                    # === Progress Update ===
                    print(f"PROGRESS: {processed_count}/{len(clips)}")
                    sys.stdout.flush()
                else:
                    print(json.dumps({"status": "debug", "message": "GrabStill returned None"}))
                    
            except Exception as ex:
                 print(json.dumps({"status": "error", "message": f"Error processing {clip.get('name')}: {ex}"}))
                 import traceback
                 traceback.print_exc()
                 # Continue to next
    finally:
        # Restore Tracks
        # print(json.dumps({"status": "debug", "message": "Restoring tracks..."}))
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
