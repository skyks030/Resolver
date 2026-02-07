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

# === Marker für gültige Szenen-Namen sammeln ===
markers = timeline.GetMarkers()
valid_prefixes = set()

if markers:
    for frame_id, marker_data in markers.items():
        if marker_data['color'] == 'Cream':
            valid_prefixes.add(marker_data['name'])

if not valid_prefixes:
    print("⚠️ Keine 'Cream' Marker gefunden. Kann keine zugehörigen Gruppen identifizieren.")
    # Optional: Trotzdem weitermachen? Eher nein, um false positives zu vermeiden.
    sys.exit(0)

# === Gruppen löschen ===
current_groups = project.GetColorGroupsList()
deleted_count = 0

if current_groups:
    for group in current_groups:
        group_name = group.GetName()
        
        # Prüfen auf Muster: {MarkerName}_{4Digits}
        # Wir splitten am letzten Unterstrich
        if "_" in group_name:
            prefix, suffix = group_name.rsplit("_", 1)
            
            # Bedingungen:
            # 1. Prefix muss ein bekannter Marker-Name sein
            # 2. Suffix muss genau 4 Ziffern haben (z.B. 0010)
            if prefix in valid_prefixes and len(suffix) == 4 and suffix.isdigit():
                if project.DeleteColorGroup(group):
                    deleted_count += 1
                    # print(f"🗑️ Gelöscht: {group_name}")

print(f"✅ {deleted_count} Resolver-Farbgruppen gelöscht.")

