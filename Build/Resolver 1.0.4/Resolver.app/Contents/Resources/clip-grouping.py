#!/usr/bin/env python3

import sys
import os
import importlib.util
import csv
import tempfile

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

# === Bestehende Marker entfernen ===
#timeline.DeleteMarkersByColor("All")
#print("✅ Alle Timeline-Marker gelöscht.")


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


print (f"VFX-Name,Rec-TC-In,Rec-TC-Out,File-Names")

for clip in clips_v1:
    clip_start = clip.GetStart()
    clip_end = clip.GetEnd()

    relative_start = clip_start - timeline_start_frame
    relative_end = clip_end - timeline_start_frame
    
    rec_tc_in = "{:02}:{:02}:{:02}:{:02}".format(
    int(clip_start // (3600 * frame_rate)),
    int((clip_start % (3600 * frame_rate)) // (60 * frame_rate)),
    int((clip_start % (60 * frame_rate)) // frame_rate),
    int(clip_start % frame_rate)
    )
    rec_tc_out = "{:02}:{:02}:{:02}:{:02}".format(
    int(clip_end // (3600 * frame_rate)),
    int((clip_end % (3600 * frame_rate)) // (60 * frame_rate)),
    int((clip_end % (60 * frame_rate)) // frame_rate),
    int(clip_end % frame_rate)
    )

    # Gruppennamen mit laufender Nummerierung in Zehnerschritten
    suffix = str(group_number * 10).zfill(4)
    group_name = f"{timeline_name}_{suffix}"
    group_number += 1
    #print({group_number},{group_name})

    # Gruppe erstellen
    color_group = project.AddColorGroup(group_name)
    if not color_group:
        print("❌ Gruppe konnte nicht erstellt werden. ")
        sys.exit(1)


    # Timeline-Marker setzen
    timeline.AddMarker(relative_start, "Green", "VFX start", group_name, 1)
    timeline.AddMarker(relative_end - 1, "Red", "VFX end", group_name, 1)

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


    clip_file_names = ",".join([item.GetName() for item in group_clips])
    #source_tc_in = "\n".join([clip.GetStartTimecode() for item in group_clips])
    #source_tc_out = "\n".join([clip.GetEndTimecode() for item in group_clips])

    print(f"{group_name},{rec_tc_in},{rec_tc_out},{clip_file_names}")

resolve.OpenPage("edit")
