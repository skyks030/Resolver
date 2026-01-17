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


resolve.OpenPage("edit")


# === Zur Color Page wechseln ===
#resolve.OpenPage("deliver")

# === Clips auf Videospur analysieren ===
target_track_index = int(sys.argv[1]) if len(sys.argv) > 1 else 1
print(f"🔍 Analysiere Clips auf Videospur: {target_track_index}")

clips_v1 = timeline.GetItemListInTrack("video", target_track_index)
if not clips_v1:
    print(f"❌ Keine Clips auf Videospur {target_track_index} gefunden.")
    sys.exit(1)

    

# === Gruppierung & Markierungen ===
track_count = timeline.GetTrackCount("video")
vfx_number = 1  # Startet bei 1 → ergibt 0010


print (f"VFX-Name,Rec-TC-In,Rec-TC-Out,File-Names")


for clip in clips_v1:
    vfx_in = clip.GetStart()
    vfx_out = clip.GetEnd()

    relative_start = vfx_in - timeline_start_frame
    relative_end = vfx_out - timeline_start_frame
    
    # Gruppennamen mit laufender Nummerierung in Zehnerschritten
    suffix = str(vfx_number * 10).zfill(4)
    vfx_name = f"{timeline_name}_{suffix}"
    vfx_number += 1
    #print(vfx_number,vfx_name)

    # Gruppe erstellen
    old_color_groups = project.GetColorGroupsList()
    for group in old_color_groups:
        if group.GetName() == vfx_name:
            project.DeleteColorGroup(group)
            

    color_group = project.AddColorGroup(vfx_name)
    if not color_group:
        print("❌ Gruppe konnte nicht erstellt werden. ")
        sys.exit(0)


  # timeline Marker löschen

    old_markers = timeline.GetMarkers()
    for frame_id, marker_name in old_markers.items():
        if marker_name["note"] == vfx_name:
            #print(f"  Note: {marker_name['note']}")
            timeline.DeleteMarkerAtFrame(frame_id)
            #timeline.DeleteMarker(marker_name['note'])
    

    # Timeline-Marker setzen
    timeline.AddMarker(relative_start, "Green", "VFX In", vfx_name, 1)
    timeline.AddMarker(relative_end - 1, "Red", "VFX Out", vfx_name, 1)

    
    # Alle Clips aus allen Videospuren analysieren und zur 'vfx_plates' hinzufügen
    vfx_plates = []
    for track_index in range(1, track_count + 1):
        clips = timeline.GetItemListInTrack("video", track_index)
        for clip in clips:
            if clip.GetEnd() > vfx_in and clip.GetStart() < vfx_out:
                vfx_plates.append(clip)

    

    # clip in 'vfx_plates' zu 'color_group' hinzufügen
    for item in vfx_plates:
        item.AssignToColorGroup(color_group)

    rec_tc_in = "{:02}:{:02}:{:02}:{:02}".format(
        int(vfx_in // (3600 * frame_rate)),
        int((vfx_in % (3600 * frame_rate)) // (60 * frame_rate)),
        int((vfx_in % (60 * frame_rate)) // frame_rate),
        int(vfx_in % frame_rate)
    )
    rec_tc_out = "{:02}:{:02}:{:02}:{:02}".format(
        int(vfx_out // (3600 * frame_rate)),
        int((vfx_out % (3600 * frame_rate)) // (60 * frame_rate)),
        int((vfx_out % (60 * frame_rate)) // frame_rate),
        int(vfx_out % frame_rate)
    )


    clip_file_names = ",".join([item.GetName() for item in vfx_plates])
    #source_tc_in = "\n".join([clip.GetStartTimecode() for item in group_clips])
    #source_tc_out = "\n".join([clip.GetEndTimecode() for item in group_clips])

    print(f"{vfx_name},{rec_tc_in},{rec_tc_out},{clip_file_names}")

resolve.OpenPage("edit")
