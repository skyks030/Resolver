#!/usr/bin/env python3
"""
list_timelines.py
Lists every timeline in the currently open DaVinci Resolve project by reading
the project's Timeline registry (Project.GetTimelineByIndex), which is
authoritative and complete regardless of how each timeline was created
(manually, or imported via AAF/XML/EDL). Only if that registry comes back
completely empty does this fall back to a recursive Media Pool scan for
Timeline-type clips (MediaPoolItem where clip property "Type" == "Timeline")
— that scan is O(every clip in the project) with one Resolve round-trip per
clip, so it is not run unless there is truly no other way to find timelines.

Outputs a single JSON object on stdout:
  {"timelines": [{"name": str, "uniqueId": str, "startTC": str, "frameCount": int, "fps": str}, ...]}
or on failure:
  {"error": "..."}

All fields are explicitly cast to JSON-safe primitive types (str/int) since
the Resolve API can return numeric types (e.g. a float framerate) depending
on version/platform, which previously broke strict JSON decoding downstream.
"""

import sys
import os
import json
import importlib.util


def safe_str(value):
    if value is None:
        return ""
    try:
        return str(value)
    except Exception:
        return ""


def safe_int(value):
    try:
        return int(value)
    except Exception:
        return 0


def log(message):
    """Debug breadcrumb, shown in Resolver's Debug Mode console. Every meaningful step prints
    one of these so a hang or crash can be pinpointed to the exact step it happened at."""
    print(json.dumps({"status": "debug", "message": message}))
    sys.stdout.flush()


def collect_media_pool_timeline_names(media_pool):
    """Recursively walk every bin/subfolder in the Media Pool (starting at the
    root folder) and collect the names of every clip whose 'Type' clip
    property equals 'Timeline'. This is the current documented way to
    identify Timeline entries anywhere in the Media Pool, regardless of which
    bin they live in."""
    names = []
    visited_folders = set()

    def walk(folder):
        if not folder:
            return
        folder_id = id(folder)
        if folder_id in visited_folders:
            return
        visited_folders.add(folder_id)

        try:
            clips = folder.GetClipList() or []
        except Exception:
            clips = []
        for clip in clips:
            try:
                clip_type = clip.GetClipProperty("Type")
            except Exception:
                clip_type = None
            if clip_type == "Timeline":
                name = None
                try:
                    name = clip.GetClipProperty("Clip Name")
                except Exception:
                    pass
                if not name:
                    try:
                        name = clip.GetName()
                    except Exception:
                        pass
                if name:
                    names.append(name)

        try:
            subfolders = folder.GetSubFolderList() or []
        except Exception:
            subfolders = []
        for sub in subfolders:
            walk(sub)

    walk(media_pool.GetRootFolder())
    return names


def main():
    # === Load DaVinci Resolve API ===
    sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
    sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")

    if not os.path.exists(sdk_file):
        print(json.dumps({"error": "DaVinci Resolve SDK not found. Is DaVinci Resolve Studio installed?"}))
        return

    log("Loading DaVinci Resolve Scripting API...")
    try:
        spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
        dvr_mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(dvr_mod)
        import DaVinciResolveScript as dvr
    except Exception as e:
        print(json.dumps({"error": f"Could not load DaVinci Resolve API: {e}"}))
        return

    log("Connecting to Resolve...")
    resolve = dvr.scriptapp("Resolve")
    if not resolve:
        print(json.dumps({"error": "Cannot connect to DaVinci Resolve. Make sure it is running and External Scripting is enabled."}))
        return

    log("Getting project manager...")
    pm = resolve.GetProjectManager()
    if not pm:
        print(json.dumps({"error": "Could not get Project Manager from DaVinci Resolve."}))
        return

    log("Getting current project...")
    project = pm.GetCurrentProject()
    if not project:
        print(json.dumps({"error": "No project is currently open in DaVinci Resolve."}))
        return

    # === 1) Build a metadata lookup from every registered Timeline object ===
    log("Building Timeline registry metadata...")
    timeline_meta_by_name = {}
    try:
        count = safe_int(project.GetTimelineCount() or 0)
    except Exception:
        count = 0
    log(f"Timeline registry reports {count} timeline(s).")

    for i in range(1, count + 1):
        try:
            tl = project.GetTimelineByIndex(i)
        except Exception:
            tl = None
        if not tl:
            continue

        try:
            name = tl.GetName() or f"Timeline {i}"
        except Exception:
            name = f"Timeline {i}"

        unique_id = ""
        try:
            if hasattr(tl, "GetUniqueId"):
                unique_id = safe_str(tl.GetUniqueId())
        except Exception:
            pass

        start_tc = ""
        try:
            if hasattr(tl, "GetStartTimecode"):
                start_tc = safe_str(tl.GetStartTimecode())
        except Exception:
            pass

        frame_count = 0
        try:
            start_frame = safe_int(tl.GetStartFrame())
            end_frame = safe_int(tl.GetEndFrame())
            frame_count = max(0, end_frame - start_frame + 1)
        except Exception:
            pass

        fps = ""
        try:
            fps = safe_str(tl.GetSetting("timelineFrameRate"))
        except Exception:
            pass

        timeline_meta_by_name[name] = {
            "name": safe_str(name),
            "uniqueId": unique_id,
            "startTC": start_tc,
            "frameCount": frame_count,
            "fps": fps
        }

    log(f"Registry metadata built for {len(timeline_meta_by_name)} timeline(s): {list(timeline_meta_by_name.keys())}")

    # === 2) Recursively search the entire Media Pool for Timeline clips ===
    # ONLY as a last-resort fallback when the Timeline registry (above) found nothing at all.
    # The registry is authoritative and complete — every timeline in a project (manually
    # created, AAF/XML/EDL-imported, whatever) is always reachable via GetTimelineByIndex — so
    # there is normally nothing this walk could add. It used to run unconditionally, which meant
    # calling clip.GetClipProperty("Type") once per clip in the ENTIRE project (every bin,
    # recursively) — each one a separate round-trip to Resolve. On a large feature-film project
    # with thousands of Media Pool clips that took minutes and looked like a hang. Only pay that
    # cost in the (very unlikely) case the registry itself came back empty.
    media_pool_names = []
    if count == 0:
        log("Timeline registry is empty — falling back to a Media Pool scan (recursive bin walk)...")
        try:
            media_pool = project.GetMediaPool()
            if media_pool:
                media_pool_names = collect_media_pool_timeline_names(media_pool)
        except Exception:
            media_pool_names = []
        log(f"Media Pool walk found {len(media_pool_names)} Timeline clip(s): {media_pool_names}")
    else:
        log("Skipping Media Pool scan — Timeline registry already has every timeline.")

    # Union of the Timeline registry and whatever the Media Pool walk found
    # (the latter is only ever non-empty in the registry-was-empty fallback
    # case above), de-duplicated while preserving discovery order. Registry
    # names go first since they are the authoritative source.
    seen = set()
    ordered_names = []
    for name in timeline_meta_by_name.keys():
        if name not in seen:
            seen.add(name)
            ordered_names.append(name)
    for name in media_pool_names:
        if name not in seen:
            seen.add(name)
            ordered_names.append(name)

    timelines = []
    for name in ordered_names:
        meta = timeline_meta_by_name.get(name, {
            "name": safe_str(name),
            "uniqueId": "",
            "startTC": "",
            "frameCount": 0,
            "fps": ""
        })
        timelines.append(meta)

    # Sort alphabetically (case-insensitive) by name
    timelines.sort(key=lambda t: (t.get("name") or "").lower())

    log(f"Union of registry + Media Pool: {len(timelines)} timeline(s) total.")
    print(json.dumps({"timelines": timelines}))


if __name__ == "__main__":
    main()
