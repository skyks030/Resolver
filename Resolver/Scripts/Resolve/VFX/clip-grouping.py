#!/usr/bin/env python3

import sys
import os
import importlib.util
import json

def log(message):
    """Debug breadcrumb, shown in Resolver's Debug Mode console. Every meaningful step prints
    one of these so a hang or crash can be pinpointed to the exact step it happened at."""
    print(json.dumps({"status": "debug", "message": message}))
    sys.stdout.flush()

if len(sys.argv) < 2:
    print(json.dumps({"error": "Missing JSON input file path"}))
    sys.exit(1)

json_path = sys.argv[1]
log(f"Loading payload from {json_path}")

if not os.path.exists(json_path):
    print(json.dumps({"error": f"JSON file not found: {json_path}"}))
    sys.exit(1)

try:
    with open(json_path, 'r') as f:
        data = json.load(f)
except Exception as e:
    print(json.dumps({"error": f"Failed to parse JSON: {e}"}))
    sys.exit(1)

action = data.get("action", "create")
markers = data.get("markers", [])
log(f"action={action}, shots={len(markers)}")

if not markers:
    # Use the same top-level "error" key as every other failure path in this file (and in
    # batch_marker_op.py) — ProjectExportView.handleBatchOpResult only surfaces `error`, not a
    # "status":"error" shape, so this message would otherwise be silently dropped in favor of a
    # generic fallback.
    print(json.dumps({"error": "No clips provided in JSON payload."}))
    sys.exit(0)

def tc_to_frames(target_tc_str, fps_val):
    parts = target_tc_str.replace(';', ':').split(':')
    if len(parts) >= 4:
        sh, sm, ss, sf = map(int, parts[:4])
        return int((sh * 3600 + sm * 60 + ss) * fps_val + sf)
    return 0

def find_timeline(project, unique_id, name):
    """Look up a registered Timeline object by unique id (preferred, stable across
    renames) or, failing that, by name. Returns None if neither matches anything."""
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
    # === Resolve API Setup ===
    log("Loading DaVinci Resolve Scripting API...")
    sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
    sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")

    spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
    dvr = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dvr)

    import DaVinciResolveScript as dvr
    log("Connecting to Resolve...")
    resolve = dvr.scriptapp("Resolve")

    if not resolve:
        raise Exception("Could not connect to DaVinci Resolve")

    log("Getting current project...")
    project = resolve.GetProjectManager().GetCurrentProject()
    if not project:
         raise Exception("No active project")

    if action == "delete":
        # Color Groups are project-level, not timeline-scoped, so deleting them needs no
        # timeline switching at all: just remove every group whose name exactly matches one
        # of the given VFX names (replaces the old Cream-marker-prefix heuristic, which
        # didn't generalize across episodes).
        target_names = {m.get("name") for m in markers if m.get("name")}
        color_groups = project.GetColorGroupsList() or []
        log(f"Found {len(color_groups)} existing color group(s); {len(target_names)} VFX name(s) targeted for deletion.")

        matching_groups = [g for g in color_groups if g.GetName() in target_names]
        total_to_delete = len(matching_groups)
        print(f"PROGRESS: 0/{max(total_to_delete, 1)}")
        sys.stdout.flush()

        deleted_count = 0
        for i, g in enumerate(matching_groups):
            if project.DeleteColorGroup(g):
                deleted_count += 1
            print(f"PROGRESS: {i + 1}/{total_to_delete}")
            sys.stdout.flush()

        log(f"Done. Deleted {deleted_count}/{total_to_delete} color group(s).")
        print(json.dumps({"status": "success", "processed": deleted_count, "total_clips_grouped": 0}))
        sys.exit(0)

    # === "create": assign clips on each shot's own episode timeline to a color group ===
    # May be None (e.g. right after a project switch, nothing open yet in the Edit page) — that's
    # only a problem for a marker whose own timeline hint can't be resolved either, so don't gate
    # on it up front.
    original_timeline = project.GetCurrentTimeline()
    log(f"Original timeline: {original_timeline.GetName() if original_timeline else 'None currently open'}")

    # Group markers by resolved target timeline. A marker with no timeline hint (no episodes
    # registered, or the hint can't be resolved) falls back to whatever is currently open —
    # this preserves the original single-timeline behavior.
    groups_by_timeline = []  # [(timeline, [markers])]
    index_by_timeline_id = {}

    def group_for(tl):
        key = id(tl)
        if key not in index_by_timeline_id:
            index_by_timeline_id[key] = len(groups_by_timeline)
            groups_by_timeline.append((tl, []))
        return groups_by_timeline[index_by_timeline_id[key]][1]

    for m in markers:
        tl = None
        uid = m.get("timelineUniqueId")
        name = m.get("timelineName")
        if uid or name:
            tl = find_timeline(project, uid, name)
        if tl is None:
            tl = original_timeline
        if tl is None:
            # Neither an explicit hint nor a currently-open timeline — nothing we can do for
            # this one shot; skip it rather than aborting the whole batch.
            continue
        group_for(tl).append(m)

    if not groups_by_timeline:
        raise Exception("No active timeline, and none of the provided shots resolved to a registered episode timeline.")

    log(f"Grouped {len(markers)} shot(s) into {len(groups_by_timeline)} timeline group(s): {[tl.GetName() for tl, _ in groups_by_timeline]}")

    print(f"PROGRESS: 0/{len(markers)}")
    sys.stdout.flush()

    processed_count = 0
    assigned_total = 0

    for timeline, group_markers in groups_by_timeline:
        try:
            project.SetCurrentTimeline(timeline)
        except Exception as e:
            log(f"Failed to switch to timeline '{timeline.GetName()}', skipping {len(group_markers)} shots: {e}")
            processed_count += len(group_markers)
            print(f"PROGRESS: {processed_count}/{len(markers)}")
            sys.stdout.flush()
            continue

        start_frame = int(timeline.GetStartFrame())
        start_tc = timeline.GetStartTimecode() if hasattr(timeline, 'GetStartTimecode') else "01:00:00:00"
        fps_raw = timeline.GetSetting("timelineFrameRate")
        fps = float(fps_raw) if fps_raw else 25.0
        start_tc_frames = tc_to_frames(start_tc, fps)

        # Cache all clips on this timeline once, to avoid repeated API calls per marker.
        all_timeline_clips = []
        track_count = timeline.GetTrackCount("video")
        for track_idx in range(1, track_count + 1):
            track_items = timeline.GetItemListInTrack("video", track_idx)
            if track_items:
                all_timeline_clips.extend(track_items)

        log(f"Timeline '{timeline.GetName()}': cached {len(all_timeline_clips)} clip(s) from {track_count} track(s), processing {len(group_markers)} shot(s).")

        for m in group_markers:
            processed_count += 1
            print(f"PROGRESS: {processed_count}/{len(markers)}")
            sys.stdout.flush()

            vfx_name = m.get("name")
            tc_in = m.get("tc")
            tc_out = m.get("note")  # We passed tcOut in the note field

            if not vfx_name or not tc_in or not tc_out:
                continue

            # Timecode parsing for Intersection Window
            in_frames = start_frame + (tc_to_frames(tc_in, fps) - start_tc_frames)
            out_frames = start_frame + (tc_to_frames(tc_out, fps) - start_tc_frames)

            # Ensure correct order
            if in_frames > out_frames:
                in_frames, out_frames = out_frames, in_frames

            # Get or Create Color Group
            color_groups = project.GetColorGroupsList()
            target_group = None
            if color_groups:
                for g in color_groups:
                    if g.GetName() == vfx_name:
                        target_group = g
                        break

            if not target_group:
                target_group = project.AddColorGroup(vfx_name)

            if not target_group:
                continue

            # Add intersecting clips to this color group
            assigned_count_for_clip = 0
            for item in all_timeline_clips:
                i_start = item.GetStart()
                i_end = item.GetEnd()

                # Simple overlap check: Item starts before VFX ends, AND Item ends after VFX starts
                if i_start < out_frames and i_end > in_frames:
                    item.AssignToColorGroup(target_group)
                    assigned_count_for_clip += 1
                    assigned_total += 1

            print(f"{vfx_name},{assigned_count_for_clip}")
            sys.stdout.flush()

    # Restore whatever timeline was open before this run, so Resolve's UI doesn't end up
    # parked on the last-processed episode.
    if original_timeline is not None:
        try:
            project.SetCurrentTimeline(original_timeline)
        except Exception:
            pass

    log(f"Done. processed={processed_count}, total_clips_grouped={assigned_total}")
    print(json.dumps({
        "status": "success",
        "processed": processed_count,
        "total_clips_grouped": assigned_total
    }))

except Exception as e:
    print(json.dumps({"error": f"Script Error: {str(e)}"}))
