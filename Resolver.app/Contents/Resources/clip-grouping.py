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

# === Bestehende Marker entfernen ===
timeline.DeleteMarkersByColor("All")
print("✅ Alle Timeline-Marker gelöscht.")


# === Zur Color Page wechseln ===
resolve.OpenPage("deliver")

# === Clips auf Videospur 1 analysieren ===
clips_v1 = timeline.GetItemListInTrack("video", 1)
if not clips_v1:
    print("❌ Keine Clips auf Videospur 1 gefunden.")
    sys.exit(1)

    

# === Gruppierung & Markierungen ===
track_count = timeline.GetTrackCount("video")
group_number = 1  # Startet bei 1 → ergibt 0010




for clip in clips_v1:
    clip_start = clip.GetStart()
    clip_end = clip.GetEnd()

    relative_start = clip_start - timeline_start_frame
    relative_end = clip_end - timeline_start_frame

    # Gruppennamen mit laufender Nummerierung in Zehnerschritten
    suffix = str(group_number * 10).zfill(4)
    group_name = f"{timeline_name}_{suffix}"
    group_number += 1

    # Gruppe erstellen
    color_group = project.AddColorGroup(group_name)
    print()
    print(f"VFX-Clip: {group_name}")
    if not color_group:
        print(f"❌ Gruppe '{group_name}' konnte nicht erstellt werden.")
        continue


    # Timeline-Marker setzen
    timeline.AddMarker(relative_start, "Green", "Start", group_name + " Start", 1)
    timeline.AddMarker(relative_end - 1, "Red", "Ende", group_name + " Ende", 1)
    print(f"    Start: {relative_start}, Ende: {relative_end - 1}")

    # Alle Clips aus allen Videospuren analysieren
    group_clips = []
    for track_index in range(1, track_count + 1):
        clips = timeline.GetItemListInTrack("video", track_index)
        for other in clips:
            if other.GetEnd() > clip_start and other.GetStart() < clip_end:
                group_clips.append(other)

    if not group_clips:
        print(f"⚠️ Keine passenden Clips im Bereich {clip_start}-{clip_end}")
        continue

    for item in group_clips:
        item.AssignToColorGroup(color_group)
        print(f"    {item.GetName()}")

resolve.OpenPage("edit")
