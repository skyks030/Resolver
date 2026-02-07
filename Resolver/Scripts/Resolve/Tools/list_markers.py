#!/usr/bin/env python3

import sys
import os
import importlib.util
import json

# === Resolve API Setup ===
sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")

if not os.path.exists(sdk_file):
    print(json.dumps({"error": "SDK not found"}))
    sys.exit(1)

spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
dvr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dvr)

import DaVinciResolveScript as dvr
resolve = dvr.scriptapp("Resolve")
if not resolve:
    print(json.dumps({"error": "Could not connect to Resolve"}))
    sys.exit(1)

pm = resolve.GetProjectManager()
project = pm.GetCurrentProject()
timeline = project.GetCurrentTimeline() if project else None

if not timeline:
    print(json.dumps([]))
    sys.exit(0)

# === Get Markers ===
markers = timeline.GetMarkers()
result = []

if markers:
    fps = timeline.GetSetting("timelineFrameRate")
    try:
        fps = float(fps)
    except:
        fps = 24.0
        
    start_frame = int(timeline.GetStartFrame())

    for frame_id, marker_data in markers.items():
        # Calculate Timecode
        # Frame ID is absolute? Or offset? GetMarkers usually returns absolute frames.
        # Let's assume absolute for display.
        
        # Determine TC string roughly (Resolve API doesn't give easy Frame->TC conv without workaround)
        # We'll just pass the Frame ID and Color, which are needed for deletion.
        
        result.append({
            "frameId": frame_id,
            "color": marker_data['color'],
            "name": marker_data['name'],
            "note": marker_data['note'],
            "duration": marker_data['duration']
        })

# Sort by frame
result.sort(key=lambda x: x['frameId'])

print(json.dumps(result))
