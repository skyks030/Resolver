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

# === Helper: TC zu Frames ===
def parse_timecode(tc, fps):
    # HH:MM:SS:FF
    try:
        parts = tc.split(':')
        if len(parts) != 4:
            return 0
        h, m, s, f = map(int, parts)
        return int((h * 3600 + m * 60 + s) * fps + f)
    except ValueError:
        return 0

# === Timeline Infos ===
try:
    fps = float(timeline.GetSetting("timelineFrameRate"))
    start_frame = int(timeline.GetStartFrame())
    current_tc = timeline.GetCurrentTimecode()
    current_frame_abs = parse_timecode(current_tc, fps)
except Exception as e:
    print(f"❌ Fehler beim Lesen der Timeline-Daten: {e}")
    sys.exit(1)

# === Bestehende 'Cream' Marker analysieren ===
markers = timeline.GetMarkers()
cream_markers = []

if markers:
    for frame_id, marker_data in markers.items():
        if marker_data['color'] == 'Cream':
            cream_markers.append({
                'frame': frame_id, # Frame ID ist meist absolut in Resolve
                'name': marker_data['name']
            })

# Sortiere nach Frame
cream_markers.sort(key=lambda x: x['frame'])

# === Nächsten Namen bestimmen ===
next_number = 10
last_marker = None

# Finde den letzten Marker VOR oder AN der aktuellen Position
for m in cream_markers:
    if m['frame'] <= current_frame_abs:
        last_marker = m
    else:
        break

if last_marker:
    try:
        # Versuche den Namen zu parsen (z.B. "0010")
        last_number = int(last_marker['name'])
        next_number = last_number + 10
    except ValueError:
        pass

new_name = str(next_number).zfill(4)

# === Marker setzen (Relativ zum Start) ===
add_pos_relative = current_frame_abs - start_frame

# Resolve AddMarker erwartet offset
if timeline.AddMarker(add_pos_relative, "Cream", new_name, "Resolver Scene Marker", 1):
    print(f"✅ Szenen-Marker '{new_name}' gesetzt bei Frame {current_frame_abs} (Rel: {add_pos_relative}).")
else:
    # Fallback: Manchmal sind Marker Absolute? Probieren wir Absolute wenn Relative fehlschlägt?
    # Nein, API Dokumentation sagt Offset. Aber wir können loggen.
    print(f"❌ Fehler beim Setzen des Markers bei Frame {current_frame_abs}.")

# === Fokus zurück zu DaVinci Resolve ===
import subprocess
try:
    subprocess.run(["osascript", "-e", 'tell application "DaVinci Resolve" to activate'], check=False)
except Exception:
    pass
