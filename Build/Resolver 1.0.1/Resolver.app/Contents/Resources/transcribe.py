import sys
import os
import importlib.util
import tkinter as tk
from tkinter import filedialog

# === Resolve API laden ===
sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")

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

# === Datei(en) auswählen ===
root = tk.Tk()
root.withdraw()
file_paths = filedialog.askopenfilenames(title="Wähle Datei(en) zum Importieren")

if not file_paths:
    print("❌ Keine Dateien ausgewählt.")
    sys.exit(0)

# === Import in Media Pool ===
media_pool.ImportMedia(list(file_paths))
print(f"✅ {len(file_paths)} Datei(en) importiert.")

current_folder = media_pool.GetCurrentFolder()

current_folder.TranscribeAudio()
