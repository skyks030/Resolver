#!/usr/bin/env python3

import sys
import os
import importlib.util
import json
import traceback

try:
    # === Resolve API Setup ===
    # Check for custom path or standard path
    # On macOS, standard path is:
    sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
    sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")

    if not os.path.exists(sdk_file):
        print(json.dumps({"error": f"SDK not found at {sdk_file}"}))
        sys.exit(0) # Exit 0 to pass output to Swift

    spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
    dvr = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dvr)

    import DaVinciResolveScript as dvr
    resolve = dvr.scriptapp("Resolve")
    
    if not resolve:
        print(json.dumps({"error": "Could not connect to Resolve (scriptapp returned None). Is Resolve running?"}))
        sys.exit(0)

    pm = resolve.GetProjectManager()
    project = pm.GetCurrentProject()
    
    if not project:
         print(json.dumps({"error": "No active project found."}))
         sys.exit(0)
         
    timeline = project.GetCurrentTimeline()

    if not timeline:
        # No timeline is not an error, just empty list
        print(json.dumps([]))
        sys.exit(0)

    # === Get Markers ===
    markers = timeline.GetMarkers()
    result = []

    if markers:
        for frame_id, marker_data in markers.items():
            result.append({
                "frameId": frame_id,
                "color": marker_data['color'],
                "name": marker_data.get('name', ''),
                "note": marker_data.get('note', ''),
                "duration": marker_data.get('duration', 1)
            })

    # Sort by frame
    result.sort(key=lambda x: x['frameId'])

    print(json.dumps(result))

except Exception as e:
    # Catch-all for Python errors
    error_msg = f"Python Exception: {str(e)}"
    print(json.dumps({"error": error_msg}))

