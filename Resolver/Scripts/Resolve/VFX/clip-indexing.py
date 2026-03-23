#!/usr/bin/env python3

import sys
import os
import importlib.util
import json
import bisect

# === Helper für Timecode ===
def frames_to_tc(frames, fps):
    try:
        # Ensure fps is not zero to prevent division by zero
        if not fps or float(fps) == 0.0:
            return "00:00:00:00"
        
        # Convert fps to float for accurate calculations
        fps_float = float(fps)

        total_seconds = frames / fps_float
        
        hours = int(total_seconds // 3600)
        minutes = int((total_seconds % 3600) // 60)
        seconds = int(total_seconds % 60)
        frame_part = int(frames % fps_float) # Frames within the last second

        return "{:02}:{:02}:{:02}:{:02}".format(
            hours,
            minutes,
            seconds,
            frame_part
        )
    except Exception:
        return "00:00:00:00"

def tc_to_frames(tc, fps):
    try:
        if not tc: return 0
        parts = tc.split(':')
        if len(parts) != 4: return 0
        h, m, s, f = map(int, parts)
        
        # Ensure fps is not zero
        if not fps or float(fps) == 0.0:
            return 0
            
        return int((h * 3600 + m * 60 + s) * float(fps) + f)
    except Exception:
        return 0

try:
    # === Pfad zur DaVinci Resolve Scripting API (macOS) ===
    sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
    sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")

    # === API laden ===
    if not os.path.exists(sdk_file):
        raise FileNotFoundError(f"SDK-Datei nicht gefunden: {sdk_file}")

    spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
    dvr = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dvr)

    import DaVinciResolveScript as dvr
    resolve = dvr.scriptapp("Resolve")
    if not resolve:
        raise ConnectionError("Verbindung zu DaVinci Resolve konnte nicht hergestellt werden.")

    # === Projekt & Timeline ===
    pm = resolve.GetProjectManager()
    project = pm.GetCurrentProject()
    
    if not project:
        raise ValueError("Kein Projekt in DaVinci Resolve geöffnet.")

    timeline = project.GetCurrentTimeline()
    if not timeline:
        raise ValueError("Keine Timeline in DaVinci Resolve geöffnet.")

    timeline_start_frame = timeline.GetStartFrame()
    frame_rate = timeline.GetSetting("timelineFrameRate")

    # === Input Argumente ===
    target_track_index = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    output_file_path = os.environ.get("RESOLVER_TMP_OUT")
    
    # Check for end marker flag (default: False)
    vfx_end_marker_enabled = False
    if len(sys.argv) > 2:
        vfx_end_marker_enabled = sys.argv[2].lower() == "true"

    # Check for renaming map
    renaming_map = {}
    if len(sys.argv) > 3:
        renaming_map_path = sys.argv[3]
        if os.path.exists(renaming_map_path):
             try:
                 with open(renaming_map_path, 'r') as f:
                     renaming_map = json.load(f)
             except Exception as e:
                 print(json.dumps({"status": "debug", "message": f"Failed to load renaming map: {e}"}))

    # === Analyze Timeline ===
    timeline_name = timeline.GetName()
    track_count = timeline.GetTrackCount("video")

    # === Clips auf Videospur analysieren ===
    videospur = timeline.GetItemListInTrack("video", target_track_index)
    if not videospur:
        videospur = []

    # Sort clips by Start Frame
    videospur.sort(key=lambda x: x.GetStart())
    
    # === START STREAMING OUTPUT ===
    if output_file_path:
        out_f = open(output_file_path, 'w', encoding='utf-8')
    else:
        out_f = sys.stdout

    # Write CSV Header
    header = ["Clip Name", "Rec TC In", "Rec TC Out", "Source TC In", "Source TC Out", "Duration", "File Name", "Reel Name"]
    out_f.write(",".join(header) + "\n")
    
    clip_count = len(videospur)
    
    for i, clip in enumerate(videospur):
        # Progress Update for UI
        print(f"PROGRESS: {i+1}/{clip_count}")
        sys.stdout.flush()

        clip_start = clip.GetStart()
        clip_end = clip.GetEnd()
        
        # TC Berechnung
        rec_tc_in = frames_to_tc(clip_start, frame_rate)
        rec_tc_out = frames_to_tc(clip_end, frame_rate)

        # Source Metadata
        mp_item = clip.GetMediaPoolItem()
        reel_name = ""
        source_tc_in = ""
        source_tc_out = ""
        clip_name = clip.GetName() or "Untitled"
        
        file_name = clip_name
        
        if mp_item:
            reel_name = mp_item.GetClipProperty("Reel Name") or ""
            file_name = mp_item.GetName() or clip_name
            file_start_tc = mp_item.GetClipProperty("Start TC")
            
            if not file_start_tc:
                file_start_tc = "00:00:00:00"

            start_frames_abs = tc_to_frames(file_start_tc, frame_rate)
            offset = clip.GetLeftOffset()
            duration = clip.GetDuration()
            
            s_in = start_frames_abs + offset
            s_out = s_in + duration
            
            source_tc_in = frames_to_tc(s_in, frame_rate)
            source_tc_out = frames_to_tc(s_out, frame_rate)
        else:
            source_tc_in = "00:00:00:00"
            source_tc_out = "00:00:00:00"
            
        duration = clip.GetDuration()
        
        # Format for CSV (escape commas if necessary)
        # Instead of importing csv module, just replace commas with semicolons for safety
        def safe_csv(val):
            return str(val).replace(",", ";")
            
        row = [
            safe_csv(clip_name),
            safe_csv(rec_tc_in),
            safe_csv(rec_tc_out),
            safe_csv(source_tc_in),
            safe_csv(source_tc_out),
            str(duration),
            safe_csv(file_name),
            safe_csv(reel_name)
        ]
        
        out_f.write(",".join(row) + "\n")
        
        if i % 50 == 0:
            out_f.flush()

    # Cleanup
    if output_file_path:
        out_f.close()
        print(f"✅ Data written to {output_file_path}")
    else:
        out_f.flush()
        
except Exception as e:
    sys.stderr.write(f"Fehler im Indexing-Script: {str(e)}")
    sys.exit(1)
