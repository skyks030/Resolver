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

def safe_csv(val):
    # Instead of importing csv module, just replace commas with semicolons for safety
    return str(val).replace(",", ";")

def extract_timeline_rows(timeline, target_track_index, episode_number, out_f, progress_base, progress_total):
    """Scans one timeline's target video track and writes a CSV row per clip,
    tagging every row with episode_number (may be ""). progress_base/
    progress_total let 'PROGRESS: x/y' report correctly across multiple
    timelines when indexing several episodes back to back in one run.
    Returns the number of clips written."""
    frame_rate = timeline.GetSetting("timelineFrameRate")

    videospur = timeline.GetItemListInTrack("video", target_track_index)
    if not videospur:
        videospur = []
    videospur.sort(key=lambda x: x.GetStart())

    for i, clip in enumerate(videospur):
        # Progress Update for UI
        print(f"PROGRESS: {progress_base + i + 1}/{progress_total}")
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

        row = [
            safe_csv(clip_name),
            safe_csv(rec_tc_in),
            safe_csv(rec_tc_out),
            safe_csv(source_tc_in),
            safe_csv(source_tc_out),
            str(duration),
            safe_csv(file_name),
            safe_csv(reel_name),
            safe_csv(episode_number)
        ]

        out_f.write(",".join(row) + "\n")

        if i % 50 == 0:
            out_f.flush()

    return len(videospur)

def find_timeline(project, unique_id, name):
    """Look up a registered Timeline object in the project's Timeline registry
    by unique id (preferred, stable across renames) or, failing that, by
    name. Returns None if neither matches anything (e.g. the timeline was
    renamed or deleted since the Episode Manager last re-indexed)."""
    try:
        count = int(project.GetTimelineCount() or 0)
    except Exception:
        count = 0

    by_name = None
    for i in range(1, count + 1):
        try:
            tl = project.GetTimelineByIndex(i)
        except Exception:
            tl = None
        if not tl:
            continue

        if unique_id and hasattr(tl, "GetUniqueId"):
            try:
                if tl.GetUniqueId() == unique_id:
                    return tl
            except Exception:
                pass

        if by_name is None and name:
            try:
                if tl.GetName() == name:
                    by_name = tl
            except Exception:
                pass

    return by_name

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

    # Whatever the user currently has open — used as the single timeline to
    # index in the default (non-all-episodes) path, and restored at the end
    # of an all-episodes run so Resolve's UI doesn't stay parked on whichever
    # episode was indexed last.
    original_timeline = project.GetCurrentTimeline()

    # === Input Argumente ===
    # Positional args are always passed (as "" when unused) by the Swift side,
    # so indices never shift depending on which optional features are active.
    target_track_index = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    # Must match the env var PyScriptRunner.swift actually sets (RESOLVER_OUTPUT_FILE).
    # If this is wrong, out_f falls back to stdout, and the interleaved "PROGRESS: x/y"
    # print() lines end up mixed into the CSV data the app reads back.
    output_file_path = os.environ.get("RESOLVER_OUTPUT_FILE")

    # Check for end marker flag (default: False)
    vfx_end_marker_enabled = False
    if len(sys.argv) > 2:
        vfx_end_marker_enabled = sys.argv[2].lower() == "true"

    # Check for renaming map
    renaming_map = {}
    renaming_map_path = sys.argv[3] if len(sys.argv) > 3 else ""
    if renaming_map_path and os.path.exists(renaming_map_path):
        try:
            with open(renaming_map_path, 'r') as f:
                renaming_map = json.load(f)
        except Exception as e:
            print(json.dumps({"status": "debug", "message": f"Failed to load renaming map: {e}"}))

    # Episodes map: a list of {"timelineName", "timelineUniqueId", "episodeNumber"}
    # registered via the Episode Manager.
    episodes_list = []
    episodes_map_path = sys.argv[4] if len(sys.argv) > 4 else ""
    if episodes_map_path and os.path.exists(episodes_map_path):
        try:
            with open(episodes_map_path, 'r') as f:
                episodes_list = json.load(f)
        except Exception as e:
            print(json.dumps({"status": "debug", "message": f"Failed to load episodes map: {e}"}))

    # "Index All Episodes": auto-open + index every registered episode's
    # timeline in one pass instead of just whatever is currently open.
    all_episodes = len(sys.argv) > 5 and sys.argv[5].lower() == "true"

    # === Resolve what we're about to index, and validate it, BEFORE touching
    # RESOLVER_OUTPUT_FILE. PyScriptRunner treats "output file exists and is
    # non-empty" as success regardless of exit code (it prefers that file over
    # stdout/stderr/termination status) — so writing even just the CSV header
    # ahead of a validation failure would silently present a raised error as a
    # successful, empty (or partial) import. Everything that can raise must
    # happen first; only once we know there is real work to do do we open the
    # output stream and start writing to it. ===
    if all_episodes and episodes_list:
        # Resolve every registered episode to an actual Timeline object up
        # front, in episode-number order, skipping (not failing on) any whose
        # timeline can no longer be found — e.g. renamed/deleted since the
        # Episode Manager last re-indexed.
        resolved = []
        for ep in sorted(episodes_list, key=lambda e: e.get("episodeNumber", 0)):
            tl = find_timeline(project, ep.get("timelineUniqueId"), ep.get("timelineName"))
            if tl is None:
                print(json.dumps({"status": "debug", "message": f"Episode {ep.get('episodeNumber')} timeline '{ep.get('timelineName')}' not found, skipping."}))
                continue
            resolved.append((tl, str(ep.get("episodeNumber", ""))))

        if not resolved:
            raise ValueError("Keine der registrierten Episoden-Timelines wurde im Projekt gefunden.")

        # Pre-count clips across every resolved timeline so 'PROGRESS: x/y' is
        # accurate for the whole multi-episode run, not just the last timeline.
        counts = []
        for tl, _ in resolved:
            try:
                items = tl.GetItemListInTrack("video", target_track_index) or []
            except Exception:
                items = []
            counts.append(len(items))
        total_count = sum(counts)
    else:
        if original_timeline is None:
            raise ValueError("Keine Timeline in DaVinci Resolve geöffnet.")

        # Check whether the currently open timeline matches one of the
        # registered episodes, so its clips get tagged with that episode
        # number (single-timeline path — unchanged from before).
        timeline_name = original_timeline.GetName()
        episode_number = ""
        for ep in episodes_list:
            if ep.get("timelineName") == timeline_name:
                episode_number = str(ep.get("episodeNumber", ""))
                break

        try:
            total_count = len(original_timeline.GetItemListInTrack("video", target_track_index) or [])
        except Exception:
            total_count = 0

    # === START STREAMING OUTPUT === (only reached once validation above succeeded)
    if output_file_path:
        out_f = open(output_file_path, 'w', encoding='utf-8')
    else:
        out_f = sys.stdout

    # Write CSV Header
    header = ["Clip Name", "Rec TC In", "Rec TC Out", "Source TC In", "Source TC Out", "Duration", "File Name", "Reel Name", "Episode"]
    out_f.write(",".join(header) + "\n")

    if all_episodes and episodes_list:
        progress_base = 0
        for (tl, episode_number), count in zip(resolved, counts):
            try:
                project.SetCurrentTimeline(tl)
            except Exception as e:
                print(json.dumps({"status": "debug", "message": f"Failed to switch to episode {episode_number} timeline, skipping: {e}"}))
                progress_base += count
                continue
            extract_timeline_rows(tl, target_track_index, episode_number, out_f, progress_base, total_count)
            progress_base += count

        if original_timeline is not None:
            try:
                project.SetCurrentTimeline(original_timeline)
            except Exception:
                pass
    else:
        extract_timeline_rows(original_timeline, target_track_index, episode_number, out_f, 0, total_count)

    # Cleanup
    if output_file_path:
        out_f.close()
        print(f"✅ Data written to {output_file_path}")
    else:
        out_f.flush()

except Exception as e:
    sys.stderr.write(f"Fehler im Indexing-Script: {str(e)}")
    sys.exit(1)
