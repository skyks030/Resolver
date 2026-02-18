#!/usr/bin/env python3

import sys
import os
import importlib.util
import json
import traceback

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

# === Clips auf Videospur analysieren ===
target_track_index = int(sys.argv[1]) if len(sys.argv) > 1 else 1
print(f"🔍 Analysiere Clips auf Videospur: {target_track_index}")

vfx_clips = timeline.GetItemListInTrack("video", target_track_index)
if not vfx_clips:
    print(f"❌ Keine Clips auf Videospur {target_track_index} gefunden.")
    sys.exit(1)

# === JSON Map laden & Index-Driven Logic ===
json_clips = []
if len(sys.argv) > 2:
    json_path = sys.argv[2]
    if os.path.exists(json_path):
        try:
            with open(json_path, 'r') as f:
                json_clips = json.load(f)
            print(f"✅ Loaded {len(json_clips)} clips from Index.")
        except Exception as e:
            print(f"⚠️ Failed to load JSON Index: {e}")

# === Build Timeline Lookup Maps ===
# We need to find the clips on the timeline that correspond to the Index.
# We scan the target track once.
timeline_uid_map = {}
timeline_frame_map = {} # Fallback

for item in vfx_clips:
    try:
        uid = item.GetUniqueId()
        if uid:
            timeline_uid_map[uid] = item
        
        start_frame = int(item.GetStart())
        timeline_frame_map[start_frame] = item
    except:
        pass

# === CSV Header ===
print(f"GroupName,Clips-Count")
sys.stdout.flush()

# === Hauptschleife ===
# Fallback: If no JSON, iterate timeline clips (Legacy Mode)
items_to_process = []

if json_clips:
    print(json.dumps({"status": "starting", "count": len(json_clips), "mode": "index-driven"}))
    items_to_process = json_clips
else:
    print(json.dumps({"status": "starting", "count": len(vfx_clips), "mode": "legacy-timeline"}))
    # Create pseudo-objects for legacy mode
    for item in vfx_clips:
        items_to_process.append({
            "uniqueId": item.GetUniqueId(),
            "vfxName": item.GetName(),
            "frameStart": int(item.GetStart()),
            "_legacy_item": item 
        })

sys.stdout.flush()

processed_count = 0
total_clips = len(items_to_process)
track_count = timeline.GetTrackCount("video")

for i, entry in enumerate(items_to_process):
    try:
        # 1. Resolve Timeline Item
        timeline_item = None
        
        if "_legacy_item" in entry:
            timeline_item = entry["_legacy_item"]
        else:
            # Index-Driven Lookup
            uid = entry.get("uniqueId")
            frame_start = int(entry.get("frameStart", 0))
            
            if uid and uid in timeline_uid_map:
                timeline_item = timeline_uid_map[uid]
            elif frame_start in timeline_frame_map:
                 timeline_item = timeline_frame_map[frame_start]
        
        # If item not found on timeline, skip
        if not timeline_item:
            # print(json.dumps({"status": "debug", "message": f"Skipping {entry.get('vfxName')}: Not found on timeline."}))
            continue
            
        # 2. Get Current Data from Timeline Item
        # (It might have moved since indexing)
        vfx_in = timeline_item.GetStart()
        vfx_out = timeline_item.GetEnd()
        
        # 3. Determine Group Name (From Index!)
        vfx_name = entry.get("vfxName", "Untitled")
        
        # 4. Create/Get Color Group
        groups = project.GetColorGroupsList()
        target_group = None
        if groups:
             for g in groups:
                 if g.GetName() == vfx_name:
                     target_group = g
                     break
        
        if not target_group:
            target_group = project.AddColorGroup(vfx_name)
        
        if not target_group:
             print(json.dumps({"status": "error", "message": f"Konnte Gruppe {vfx_name} nicht erstellen."}))
             continue

        # 5. Find Overlapping Clips (Grouping)
        assigned_count = 0
        
        for track_idx in range(1, track_count + 1):
            track_items = timeline.GetItemListInTrack("video", track_idx)
            if not track_items: continue
            
            for item in track_items:
                # Check Overlap
                i_start = item.GetStart()
                i_end = item.GetEnd()
                
                if i_start < vfx_out and i_end > vfx_in:
                    item.AssignToColorGroup(target_group)
                    assigned_count += 1
        
        # CSV Output
        print(f"{vfx_name},{assigned_count}")
        sys.stdout.flush()

    except Exception as e:
        print(json.dumps({"status": "error", "message": f"Error item {i}: {str(e)}"}))
        # traceback.print_exc()
        sys.stdout.flush()

    processed_count += 1
    # Only print progress every 5 items or last one to reduce spam? 
    # Or just keep it.
    print(f"PROGRESS: {processed_count}/{total_clips}")
    sys.stdout.flush()

print(json.dumps({"status": "success", "processed": processed_count}))
