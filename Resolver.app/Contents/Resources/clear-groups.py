
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

resolve.OpenPage("deliver")

# === Bestehende Gruppen entfernen ===
color_groups = project.GetColorGroupsList()
for group in color_groups:
    project.DeleteColorGroup(group)
print("✅ Alle Farbgruppen gelöscht.")
print()

resolve.OpenPage("Edit")
