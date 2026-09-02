#!/usr/bin/env python3
"""
jump_to_clip.py
Moves DaVinci Resolve's current playhead to a specific shot's saved Record Timecode In, switching
to that shot's registered Episode timeline first if the project uses the Episode Manager and it
isn't already the current one. Used by Resolver's Sync Review window — clicking a shot's name
during a DaVinci Resolve index review jumps straight to it in the real project.

The timecode passed in is expected to already be in the same absolute, timeline-timecode space
DaVinci Resolve itself uses (i.e. what clip-indexing.py's frames_to_tc(clip.GetStart(), fps)
produces — TimelineItem.GetStart() is already an absolute frame number account for the timeline's
own start-timecode setting, not a 0-based offset), so it's passed straight to
Timeline.SetCurrentTimecode without any further conversion.

Input (argv[1], a JSON file):
  {
    "timecode": "01:02:15:04",              # Record TC In to jump to
    "episode": "1" or "",                    # the clip's Episode number, "" if none/unknown
    "episodesMap": [ {"timelineName": "...", "timelineUniqueId": "...", "episodeNumber": 1}, ... ]
  }

Output (stdout, single JSON line):
  {"status": "success", "timeline": "..."}
  or: {"error": "..."}
"""

import sys
import os
import json
import importlib.util


def log(message):
    """Debug breadcrumb, shown in Resolver's Debug Mode console."""
    print(json.dumps({"status": "debug", "message": message}))
    sys.stdout.flush()


def find_timeline(project, unique_id, name):
    """Same lookup clip-indexing.py's find_timeline uses: unique id first (stable across
    renames), name as a fallback. Returns None if neither matches anything."""
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


def fail(message):
    print(json.dumps({"error": message}))
    sys.exit(1)


def main():
    if len(sys.argv) < 2:
        fail("Missing JSON input file path")

    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)

    timecode = (data.get("timecode") or "").strip()
    episode = str(data.get("episode") or "").strip()
    episodes_map = data.get("episodesMap") or []

    if not timecode:
        fail("This shot has no saved timecode to jump to.")

    sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
    sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")
    if not os.path.exists(sdk_file):
        fail(f"Resolve scripting SDK not found: {sdk_file}")

    log("Connecting to Resolve...")
    spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
    dvr = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dvr)
    import DaVinciResolveScript as dvr
    resolve = dvr.scriptapp("Resolve")
    if not resolve:
        fail("Could not connect to DaVinci Resolve.")

    pm = resolve.GetProjectManager()
    project = pm.GetCurrentProject()
    if not project:
        fail("No project is open in DaVinci Resolve.")

    target_timeline = None
    if episode:
        for ep in episodes_map:
            if str(ep.get("episodeNumber", "")) == episode:
                target_timeline = find_timeline(project, ep.get("timelineUniqueId"), ep.get("timelineName"))
                break
        if target_timeline is None:
            log(f"Episode {episode}'s registered timeline was not found — falling back to the current timeline.")

    if target_timeline is None:
        target_timeline = project.GetCurrentTimeline()

    if target_timeline is None:
        fail("No matching episode timeline was found, and no timeline is currently open.")

    current = project.GetCurrentTimeline()
    same_timeline = current is not None and (
        (hasattr(current, "GetUniqueId") and hasattr(target_timeline, "GetUniqueId")
         and current.GetUniqueId() == target_timeline.GetUniqueId())
        or current.GetName() == target_timeline.GetName()
    )
    if not same_timeline:
        log(f"Switching to timeline '{target_timeline.GetName()}'...")
        if not project.SetCurrentTimeline(target_timeline):
            fail(f"Could not switch to timeline '{target_timeline.GetName()}'.")

    try:
        resolve.OpenPage("edit")
    except Exception:
        pass  # Not fatal — the playhead jump below still works even if the page switch fails.

    log(f"Setting current timecode to {timecode} on '{target_timeline.GetName()}'...")
    if not target_timeline.SetCurrentTimecode(timecode):
        fail(f"Resolve rejected timecode {timecode} on '{target_timeline.GetName()}' — it may be out of the timeline's range.")

    print(json.dumps({"status": "success", "timeline": target_timeline.GetName()}))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        fail(str(e))
