#!/usr/bin/env python3
"""
color_groups.py
Lists or deletes DaVinci Resolve Color Groups — Project.GetColorGroupsList()/DeleteColorGroup(),
the Color page's project-wide grouping feature (not tied to any one timeline). Used by Resolver's
Color Group Manager window.

Input (argv[1], a JSON file):
  {"action": "list"}
  or
  {"action": "delete", "groupName": "..."}

Output (stdout, single JSON line):
  list:   {"status": "success", "groups": [{"name": "...", "clipCount": N}, ...]}
  delete: {"status": "success"}
  or:     {"error": "..."}
"""

import sys
import os
import json
import importlib.util


def log(message):
    """Debug breadcrumb, shown in Resolver's Debug Mode console."""
    print(json.dumps({"status": "debug", "message": message}))
    sys.stdout.flush()


def fail(message):
    print(json.dumps({"error": message}))
    sys.exit(1)


def connect():
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
    return project


def do_list(project):
    # Project-wide — Color Groups live on the project, not any one timeline, so this already
    # covers the whole project in one call; no need to walk every timeline.
    groups = project.GetColorGroupsList() or []
    log(f"Found {len(groups)} color group(s).")
    result = []
    for g in groups:
        try:
            name = g.GetName() or ""
        except Exception:
            name = ""
        # Best-effort clip count for the *current* timeline only — GetClipsInTimeline() defaults
        # to it and doesn't take a project-wide equivalent; walking every timeline just to count
        # clips would work against "super fast", so this is a nice-to-have hint, not a total.
        clip_count = 0
        try:
            clip_count = len(g.GetClipsInTimeline() or [])
        except Exception:
            pass
        result.append({"name": name, "clipCount": clip_count})
    print(json.dumps({"status": "success", "groups": result}))


def do_delete(project, group_name):
    if not group_name:
        fail("No group name given to delete.")
    groups = project.GetColorGroupsList() or []
    target = None
    for g in groups:
        try:
            if g.GetName() == group_name:
                target = g
                break
        except Exception:
            continue
    if target is None:
        fail(f"Color group '{group_name}' was not found — it may have already been deleted.")

    log(f"Deleting color group '{group_name}'...")
    if not project.DeleteColorGroup(target):
        fail(f"Resolve refused to delete color group '{group_name}'.")
    print(json.dumps({"status": "success"}))


def main():
    if len(sys.argv) < 2:
        fail("Missing JSON input file path")
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)

    action = data.get("action") or ""
    project = connect()

    if action == "list":
        do_list(project)
    elif action == "delete":
        do_delete(project, data.get("groupName") or "")
    else:
        fail(f"Unknown action: {action}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        fail(str(e))
