#!/usr/bin/env python3
"""
export-scene-markers.py
Reads all Cream-coloured markers from the current DaVinci Resolve timeline
and prints them as CSV lines: name,startTC
One line per marker, sorted by timecode position.
"""

import sys
import os
import importlib.util

# === Load DaVinci Resolve API ===
sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")

if not os.path.exists(sdk_file):
    print(f"ERROR: DaVinci Resolve SDK not found at {sdk_file}")
    sys.exit(1)

spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
dvr_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dvr_mod)

import DaVinciResolveScript as dvr
resolve = dvr.scriptapp("Resolve")

if not resolve:
    print("ERROR: Cannot connect to DaVinci Resolve. Make sure it is running and External Scripting is enabled.")
    sys.exit(1)

pm = resolve.GetProjectManager()
if not pm:
    print("ERROR: Could not get Project Manager from DaVinci Resolve.")
    sys.exit(1)

project = pm.GetCurrentProject()
if not project:
    print("ERROR: No project is currently open in DaVinci Resolve.")
    sys.exit(1)

timeline = project.GetCurrentTimeline()
if not timeline:
    print("ERROR: No timeline is currently open in DaVinci Resolve.")
    sys.exit(1)

# === Parse timecode from frame number ===
try:
    fps_raw = timeline.GetSetting("timelineFrameRate")
    fps = float(fps_raw) if fps_raw else 25.0
    start_frame = int(timeline.GetStartFrame())
    start_tc = timeline.GetStartTimecode() if hasattr(timeline, 'GetStartTimecode') else "01:00:00:00"
except Exception as e:
    print(f"ERROR: Could not read timeline settings: {e}")
    sys.exit(1)

def frames_to_tc(absolute_frame, fps, start_frame, start_tc_str):
    """Convert an absolute frame number to a timecode string."""
    try:
        # Parse start_tc into frames
        parts = start_tc_str.replace(';', ':').split(':')
        sh, sm, ss, sf = map(int, parts)
        start_tc_frames = int((sh * 3600 + sm * 60 + ss) * fps + sf)
        
        total_frames = start_tc_frames + (absolute_frame - start_frame)
        
        fps_int = int(fps)
        ff = total_frames % fps_int
        total_seconds = total_frames // fps_int
        ss2 = total_seconds % 60
        total_minutes = total_seconds // 60
        mm = total_minutes % 60
        hh = total_minutes // 60
        return f"{hh:02d}:{mm:02d}:{ss2:02d}:{ff:02d}"
    except Exception:
        return "00:00:00:00"

# === Read markers ===
markers = timeline.GetMarkers()
if not markers:
    print("INFO: No markers found on this timeline.")
    sys.exit(0)

scene_markers = []
for frame_id, data in markers.items():
    if data.get("color", "") == "Cream":
        # Resolve can return relative or absolute frame IDs
        abs_frame = frame_id
        if frame_id < start_frame:
            abs_frame = frame_id + start_frame
        tc = frames_to_tc(abs_frame, fps, start_frame, start_tc)
        name = data.get("name", "").strip() or f"Scene_{len(scene_markers)+1}"
        scene_markers.append((abs_frame, name, tc))

# Sort by frame
scene_markers.sort(key=lambda x: x[0])

if not scene_markers:
    print("INFO: No Cream (scene) markers found on this timeline.")
    sys.exit(0)

# === Output CSV ===
print("SCENES_CSV_START")
print("name,startTC")
for _, name, tc in scene_markers:
    safe_name = name.replace(",", ";")
    print(f"{safe_name},{tc}")
print("SCENES_CSV_END")
print(f"SUCCESS: Found {len(scene_markers)} scene marker(s).")
