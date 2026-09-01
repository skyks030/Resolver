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

# === Load JSON Payload ===
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

action = data.get("action")
markers = data.get("markers", [])
# Every registered episode's timeline (only needed by "delete_all_vfx", which has no per-marker
# list to carry timeline hints on) — see EpisodeManagementView / ProjectExportView.performBatchOp.
episodes = data.get("episodes") or []
log(f"action={action}, markers={len(markers)}, registered episodes={len(episodes)}")

if not action or action not in ["create", "delete", "delete_all_vfx"]:
    print(json.dumps({"error": "Invalid action. Must be 'create', 'delete', or 'delete_all_vfx'."}))
    sys.exit(1)

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
        raise Exception("Could not connect to Resolve")

    log("Getting current project...")
    project = resolve.GetProjectManager().GetCurrentProject()
    if not project:
         raise Exception("No active project")

    original_timeline = project.GetCurrentTimeline()
    log(f"Original timeline: {original_timeline.GetName() if original_timeline else 'None currently open'}")

    count = 0
    failed_count = 0

    if action == "delete_all_vfx":
        # Scan for "Resolver VFX-Marker" in notes, across every registered episode's timeline
        # when episodes exist, otherwise just whatever is currently open (original behavior).
        target_timelines = []
        if episodes:
            for ep in episodes:
                tl = find_timeline(project, ep.get("timelineUniqueId"), ep.get("timelineName"))
                if tl is not None:
                    target_timelines.append(tl)
                else:
                    log(f"Could not resolve timeline for episode '{ep.get('timelineName')}', skipping.")
        if not target_timelines:
            if not original_timeline:
                raise Exception("No active timeline")
            target_timelines = [original_timeline]
        log(f"Scanning {len(target_timelines)} timeline(s) for existing VFX markers: {[t.GetName() for t in target_timelines]}")

        # Two passes so the UI can show a real "x/y processed" counter instead of an unknown
        # total: first count how many "Resolver VFX-Marker" notes exist across every target
        # timeline, then delete them while reporting progress against that count.
        to_delete = []  # [(timeline, frame_id, color)]
        for timeline in target_timelines:
            try:
                project.SetCurrentTimeline(timeline)
            except Exception as e:
                log(f"Failed to switch to timeline '{timeline.GetName()}' for scanning, skipping: {e}")
                continue

            markers_dict = timeline.GetMarkers()
            found_here = 0
            if markers_dict:
                for frame_id, marker_info in markers_dict.items():
                    note = marker_info.get("note", "")
                    if "Resolver VFX-Marker" in note:
                        to_delete.append((timeline, frame_id, marker_info.get("color", "")))
                        found_here += 1
            log(f"Timeline '{timeline.GetName()}': found {found_here} VFX marker(s) to delete.")

        total_to_delete = len(to_delete)
        print(f"PROGRESS: 0/{max(total_to_delete, 1)}")
        sys.stdout.flush()

        current_timeline_for_delete = None
        for i, (timeline, frame_id, color) in enumerate(to_delete):
            if timeline is not current_timeline_for_delete:
                try:
                    project.SetCurrentTimeline(timeline)
                    current_timeline_for_delete = timeline
                except Exception as e:
                    log(f"Failed to switch to timeline '{timeline.GetName()}' for deletion, skipping its markers: {e}")
                    failed_count += 1
                    # Still advance the counter — otherwise the progress bar visually stalls for
                    # this whole timeline's markers instead of reflecting that they were skipped.
                    print(f"PROGRESS: {i + 1}/{total_to_delete}")
                    sys.stdout.flush()
                    continue

            if timeline.DeleteMarkerAtFrame(frame_id, color):
                count += 1
            else:
                failed_count += 1

            print(f"PROGRESS: {i + 1}/{total_to_delete}")
            sys.stdout.flush()

        if original_timeline is not None:
            try:
                project.SetCurrentTimeline(original_timeline)
            except Exception:
                pass

    else:
        # action in ("create", "delete"): group markers by resolved target timeline. A marker
        # with no timeline hint (no episodes registered, or the hint couldn't be resolved) falls
        # back to whatever is currently open — this preserves the original single-timeline
        # behavior when Episodes aren't in use. original_timeline may be None (e.g. right after a
        # project switch); that's only a problem for a marker whose own hint can't resolve either.
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
                # this one marker; skip it rather than aborting the whole batch.
                failed_count += 1
                continue
            group_for(tl).append(m)

        if not groups_by_timeline:
            raise Exception("No active timeline, and none of the provided markers resolved to a registered episode timeline.")

        log(f"Grouped {len(markers)} marker(s) into {len(groups_by_timeline)} timeline group(s): {[tl.GetName() for tl, _ in groups_by_timeline]}")

        total_markers = len(markers)
        processed = 0
        print(f"PROGRESS: 0/{max(total_markers, 1)}")
        sys.stdout.flush()

        for timeline, group_markers in groups_by_timeline:
            try:
                project.SetCurrentTimeline(timeline)
            except Exception as e:
                log(f"Failed to switch to timeline '{timeline.GetName()}', skipping {len(group_markers)} markers: {e}")
                failed_count += len(group_markers)
                processed += len(group_markers)
                print(f"PROGRESS: {processed}/{total_markers}")
                sys.stdout.flush()
                continue

            start_frame = int(timeline.GetStartFrame())
            start_tc = timeline.GetStartTimecode() if hasattr(timeline, 'GetStartTimecode') else "01:00:00:00"
            fps_raw = timeline.GetSetting("timelineFrameRate")
            fps = float(fps_raw) if fps_raw else 25.0
            start_tc_frames = tc_to_frames(start_tc, fps)
            log(f"Timeline '{timeline.GetName()}' Start Frame: {start_frame}, Start TC: {start_tc}, FPS: {fps} — processing {len(group_markers)} marker(s)")

            if action == "delete":
                # DeleteMarkerAtFrame expects Absolute Frame and Color
                for m in group_markers:
                    if "tc" in m and m["tc"]:
                        target_frames = tc_to_frames(m["tc"], fps)
                        frame_abs = start_frame + (target_frames - start_tc_frames)
                    else:
                        frame_abs = int(m.get("frameId", 0))

                    color = m.get("color", "Cream")

                    # Try to delete (Absolute)
                    if timeline.DeleteMarkerAtFrame(frame_abs, color):
                        count += 1
                    else:
                        # Retry with offset (Relative to Start)
                        frame_offset = frame_abs - start_frame
                        if timeline.DeleteMarkerAtFrame(frame_offset, color):
                            count += 1
                        else:
                            failed_count += 1

                    processed += 1
                    print(f"PROGRESS: {processed}/{total_markers}")
                    sys.stdout.flush()

            elif action == "create":
                for m in group_markers:
                    if "tc" in m and m["tc"]:
                        target_frames = tc_to_frames(m["tc"], fps)
                        frame_abs = start_frame + (target_frames - start_tc_frames)
                    else:
                        frame_abs = int(m.get("frameId", 0))

                    color = m.get("color", "Cream")
                    name = m.get("name", "")
                    note = m.get("note", "")
                    duration = int(m.get("duration", 1))

                    # AddMarker expects OFFSET from Start Frame
                    frame_offset = frame_abs - start_frame

                    if timeline.AddMarker(frame_offset, color, name, note, duration):
                        count += 1
                    else:
                        failed_count += 1

                    processed += 1
                    print(f"PROGRESS: {processed}/{total_markers}")
                    sys.stdout.flush()

        if original_timeline is not None:
            try:
                project.SetCurrentTimeline(original_timeline)
            except Exception:
                pass

    log(f"Done. count={count}, failed={failed_count}")
    print(json.dumps({
        "status": "success",
        "count": count,
        "failed": failed_count,
        "action": action,
        "total_attempted": len(markers)
    }))

except Exception as e:
    print(json.dumps({"error": f"Script Error: {str(e)}"}))
