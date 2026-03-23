#!/usr/bin/env python3

import sys
import os
import importlib.util
import json

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

action = data.get("action")
markers = data.get("markers", [])

if not action or action not in ["create", "delete", "delete_all_vfx"]:
    print(json.dumps({"error": "Invalid action. Must be 'create', 'delete', or 'delete_all_vfx'."}))
    sys.exit(1)

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
        raise Exception("Could not connect to Resolve")

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
    print(json.dumps({"status": "debug", "message": f"Timeline Start Frame: {start_frame}, Start TC: {start_tc}, FPS: {fps}"}))
    
    def tc_to_frames(target_tc_str, fps_val):
        parts = target_tc_str.replace(';', ':').split(':')
        if len(parts) >= 4:
            sh, sm, ss, sf = map(int, parts[:4])
            return int((sh * 3600 + sm * 60 + ss) * fps_val + sf)
        return 0

    start_tc_frames = tc_to_frames(start_tc, fps)
    
    count = 0
    failed_count = 0
    
    if action == "delete_all_vfx":
        # Scan entire timeline for "Resolver VFX-Marker" in notes
        markers_dict = timeline.GetMarkers()
        if markers_dict:
            for frame_id, marker_info in markers_dict.items():
                note = marker_info.get("note", "")
                if "Resolver VFX-Marker" in note:
                    if timeline.DeleteMarkerAtFrame(frame_id, marker_info.get("color", "")):
                        count += 1
                    else:
                        failed_count += 1
    elif action == "delete":
        # DeleteMarkerAtFrame expects Absolute Frame and Color
        
        for m in markers:
            if "tc" in m and m["tc"]:
                target_frames = tc_to_frames(m["tc"], fps)
                frame_abs = start_frame + (target_frames - start_tc_frames)
            else:
                frame_abs = int(m.get("frameId", 0))
                
            color = m.get("color", "Cream")
            
            # Try to delete (Absolute)
            if timeline.DeleteMarkerAtFrame(frame_abs, color):
                count += 1
            else:
                # Retry with offset (Relative to Start)
                frame_offset = frame_abs - start_frame
                if timeline.DeleteMarkerAtFrame(frame_offset, color):
                    count += 1
                else:
                    failed_count += 1
                
    elif action == "create":
        for m in markers:
            if "tc" in m and m["tc"]:
                target_frames = tc_to_frames(m["tc"], fps)
                frame_abs = start_frame + (target_frames - start_tc_frames)
            else:
                frame_abs = int(m.get("frameId", 0))
                
            color = m.get("color", "Cream")
            name = m.get("name", "")
            note = m.get("note", "")
            duration = int(m.get("duration", 1))
            
            # AddMarker expects OFFSET from Start Frame
            frame_offset = frame_abs - start_frame
            
            if timeline.AddMarker(frame_offset, color, name, note, duration):
                count += 1
            else:
                failed_count += 1

    print(json.dumps({
        "status": "success", 
        "count": count, 
        "failed": failed_count,
        "action": action,
        "total_attempted": len(markers)
    }))

except Exception as e:
    print(json.dumps({"error": f"Script Error: {str(e)}"}))
