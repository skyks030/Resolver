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

timeline_name = timeline.GetName()
timeline_start_frame = timeline.GetStartFrame()
frame_rate = timeline.GetSetting("timelineFrameRate")

#resolve.OpenPage("edit")

# === Clips auf Videospur analysieren ===
target_track_index = int(sys.argv[1]) if len(sys.argv) > 1 else 1
print(f"🔍 Analysiere Clips auf Videospur: {target_track_index}")
print(f"DEBUG: sys.argv: {sys.argv}")

vfx_clips = timeline.GetItemListInTrack("video", target_track_index)
if not vfx_clips:
    print(f"❌ Keine Clips auf Videospur {target_track_index} gefunden.")
    sys.exit(1)

# === Gruppierung ===
track_count = timeline.GetTrackCount("video")

# === Marker für Benennung sammeln (wie in clip-indexing.py) ===
import json

app_clips_map = {} # frame_start -> vfx_name

# Check for JSON input (renamed clips)
if len(sys.argv) > 2:
    json_path = sys.argv[2]
    if os.path.exists(json_path):
        try:
            with open(json_path, 'r') as f:
                clips_data = json.load(f)
                # Build map: frameStart -> vfxName
                for c in clips_data:
                    # Key is string in JSON? We generally get int or string
                    fs = int(c.get("frameStart", 0))
                    name = c.get("vfxName", "")
                    if fs > 0 and name:
                        app_clips_map[fs] = name
            
            if not app_clips_map:
                 print(f"⚠️ JSON loaded but map is empty. Raw Data: {clips_data}")
            else:
                 print(f"✅ Loaded {len(app_clips_map)} renamed clips from App.")
        except Exception as e:
            print(f"⚠️ Failed to load JSON map: {e}")

markers = timeline.GetMarkers()
white_markers = []

if markers:
    for frame_id, marker_data in markers.items():
        if marker_data['color'] == 'Cream':
            white_markers.append({
                'frame': frame_id,
                'name': marker_data['name']
            })

# Sortiere Marker nach Frame-ID aufsteigend
white_markers.sort(key=lambda x: x['frame'])

print (f"GroupName,Clips-Count")

current_marker_name = None
vfx_counter = 10

# ... (imports remain)
import traceback

# ... (previous code remains until the loop)

print(json.dumps({"status": "starting", "count": len(vfx_clips)}))

processed_count = 0
total_clips = len(vfx_clips)

for i, clip in enumerate(vfx_clips):
    try:
        vfx_in = clip.GetStart()
        vfx_out = clip.GetEnd()
        
        vfx_name = ""
        
        # 1. Check if we have an exact match from App Data
        # STRICT MATCH ONLY (User Request)
        if vfx_in in app_clips_map:
            vfx_name = app_clips_map[vfx_in]
            print(json.dumps({"status": "debug", "message": f"Match found for frame {vfx_in}: {vfx_name}"}))
        else:
            # print(f"⚠️ No JSON match for frame {vfx_in}. Map keys: {list(app_clips_map.keys())[:5]}...")
            # Fallback: Use Marker Logic
            
            # Finde den letzten weißen Marker, der VOR (oder am) Start des Clips liegt
            preceding_marker = None
            for m in white_markers:
                if m['frame'] <= vfx_in:
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
                vfx_name = f"{current_marker_name}_{suffix}"
                
                # Counter erhöhen
                vfx_counter += 10
                
        if vfx_name:
            
            # Gruppe erstellen / bereinigen
            old_color_groups = project.GetColorGroupsList()
            # Vorherige Gruppe gleichen Namens löschen (Clean Start)
            for group in old_color_groups:
                if group.GetName() == vfx_name:
                    project.DeleteColorGroup(group)

            color_group = project.AddColorGroup(vfx_name)
            if not color_group:
                print(json.dumps({"status": "error", "message": f"Gruppe '{vfx_name}' konnte nicht erstellt werden."}))
                continue

            # Alle Clips aus allen Videospuren analysieren und zur 'vfx_plates' hinzufügen
            vfx_plates = []
            
            # Durchlaufe alle Spuren um zugehörige Clips zu finden
            for track_index in range(1, track_count + 1):
                # Hole Clips der aktuellen Spur
                current_track_clips = timeline.GetItemListInTrack("video", track_index)
                if not current_track_clips:
                    continue
                    
                for item in current_track_clips:
                    # Prüfen ob der Clip im Zeitfenster des VFX-Clips liegt (Schnittmenge)
                    if item.GetEnd() > vfx_in and item.GetStart() < vfx_out:
                        vfx_plates.append(item)

            # Clips der Gruppe zuweisen
            for item in vfx_plates:
                item.AssignToColorGroup(color_group)

            print(json.dumps({"status": "debug", "message": f"Created group {vfx_name} with {len(vfx_plates)} clips"}))

    except Exception as e:
        print(json.dumps({"status": "error", "message": f"Error processing clip {i}: {str(e)}"}))
        traceback.print_exc()

    processed_count += 1
    print(f"PROGRESS: {processed_count}/{total_clips}")
    sys.stdout.flush()

print(json.dumps({"status": "success", "processed": processed_count}))



#resolve.OpenPage("edit")
