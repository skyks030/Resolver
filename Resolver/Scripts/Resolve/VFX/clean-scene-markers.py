#!/usr/bin/env python3

import sys
import os
import importlib.util

# === Pfad zur DaVinci Resolve Scripting API (macOS) ===
sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")

# === API laden ===
if not os.path.exists(sdk_file):
    print(f"❌ SDK-Datei nicht gefunden: {sdk_file}")
    sys.exit(1)

spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
dvr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dvr)

import DaVinciResolveScript as dvr
resolve = dvr.scriptapp("Resolve")
if not resolve:
    print("❌ Verbindung zu DaVinci Resolve konnte nicht hergestellt werden.")
    sys.exit(1)

# === Projekt & Timeline ===
pm = resolve.GetProjectManager()
project = pm.GetCurrentProject()
timeline = project.GetCurrentTimeline()

if not project or not timeline:
    print("❌ Kein Projekt oder keine Timeline geöffnet.")
    sys.exit(1)

# === Marker suchen und löschen ===
markers = timeline.GetMarkers()
deleted_count = 0

if markers:
    # Wir sammeln erst die Frames, um Iterationsprobleme beim Löschen zu vermeiden
    frames_to_delete = []
    
    for frame_id, marker_data in markers.items():
        # Check Color und Note
        if marker_data['color'] == 'Cream' and marker_data['note'] == 'Resolver Scene Marker':
            frames_to_delete.append(frame_id)
            
    # Löschen
    for frame_id in frames_to_delete:
        if timeline.DeleteMarkerAtFrame(frame_id, "Cream"):
            deleted_count += 1
            
    print(f"✅ {deleted_count} Szenen-Marker wurden gelöscht.")
else:
    print("ℹ️ Keine Marker in der Timeline gefunden.")

# === Fokus zurück zu DaVinci Resolve ===
import subprocess
try:
    subprocess.run(["osascript", "-e", 'tell application "DaVinci Resolve" to activate'], check=False)
except Exception:
    pass
