#!/usr/bin/env python3

import sys
import os
import importlib.util

# Args: ScriptName, FrameID, Color
if len(sys.argv) < 3:
    print("❌ Error: Missing arguments (Frame ID, Color)")
    sys.exit(1)

frame_id = int(sys.argv[1])
color = sys.argv[2]

# === Resolve API Setup ===
sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")

if not os.path.exists(sdk_file):
    # fail silently or text output
    sys.exit(1)

spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
dvr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dvr)

import DaVinciResolveScript as dvr
resolve = dvr.scriptapp("Resolve")
if not resolve:
    sys.exit(1)

pm = resolve.GetProjectManager()
project = pm.GetCurrentProject()
timeline = project.GetCurrentTimeline() if project else None

if not timeline:
    print("❌ No Timeline")
    sys.exit(1)

# === Delete Marker ===
# DeleteMarkerAtFrame(frame, color)
if timeline.DeleteMarkerAtFrame(frame_id, color):
    print("✅ Marker deleted")
else:
    print("❌ Failed to delete marker")

# Refresh UI
import subprocess
try:
    subprocess.run(["osascript", "-e", 'tell application "DaVinci Resolve" to activate'], check=False)
except:
    pass
