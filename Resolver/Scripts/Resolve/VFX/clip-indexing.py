#!/usr/bin/env python3

import sys
import os
import importlib.util
import json

# === Pfad zur DaVinci Resolve Scripting API (macOS) ===
sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")

# === API laden ===
if not os.path.exists(sdk_file):
    print(json.dumps({"error": f"SDK-Datei nicht gefunden: {sdk_file}"}))
    sys.exit(1)

spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
dvr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dvr)

import DaVinciResolveScript as dvr
resolve = dvr.scriptapp("Resolve")
if not resolve:
    print(json.dumps({"error": "Verbindung zu DaVinci Resolve konnte nicht hergestellt werden."}))
    sys.exit(1)

# === Projekt & Timeline ===
pm = resolve.GetProjectManager()
project = pm.GetCurrentProject()
timeline = project.GetCurrentTimeline()

if not project or not timeline:
    print(json.dumps({"error": "Kein Projekt oder keine Timeline geöffnet."}))
    sys.exit(1)

timeline_start_frame = timeline.GetStartFrame()
frame_rate = timeline.GetSetting("timelineFrameRate")

# === Input Argumente ===
target_track_index = int(sys.argv[1]) if len(sys.argv) > 1 else 1

# === Clips auf Videospur analysieren ===
videospur = timeline.GetItemListInTrack("video", target_track_index)
if not videospur:
    print(json.dumps({"error": f"Keine Clips auf Videospur {target_track_index} gefunden."}))
    sys.exit(1)

# === White Markers Sammeln ===
markers = timeline.GetMarkers()
white_markers = []

if markers:
    for frame_id, marker_data in markers.items():
        if marker_data['color'] == 'Cream':
            white_markers.append({
                'frame': frame_id,
                'name': marker_data['name'],
                'note': marker_data['note']
            })

# Sortiere Marker nach Frame-ID aufsteigend
white_markers.sort(key=lambda x: x['frame'])

# === Logik: Clips benennen ===
results = []
current_marker_name = None
vfx_counter = 10 

for clip in videospur:
    clip_start = clip.GetStart()
    clip_end = clip.GetEnd()
    
    # Finde den letzten weißen Marker, der VOR (oder am) Start des Clips liegt
    preceding_marker = None
    for m in white_markers:
        if m['frame'] <= clip_start:
            preceding_marker = m
        else:
            break
            
    if preceding_marker:
        marker_name = preceding_marker['name']
        
        # Wenn wir einen neuen Marker-Bereich betreten, Counter resetten
        if marker_name != current_marker_name:
            current_marker_name = marker_name
            vfx_counter = 10
            
        # Suffix bauen
        suffix = str(vfx_counter).zfill(4)
        vfx_final_name = f"{current_marker_name}_{suffix}"
        
        # Counter erhöhen
        vfx_counter += 10
        
        # Marker setzen
        relative_start = clip_start - timeline_start_frame
        relative_end = clip_end - timeline_start_frame
        
        timeline.AddMarker(relative_start, "Green", vfx_final_name, "Resolver-Vfx-Marker", 1)
        timeline.AddMarker(relative_end - 1, "Red", vfx_final_name, "Resolver-Vfx-Marker", 1)
        
        # TC Berechnung
        def frames_to_tc(frames, fps):
            return "{:02}:{:02}:{:02}:{:02}".format(
                int(frames // (3600 * fps)),
                int((frames % (3600 * fps)) // (60 * fps)),
                int((frames % (60 * fps)) // fps),
                int(frames % fps)
            )
            
        rec_tc_in = frames_to_tc(clip_start, frame_rate)
        rec_tc_out = frames_to_tc(clip_end, frame_rate)
        
        results.append({
            "vfxName": vfx_final_name,
            "tcIn": rec_tc_in,
            "tcOut": rec_tc_out,
            "fileNames": clip.GetName()
        })

print(json.dumps(results, indent=2))



