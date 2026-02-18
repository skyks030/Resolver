#!/usr/bin/env python3

import sys
import os
import importlib.util
import json
import bisect

# === Helper für Timecode ===
def frames_to_tc(frames, fps):
    try:
        # Ensure fps is not zero to prevent division by zero
        if not fps or float(fps) == 0.0:
            return "00:00:00:00"
        
        # Convert fps to float for accurate calculations
        fps_float = float(fps)

        total_seconds = frames / fps_float
        
        hours = int(total_seconds // 3600)
        minutes = int((total_seconds % 3600) // 60)
        seconds = int(total_seconds % 60)
        frame_part = int(frames % fps_float) # Frames within the last second

        return "{:02}:{:02}:{:02}:{:02}".format(
            hours,
            minutes,
            seconds,
            frame_part
        )
    except Exception:
        return "00:00:00:00"

def tc_to_frames(tc, fps):
    try:
        if not tc: return 0
        parts = tc.split(':')
        if len(parts) != 4: return 0
        h, m, s, f = map(int, parts)
        
        # Ensure fps is not zero
        if not fps or float(fps) == 0.0:
            return 0
            
        return int((h * 3600 + m * 60 + s) * float(fps) + f)
    except Exception:
        return 0

try:
    # === Pfad zur DaVinci Resolve Scripting API (macOS) ===
    sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
    sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")

    # === API laden ===
    if not os.path.exists(sdk_file):
        raise FileNotFoundError(f"SDK-Datei nicht gefunden: {sdk_file}")

    spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
    dvr = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dvr)

    import DaVinciResolveScript as dvr
    resolve = dvr.scriptapp("Resolve")
    if not resolve:
        raise ConnectionError("Verbindung zu DaVinci Resolve konnte nicht hergestellt werden.")

    # === Projekt & Timeline ===
    pm = resolve.GetProjectManager()
    project = pm.GetCurrentProject()
    
    if not project:
        raise ValueError("Kein Projekt in DaVinci Resolve geöffnet.")

    timeline = project.GetCurrentTimeline()
    if not timeline:
        raise ValueError("Keine Timeline in DaVinci Resolve geöffnet.")

    timeline_start_frame = timeline.GetStartFrame()
    frame_rate = timeline.GetSetting("timelineFrameRate")

    # === Input Argumente ===
    target_track_index = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    output_file_path = os.environ.get("RESOLVER_OUTPUT_FILE")
    
    # Check for end marker flag (default: False)
    vfx_end_marker_enabled = False
    if len(sys.argv) > 2:
        vfx_end_marker_enabled = sys.argv[2].lower() == "true"

    # Check for renaming map
    renaming_map = {}
    if len(sys.argv) > 3:
        renaming_map_path = sys.argv[3]
        if os.path.exists(renaming_map_path):
             try:
                 with open(renaming_map_path, 'r') as f:
                     renaming_map = json.load(f)
             except Exception as e:
                 print(json.dumps({"status": "debug", "message": f"Failed to load renaming map: {e}"}))

    # === Analyze Timeline ===
    timeline_name = timeline.GetName()
    track_count = timeline.GetTrackCount("video")

    # === Clips auf Videospur analysieren ===
    videospur = timeline.GetItemListInTrack("video", target_track_index)
    if not videospur:
        videospur = []

    # Sort clips by Start Frame to ensure sequential processing
    # efficient marker lookup relies on sequential order or valid lookups
    # Sorting is cheap for a few thousand items
    videospur.sort(key=lambda x: x.GetStart())

    # === White Markers Sammeln ===
    markers = timeline.GetMarkers()
    white_markers = []

    if markers:
        for frame_id, marker_data in markers.items():
            # Check for EXACT Scene Marker attributes
            # Color: Cream
            # Note: Resolver Scene Marker
            note = marker_data.get('note', '')
            
            if marker_data['color'] == 'Cream' and note == 'Resolver Scene Marker':
                # FIX: Handle Relative vs Absolute Frames
                # If frame_id is very small (relative to start), add start_frame
                marker_abs = frame_id
                if frame_id < timeline_start_frame:
                    print(json.dumps({"status": "debug", "message": f"Fixing Relative Marker {frame_id} -> {frame_id + timeline_start_frame}"}))
                    marker_abs = frame_id + timeline_start_frame
                    
                white_markers.append({
                    'frame': marker_abs,
                    'name': marker_data['name'],
                    'note': note
                })

    # Sortiere Marker nach Frame-ID aufsteigend
    white_markers.sort(key=lambda x: x['frame'])
    
    # Prepare lookup list for bisect
    marker_frames = [m['frame'] for m in white_markers]
    
    # === START STREAMING OUTPUT ===
    # Open file (or stdout wrapper)
    if output_file_path:
        out_f = open(output_file_path, 'w', encoding='utf-8')
    else:
        out_f = sys.stdout

    # Write JSON Header
    out_f.write('{\n  "clips": [\n')

    # === Logik: Clips benennen & Streamen ===
    current_marker_name = None
    vfx_counter = 10 
    
    clip_count = len(videospur)
    
    # Pre-calculate reserved names from renaming map
    reserved_names = set(renaming_map.values())
    used_names = set()
    
    for i, clip in enumerate(videospur):
        # Progress Update for UI
        # Format: PROGRESS: <current>/<total>
        print(f"PROGRESS: {i+1}/{clip_count}")
        sys.stdout.flush() # Ensure immediate output

        clip_start = clip.GetStart()
        clip_end = clip.GetEnd()
        
        # Optimize: Use bisect to find preceding marker
        # finding right insertion point gives index where all elements to left are <=
        # actually bisect_right gives elements <= x if we look at idx-1
        idx = bisect.bisect_right(marker_frames, clip_start)
        if idx > 0:
            preceding_marker = white_markers[idx - 1]
            marker_name = preceding_marker['name']
        else:
            preceding_marker = None
            marker_name = "NO_SCENE"
            
        # Wenn wir einen neuen Marker-Bereich betreten, Counter resetten
        if marker_name != current_marker_name:
            current_marker_name = marker_name
            vfx_counter = 10
            
        # Collision Detection Loop
        while True:
            suffix = str(vfx_counter).zfill(4)
            
            if current_marker_name == "NO_SCENE":
                 calculated_name = suffix
            else:
                 calculated_name = f"{current_marker_name}_{suffix}"
            
            # Check collisions
            is_reserved = False
            
            if calculated_name in reserved_names:
                 is_reserved = True
            if calculated_name in used_names:
                 is_reserved = True
                 
            if is_reserved:
                 vfx_counter += 10 # Try next
                 # Safety break? No, assuming eventually we find one.
            else:
                 vfx_final_name = calculated_name
                 # Don't increment yet, we need to register it first
                 break
        
        # Capture Original Name (Sequential Unique)
        original_vfx_name = vfx_final_name
        
        # Check for Manual Rename (Priority: Map)
        # We need UniqueID
        uid = clip.GetUniqueId()
        if uid and uid in renaming_map:
             vfx_final_name = renaming_map[uid] # Override with manual name
             # Note: Manual names are allowed to collide if user forced them? 
             # Or should we check collision for manual names too? 
             # Usually manual wins.
        elif vfx_final_name in renaming_map: # Legacy / Non-UID Map
             vfx_final_name = renaming_map[vfx_final_name]

        # Register THIS name as used
        used_names.add(vfx_final_name)
        
        # Increment for NEXT clip
        vfx_counter += 10
            
        # Marker setzen
        relative_start = clip_start - timeline_start_frame
        relative_end = clip_end - timeline_start_frame
        
        timeline.AddMarker(relative_start, "Green", vfx_final_name, "Resolver-Vfx-Marker", 1)
        
        if vfx_end_marker_enabled:
            timeline.AddMarker(relative_end - 1, "Red", vfx_final_name, "Resolver-Vfx-Marker", 1)
        
        # TC Berechnung
        rec_tc_in = frames_to_tc(clip_start, frame_rate)
        rec_tc_out = frames_to_tc(clip_end, frame_rate)

        # Source Metadata
        mp_item = clip.GetMediaPoolItem()
        reel_name = ""
        source_tc_in = ""
        source_tc_out = ""
        
        if mp_item:
            reel_name = mp_item.GetClipProperty("Reel Name") or ""
            file_start_tc = mp_item.GetClipProperty("Start TC")
            
            # If file_start_tc is empty, use "00:00:00:00" for calculation
            if not file_start_tc:
                file_start_tc = "00:00:00:00"

            start_frames_abs = tc_to_frames(file_start_tc, frame_rate)
            # LeftOffset ist der Offset vom File-Start zum Clip-In
            offset = clip.GetLeftOffset()
            duration = clip.GetDuration()
            
            s_in = start_frames_abs + offset
            s_out = s_in + duration
            
            source_tc_in = frames_to_tc(s_in, frame_rate)
            source_tc_out = frames_to_tc(s_out, frame_rate)
            
            # Fallback für leere Source TCs
            if not source_tc_in: source_tc_in = "00:00:00:00"
            if not source_tc_out: source_tc_out = "00:00:00:00"
        
        # Build Clip Dict
        clip_data = {
            "uniqueId": str(clip.GetUniqueId() or ""),
            "vfxName": str(vfx_final_name or ""),
            "originalVfxName": str(original_vfx_name or ""),
            "tcIn": str(rec_tc_in or ""),
            "tcOut": str(rec_tc_out or ""),
            "sourceTcIn": str(source_tc_in or ""),
            "sourceTcOut": str(source_tc_out or ""),
            "fileNames": str(clip.GetName() or ""),
            "reelName": str(reel_name or ""),
            "frameStart": int(clip_start),
            "frameEnd": int(clip_end),
            "duration": int(clip.GetDuration())
        }
        
        # Stream Write
        # Write INDENTED manually for readability or just dump
        out_f.write("    ") # indent
        json.dump(clip_data, out_f)
        
        # Add comma if not last element
        if i < clip_count - 1:
            out_f.write(",\n")
        else:
            out_f.write("\n")
            
        # Flush periodically (e.g. every 50 clips) to ensure disk write
        if i % 50 == 0:
            out_f.flush()

    # === Write Scene Markers & Footer ===
    out_f.write('  ],\n') # Close clips array
    
    scene_markers_output = []
    for m in white_markers:
        scene_markers_output.append({
            "frameId": m['frame'],
            "color": "Cream",
            "name": m['name'],
            "note": m.get('note', ''),
            "duration": 1
        })

    # Prepare Debug & Footer Data
    # === Finalizing ===
    print(f"PROGRESS: Finalizing/...")
    sys.stdout.flush()

    # Prepare Debug & Footer Data
    # track_distribution removed for performance on large timelines
    
    raw_markers_debug = []
    if markers:
        # Limit debug markers to 10
        count = 0
        for frame_id, marker_data in markers.items():
            if count >= 10: break
            raw_markers_debug.append({
                "frame": frame_id,
                "color": marker_data['color'],
                "note": marker_data.get('note', ''),
                "name": marker_data['name']
            })
            count += 1

    warning_msg = ""
    if not white_markers:
        warning_msg = "No Scene Markers found. Clips have been indexed without scene contexts."

    footer_data = {
        "sceneMarkers": scene_markers_output,
        "warning": warning_msg,
        "debug_track_received": target_track_index,
        "debug_timeline_name": timeline_name,
        "debug_track_count": track_count,
        # "debug_track_distribution": track_distribution, # REMOVED
        "debug_raw_markers": raw_markers_debug,
        "debug_white_markers_count": len(white_markers)
    }

    # Write Footer keys manually to merge into the main object
    # We already wrote "clips": [ ... ],
    # Now we write the rest of the keys
    
    # sceneMarkers
    out_f.write('  "sceneMarkers": ')
    json.dump(scene_markers_output, out_f, indent=2)
    out_f.write(',\n')
    
    # warning
    out_f.write('  "warning": ')
    json.dump(warning_msg, out_f)
    out_f.write(',\n')
    
    # Debug info
    out_f.write('  "debug_timeline_name": ')
    json.dump(timeline_name, out_f)
    
    # Close main object
    out_f.write('\n}')
    
    # Cleanup
    if output_file_path:
        out_f.close()
        print(f"✅ Data written to {output_file_path}")
    else:
        out_f.flush()
        
except Exception as e:
    sys.stderr.write(f"Fehler im Indexing-Script: {str(e)}")
    sys.exit(1)
