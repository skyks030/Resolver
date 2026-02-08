#!/usr/bin/env python3

import sys
import os
import importlib.util
import json

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

    # === Clips auf Videospur analysieren ===
    videospur = timeline.GetItemListInTrack("video", target_track_index)
    if not videospur:
        # Kein Fehler, sondern leeres Ergebnis, wenn keine Clips gefunden werden
        print(json.dumps([]))
        sys.exit(0)

    # === White Markers Sammeln ===
    markers = timeline.GetMarkers()
    white_markers = []

    if markers:
        for frame_id, marker_data in markers.items():
            # Check for EXACT Scene Marker attributes
            # Color: Cream
            # Note: Resolver Scene Marker
            note = marker_data.get('note', '')
            
            if marker_data['color'] == 'Cream' and note == 'Resolver Scene Marker':
                # FIX: Handle Relative vs Absolute Frames
                # If frame_id is very small (relative to start), add start_frame
                marker_abs = frame_id
                if frame_id < timeline_start_frame:
                    marker_abs = frame_id + timeline_start_frame
                    
                white_markers.append({
                    'frame': marker_abs,
                    'name': marker_data['name'],
                    'note': note
                })

    # Sortiere Marker nach Frame-ID aufsteigend
    white_markers.sort(key=lambda x: x['frame'])

    # === Logik: Clips benennen ===
    results = []
    current_marker_name = None
    vfx_counter = 10 

    for clip in videospur:
        clip_start = clip.GetStart()
        clip_end = clip.GetEnd()
        
        # Finde den letzten weißen Marker, der VOR (oder am) Start des Clips liegt
        preceding_marker = None
        for m in white_markers:
            if m['frame'] <= clip_start:
                preceding_marker = m
            else:
                break
            
        if preceding_marker:
            marker_name = preceding_marker['name']
            
            # Wenn wir einen neuen Marker-Bereich betreten, Counter resetten
            if marker_name != current_marker_name:
                current_marker_name = marker_name
                vfx_counter = 10
                
            # Suffix bauen
            suffix = str(vfx_counter).zfill(4)
            vfx_final_name = f"{current_marker_name}_{suffix}"
            
            # Counter erhöhen
            vfx_counter += 10
            
            # Marker setzen
            relative_start = clip_start - timeline_start_frame
            relative_end = clip_end - timeline_start_frame
            
            timeline.AddMarker(relative_start, "Green", vfx_final_name, "Resolver-Vfx-Marker", 1)
            timeline.AddMarker(relative_end - 1, "Red", vfx_final_name, "Resolver-Vfx-Marker", 1)
            
            # TC Berechnung
            rec_tc_in = frames_to_tc(clip_start, frame_rate)
            rec_tc_out = frames_to_tc(clip_end, frame_rate)

            # Source Metadata
            mp_item = clip.GetMediaPoolItem()
            reel_name = ""
            source_tc_in = ""
            source_tc_out = ""

            if mp_item:
                reel_name = mp_item.GetClipProperty("Reel Name") or ""
                file_start_tc = mp_item.GetClipProperty("Start TC")
                
                # If file_start_tc is empty, use "00:00:00:00" for calculation
                if not file_start_tc:
                    file_start_tc = "00:00:00:00"

                start_frames_abs = tc_to_frames(file_start_tc, frame_rate)
                # LeftOffset ist der Offset vom File-Start zum Clip-In
                offset = clip.GetLeftOffset()
                duration = clip.GetDuration()
                
                s_in = start_frames_abs + offset
                s_out = s_in + duration
                
                source_tc_in = frames_to_tc(s_in, frame_rate)
                source_tc_out = frames_to_tc(s_out, frame_rate)
            
            # Fallback für leere Source TCs
            if not source_tc_in: source_tc_in = "00:00:00:00"
            if not source_tc_out: source_tc_out = "00:00:00:00"
        
            results.append({
                "vfxName": str(vfx_final_name or ""),
                "tcIn": str(rec_tc_in or ""),
                "tcOut": str(rec_tc_out or ""),
                "sourceTcIn": str(source_tc_in or ""),
                "sourceTcOut": str(source_tc_out or ""),
                "fileNames": str(clip.GetName() or ""),
                "reelName": str(reel_name or ""),
                "frameStart": int(clip_start),
                "frameEnd": int(clip_end)
            })

    # Prepare Scene Markers for Export
    scene_markers_output = []
    for m in white_markers:
        scene_markers_output.append({
            "frameId": m['frame'],
            "color": "Cream",
            "name": m['name'],
            "note": m.get('note', ''),
            "duration": 1
        })

    # Output JSON Object
    final_output = {
        "clips": results,
        "sceneMarkers": scene_markers_output
    }

    output_file = os.environ.get("RESOLVER_OUTPUT_FILE")
    if output_file:
        with open(output_file, 'w') as f:
            json.dump(final_output, f, indent=2)
        # Optional: Print a small status message to stdout, which won't block
        print(f"✅ Data written to {output_file}")
    else:
        print(json.dumps(final_output, indent=2))
        sys.stdout.flush()

except Exception as e:
    # Wir printen den Fehler nicht als JSON-Array (was Swift erwartet), 
    # sondern als Text auf Stderr. Swift wird beim decode failen, aber das Output-Fenster zeigt den Stderr.
    sys.stderr.write(f"Fehler im Indexing-Script: {str(e)}")
    sys.exit(1)
