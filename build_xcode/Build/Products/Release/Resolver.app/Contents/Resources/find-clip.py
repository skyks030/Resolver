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

project_manager = resolve.GetProjectManager()
project = project_manager.GetCurrentProject()
media_pool = project.GetMediaPool()

# 📌 Den im MediaPool aktuell ausgewählten Clip holen
selected_folder = media_pool.GetCurrentFolder()
selected_items_dict = selected_folder.GetSelectedItems  # ohne ()!

if not selected_items_dict:
    print("⚠️ Kein Clip im MediaPool ausgewählt.")
    sys.exit(1)

selected_clip = list(selected_items_dict.values())[0]
selected_media_id = selected_clip.GetMediaId()
print(f"🎞️ Verwende ausgewählten Clip: {selected_clip.GetName()}")

# 🔍 Suche in allen Timelines nach dem Clip
timeline_count = project.GetTimelineCount()
if timeline_count == 0:
    print("⚠️ Keine Timelines im Projekt.")
    sys.exit(1)

for i in range(1, timeline_count + 1):
    timeline = project.GetTimelineByIndex(i)
    timeline_name = timeline.GetName()
    print(f"📂 Durchsuche Timeline: {timeline_name}")

    found_any = False
    track_types = ["video", "audio"]
    for track_type in track_types:
        track_count = timeline.GetTrackCount(track_type)
        for track_index in range(1, track_count + 1):
            clips = timeline.GetItemListInTrack(track_type, track_index)
            for clip in clips:
                mpi = clip.GetMediaPoolItem()
                if mpi and mpi.GetMediaId() == selected_media_id:
                    found_any = True
                    clip_start = clip.GetStart()
                    timeline_start = timeline.GetStartFrame()

                    marker_frame = clip_start
                    marker_color = "Blue"
                    marker_name = f"Marker für: {selected_clip.GetName()}"
                    timeline.AddMarker(marker_frame, marker_color, marker_name, "", 1, "")
                    print(f"✅ Marker gesetzt in '{timeline_name}' bei Frame {marker_frame}")

    if not found_any:
        print(f"🔎 Kein Vorkommen in Timeline: {timeline_name}")

print("✅ Fertig.")
