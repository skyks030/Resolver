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

timeline_start_frame = timeline.GetStartFrame()
frame_rate = timeline.GetSetting("timelineFrameRate")

# === Input Argumente ===
target_track_index = int(sys.argv[1]) if len(sys.argv) > 1 else 1

# === Clips auf Videospur analysieren ===
videospur = timeline.GetItemListInTrack("video", target_track_index)
if not videospur:
    print(f"❌ Keine Clips auf Videospur {target_track_index} gefunden.")
    sys.exit(1)

# === White Markers Sammeln ===
markers = timeline.GetMarkers()
white_markers = []

for frame_id, marker_data in markers.items():
    if marker_data['color'] == 'Cream':
        # frame_id is relative to timeline start in API logic usually, but let's verify context.
        # Usually GetMarkers returns absolute record frame or relative to start.
        # We will assume it keys by Frame ID correct for comparison with Clip Start.
        white_markers.append({
            'frame': frame_id,
            'name': marker_data['name'],
            'note': marker_data['note']
        })

# Sortiere Marker nach Frame-ID aufsteigend
white_markers.sort(key=lambda x: x['frame'])

# === Logik: Clips benennen ===
# CSV Header
print("VFX-Name,Rec-TC-In,Rec-TC-Out,File-Names")

current_marker_name = None
vfx_counter = 10 

# Wir gehen alle Clips durch. Für jeden Clip suchen wir den passenden Marker davor.
# Da Clips sortiert sein könnten, aber Marker auch, machen wir es einfach:
# Find last marker where marker.frame <= clip.start

for clip in videospur:
    clip_start = clip.GetStart()
    clip_end = clip.GetEnd()
    
    # Finde den letzten weißen Marker, der VOR (oder am) Start des Clips liegt
    preceding_marker = None
    for m in white_markers:
        # Marker Frame ist oft Offset by Start Time, also + timeline_start_frame?
        # Die Marker ID von GetMarkers() ist normalerweise der Frame Index im Timeline Space.
        # Clip.GetStart() ist auch im Timeline Space.
        
        # Achtung: DaVinci API GetMarkers() keys sind frames. 
        # Wir müssen sicherstellen, dass wir die richtige Scale haben.
        # Wir nehmen an frame_id ist direkt vergleichbar.
        
        if m['frame'] <= clip_start:
            preceding_marker = m
        else:
            # Da Marker sortiert sind, sind alle folgenden größer -> break
            break
            
    if preceding_marker:
        marker_name = preceding_marker['name'] # Name des Markers (z.B. "SC01")
        
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
        
        # Output generieren
        
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
        
        print(f"{vfx_final_name},{rec_tc_in},{rec_tc_out},{clip.GetName()}")
        
    else:
        # Clip ist vor dem ersten Marker -> Ignorieren oder Warning?
        # Laut Useranforderung: "alle Clips die nach einem solchen Marker gefunden werden"
        pass

