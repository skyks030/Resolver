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

if not action or action not in ["create", "delete"]:
    print(json.dumps({"error": "Invalid action. Must be 'create' or 'delete'."}))
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
    print(json.dumps({"status": "debug", "message": f"Timeline Start Frame: {start_frame}"}))
    
    count = 0
    failed_count = 0
    
    if action == "delete":
        # DeleteMarkerAtFrame expects Absolute Frame and Color
        
        for m in markers:
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
