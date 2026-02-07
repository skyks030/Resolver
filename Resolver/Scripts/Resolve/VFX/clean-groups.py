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

# === Ziel-Liste erstellen ===
# Wir simulieren die Namen, die durch clip-grouping.py erstellt worden wären.
# Annahme: Track 1 wird verwendet.

target_track_index = 1 
clips_v1 = timeline.GetItemListInTrack("video", target_track_index)

if not clips_v1:
    print(f"⚠️ Keine Clips auf Videospur {target_track_index} gefunden. Keine Gruppen zu löschen?")
    sys.exit(0)

expected_group_names = set()
vfx_number = 1 

for clip in clips_v1:
    # Namensschema aus clip-grouping.py:
    # suffix = str(vfx_number * 10).zfill(4)
    # vfx_name = f"{timeline_name}_{suffix}"
    
    suffix = str(vfx_number * 10).zfill(4)
    vfx_name = f"{timeline_name}_{suffix}"
    expected_group_names.add(vfx_name)
    vfx_number += 1

# === Gruppen löschen ===
current_groups = project.GetColorGroupsList()
deleted_count = 0

if current_groups:
    for group in current_groups:
        group_name = group.GetName()
        
        # Prüfen ob der Gruppen-Name in unserer erwarteten Liste ist
        if group_name in expected_group_names:
            if project.DeleteColorGroup(group):
                deleted_count += 1
                # print(f"🗑️ Gelöscht: {group_name}")

print(f"✅ {deleted_count} Resolver-Farbgruppen gelöscht.")
