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
    # HH:MM:SS:FF or HH:MM:SS;FF
    try:
        # Normalize separators
        clean_tc = tc.replace(';', ':').replace('.', ':')
        parts = clean_tc.split(':')
        
        if len(parts) != 4:
            return 0
        h, m, s, f = map(int, parts)
        # Use simple calculation (approximate for NDF/DF mix, but robust enough for sorting)
        return int((h * 3600 + m * 60 + s) * fps + f)
    except ValueError:
        return 0

# === Timeline Infos ===
try:
    fps = float(timeline.GetSetting("timelineFrameRate"))
    start_frame = int(timeline.GetStartFrame())
    current_tc = timeline.GetCurrentTimecode()
    current_frame_abs = parse_timecode(current_tc, fps)
    
    print(f"ℹ️ Current Pos: {current_tc} -> {current_frame_abs} (Start: {start_frame})")
except Exception as e:
    print(f"❌ Fehler beim Lesen der Timeline-Daten: {e}")
    sys.exit(1)

# === Bestehende 'Cream' Marker analysieren ===
markers = timeline.GetMarkers()
cream_markers = []

if markers:
    for frame_id, marker_data in markers.items():
        if marker_data['color'] == 'Cream':
            # Fix: Check if Resolve returns relative or absolute frames
            # If marker frame is WAY smaller than start_frame, it's likely relative
            marker_abs = frame_id
            if frame_id < start_frame:
                marker_abs = frame_id + start_frame
            
            cream_markers.append({
                'frame': marker_abs,
                'name': marker_data['name']
            })

# Sortiere nach Frame
cream_markers.sort(key=lambda x: x['frame'])

# === Nächsten Namen bestimmen ===
next_number = 10
last_marker = None

# Finde den letzten Marker VOR oder AN der aktuellen Position
# Logik: Suche den nächstgelegenen Marker, der frames <= current ist.
for m in cream_markers:
    if m['frame'] <= current_frame_abs:
        last_marker = m
    else:
        # Da sortiert, sind alle folgenden größer -> Abbruch
        break

if last_marker:
    print(f"ℹ️ Vorherige Szene gefunden: {last_marker['name']} (Frame {last_marker['frame']})")
    try:
        # Versuche den Namen zu parsen (z.B. "0010")
        # Entferne mögliche Präfixe wie "SEQ_" falls vorhanden
        clean_name = last_marker['name'].replace("SEQ_", "").replace("_", "")
        last_number = int(clean_name)
        next_number = last_number + 10
    except ValueError:
        pass
else:
    print("ℹ️ Keine vorherige Szene gefunden. Starte bei 0010.")

new_name = str(next_number).zfill(4)

# === Marker setzen (Relativ zum Start) ===
add_pos_relative = current_frame_abs - start_frame

# Resolve AddMarker erwartet offset
if timeline.AddMarker(add_pos_relative, "Cream", new_name, "Resolver Scene Marker", 1):
    print(f"✅ Szenen-Marker '{new_name}' gesetzt bei Frame {current_frame_abs}.")
else:
    # Fallback: Manchmal sind Marker Absolute? Probieren wir Absolute wenn Relative fehlschlägt?
    print(f"❌ Fehler beim Setzen des Markers bei Frame {current_frame_abs} (Offset {add_pos_relative}).")

# === Fokus zurück zu DaVinci Resolve ===
import subprocess
try:
    subprocess.run(["osascript", "-e", 'tell application "DaVinci Resolve" to activate'], check=False)
except Exception:
    pass
