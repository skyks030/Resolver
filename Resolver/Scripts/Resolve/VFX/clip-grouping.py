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

resolve.OpenPage("edit")

# === Clips auf Videospur analysieren ===
target_track_index = int(sys.argv[1]) if len(sys.argv) > 1 else 1
print(f"🔍 Analysiere Clips auf Videospur: {target_track_index}")

vfx_clips = timeline.GetItemListInTrack("video", target_track_index)
if not vfx_clips:
    print(f"❌ Keine Clips auf Videospur {target_track_index} gefunden.")
    sys.exit(1)

# === Gruppierung ===
track_count = timeline.GetTrackCount("video")
vfx_number = 1  # Startet bei 1 → ergibt 0010

print (f"GroupName,Clips-Count")

for clip in vfx_clips:
    vfx_in = clip.GetStart()
    vfx_out = clip.GetEnd()

    # Gruppennamen mit laufender Nummerierung in Zehnerschritten
    suffix = str(vfx_number * 10).zfill(4)
    vfx_name = f"{timeline_name}_{suffix}"
    vfx_number += 1

    # Gruppe erstellen / bereinigen
    old_color_groups = project.GetColorGroupsList()
    for group in old_color_groups:
        if group.GetName() == vfx_name:
            project.DeleteColorGroup(group)

    color_group = project.AddColorGroup(vfx_name)
    if not color_group:
        print(f"❌ Gruppe '{vfx_name}' konnte nicht erstellt werden.")
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
            # Wir nutzen hier > in und < out um sicherzustellen, dass er relevant ist.
            if item.GetEnd() > vfx_in and item.GetStart() < vfx_out:
                vfx_plates.append(item)

    # Clips der Gruppe zuweisen
    for item in vfx_plates:
        item.AssignToColorGroup(color_group)

    print(f"{vfx_name},{len(vfx_plates)}")

resolve.OpenPage("edit")
