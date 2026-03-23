#!/usr/bin/env python3

import sys
import os
import importlib.util
import json

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

markers = data.get("markers", [])
if not markers:
    print(json.dumps({"status": "error", "message": "No clips provided in JSON payload."}))
    sys.exit(0)

try:
    # === Resolve API Setup ===
    sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
    sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")

    spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
    dvr = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dvr)

    import DaVinciResolveScript as dvr
    resolve = dvr.scriptapp("Resolve")
    
    if not resolve:
        raise Exception("Could not connect to DaVinci Resolve")

    project = resolve.GetProjectManager().GetCurrentProject()
    if not project:
         raise Exception("No active project")
         
    timeline = project.GetCurrentTimeline()
    if not timeline:
        raise Exception("No active timeline")

    start_frame = int(timeline.GetStartFrame())
    start_tc = timeline.GetStartTimecode() if hasattr(timeline, 'GetStartTimecode') else "01:00:00:00"
    fps_raw = timeline.GetSetting("timelineFrameRate")
    fps = float(fps_raw) if fps_raw else 25.0
    
    def tc_to_frames(target_tc_str, fps_val):
        parts = target_tc_str.replace(';', ':').split(':')
        if len(parts) >= 4:
            sh, sm, ss, sf = map(int, parts[:4])
            return int((sh * 3600 + sm * 60 + ss) * fps_val + sf)
        return 0

    start_tc_frames = tc_to_frames(start_tc, fps)
    
    # Cache all timeline clips to avoid repeated API calls
    all_timeline_clips = []
    track_count = timeline.GetTrackCount("video")
    print(f"PROGRESS: 0/{len(markers)}")
    sys.stdout.flush()

    for track_idx in range(1, track_count + 1):
        track_items = timeline.GetItemListInTrack("video", track_idx)
        if track_items:
            for item in track_items:
                all_timeline_clips.append(item)

    print(json.dumps({"status": "progress", "message": f"Cached {len(all_timeline_clips)} clips from {track_count} tracks."}))
    sys.stdout.flush()

    processed_count = 0
    assigned_total = 0

    for m in markers:
        processed_count += 1
        print(f"PROGRESS: {processed_count}/{len(markers)}")
        sys.stdout.flush()

        vfx_name = m.get("name")
        tc_in = m.get("tc")
        tc_out = m.get("note")  # We passed tcOut in the note field
        
        if not vfx_name or not tc_in or not tc_out:
            continue
            
        # Timecode parsing for Intersection Window
        in_frames = start_frame + (tc_to_frames(tc_in, fps) - start_tc_frames)
        out_frames = start_frame + (tc_to_frames(tc_out, fps) - start_tc_frames)
        
        # Ensure correct order
        if in_frames > out_frames:
            in_frames, out_frames = out_frames, in_frames

        # Get or Create Color Group
        groups = project.GetColorGroupsList()
        target_group = None
        if groups:
             for g in groups:
                 if g.GetName() == vfx_name:
                     target_group = g
                     break
        
        if not target_group:
            target_group = project.AddColorGroup(vfx_name)
        
        if not target_group:
             continue
             
        # Add intersecting clips to this color group
        assigned_count_for_clip = 0
        for item in all_timeline_clips:
            i_start = item.GetStart()
            i_end = item.GetEnd()
            
            # Simple overlap check: Item starts before VFX ends, AND Item ends after VFX starts
            if i_start < out_frames and i_end > in_frames:
                item.AssignToColorGroup(target_group)
                assigned_count_for_clip += 1
                assigned_total += 1
                
        print(f"{vfx_name},{assigned_count_for_clip}")
        sys.stdout.flush()

    print(json.dumps({
        "status": "success", 
        "processed": processed_count,
        "total_clips_grouped": assigned_total
    }))

except Exception as e:
    print(json.dumps({"error": f"Script Error: {str(e)}"}))
