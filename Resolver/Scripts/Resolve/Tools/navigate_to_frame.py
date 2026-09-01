#!/usr/bin/env python
import sys
import json
import traceback

def log(message):
    """Debug breadcrumb, shown in Resolver's Debug Mode console. Every meaningful step prints
    one of these so a hang or crash can be pinpointed to the exact step it happened at. This
    script's output is otherwise ignored by the Swift side, so extra lines here are risk-free."""
    print(json.dumps({"status": "debug", "message": message}))
    sys.stdout.flush()

# Wrap everything to ensure we capture crashes
try:
    import importlib.util
    import os

    # === Load JSON Payload ===
    # Expecting: {"frame": 12345}
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No input file provided"}))
        sys.exit(1)

    input_file = sys.argv[1]
    log(f"Loading payload from {input_file}")

    try:
        with open(input_file, 'r') as f:
            data = json.load(f)
    except Exception as e:
        print(json.dumps({"error": f"Failed to load JSON: {str(e)}"}))
        sys.exit(1)

    target_frame = int(data.get("frame", 0))
    target_tc = data.get("tc")
    target_timeline_unique_id = data.get("timelineUniqueId")
    target_timeline_name = data.get("timelineName")
    log(f"target_tc={target_tc}, target_frame={target_frame}, timelineUniqueId={target_timeline_unique_id}, timelineName={target_timeline_name}")

    # === Helpers ===
    def frames_to_tc(frames, fps):
        total_seconds = int(frames / fps)
        frame = int(frames % fps)
        second = int(total_seconds % 60)
        minute = int((total_seconds / 60) % 60)
        hour = int(total_seconds / 3600)
        return f"{hour:02d}:{minute:02d}:{second:02d}:{frame:02d}"

    # === API Setup ===
    try:
        # Try standard macOS path for DaVinciResolveScript.py
        sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
        sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")
        
        if os.path.exists(sdk_file):
            spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
            dvr = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(dvr)
            import DaVinciResolveScript as dvr
            scriptapp = dvr.scriptapp
        else:
            # Fallback to fusionscript.so if SDK file missing (less likely on Mac)
            path = "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so"
            spec = importlib.util.spec_from_file_location("fusionscript", path)
            if spec:
                fusionscript = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(fusionscript)
                scriptapp = fusionscript.scriptapp
            else:
                 raise Exception("Could not find Resolve API modules")

        log("Connecting to Resolve...")
        resolve = scriptapp("Resolve")
        if not resolve:
             raise Exception("Could not connect to DaVinci Resolve")

        log("Getting current project...")
        projectManager = resolve.GetProjectManager()
        project = projectManager.GetCurrentProject()
        if not project:
             raise Exception("No active project")

        # If the clip being jumped to belongs to a specific registered episode,
        # switch to that episode's timeline first so the clip is actually
        # reachable — jumping to a raw TC only makes sense within the right
        # timeline. Falls back to whatever is currently open if no match is
        # found (e.g. no episodes registered, or the timeline was renamed).
        if target_timeline_unique_id or target_timeline_name:
            log(f"Resolving target timeline (uid={target_timeline_unique_id}, name={target_timeline_name})...")
            try:
                count = int(project.GetTimelineCount() or 0)
            except Exception:
                count = 0
            match_by_name = None
            for i in range(1, count + 1):
                try:
                    tl = project.GetTimelineByIndex(i)
                except Exception:
                    tl = None
                if not tl:
                    continue
                if target_timeline_unique_id and hasattr(tl, "GetUniqueId"):
                    try:
                        if tl.GetUniqueId() == target_timeline_unique_id:
                            match_by_name = tl
                            break
                    except Exception:
                        pass
                if match_by_name is None and target_timeline_name:
                    try:
                        if tl.GetName() == target_timeline_name:
                            match_by_name = tl
                    except Exception:
                        pass
            if match_by_name is not None:
                current = project.GetCurrentTimeline()
                already_current = current is not None and current.GetName() == match_by_name.GetName()
                if not already_current:
                    log(f"Switching to timeline '{match_by_name.GetName()}'...")
                    project.SetCurrentTimeline(match_by_name)
                else:
                    log(f"Timeline '{match_by_name.GetName()}' is already current, no switch needed.")
            else:
                log(f"Target timeline '{target_timeline_name}' not found, navigating in the currently open timeline instead.")

        timeline = project.GetCurrentTimeline()
        if not timeline:
             raise Exception("No active timeline")
        log(f"Navigating within timeline '{timeline.GetName()}'...")

    except Exception as e:
        raise Exception(f"Resolve API Error: {str(e)}")

    # === Navigate ===
    try:
        navigated = False
        
        # Method 0: SetCurrentTimecode directly if exact TC provided
        if target_tc and hasattr(timeline, "SetCurrentTimecode"):
            method = getattr(timeline, "SetCurrentTimecode")
            if callable(method):
                try:
                    method(target_tc)
                    print(json.dumps({"status": "success", "message": f"Moved to exact TC {target_tc} using SetCurrentTimecode"}))
                    navigated = True
                except Exception as e:
                    print(json.dumps({"status": "debug", "message": f"SetCurrentTimecode direct failed: {str(e)}"}))
        
        # Method 1: SetCurrentTime (Frames)
        if not navigated and target_frame > 0 and hasattr(timeline, "SetCurrentTime"):
            method = getattr(timeline, "SetCurrentTime")
            if callable(method):
                try:
                    method(target_frame)
                    print(json.dumps({"status": "success", "message": f"Moved to frame {target_frame} using SetCurrentTime"}))
                    navigated = True
                except Exception as e:
                    print(json.dumps({"status": "debug", "message": f"SetCurrentTime failed: {str(e)}"}))
        
        if not navigated and target_frame > 0:
            # Method 2: SetCurrentTimecode fallback via conversion
            fps = float(timeline.GetSetting("timelineFrameRate"))
            tc = frames_to_tc(target_frame, fps)
            
            if hasattr(timeline, "SetCurrentTimecode"):
                method = getattr(timeline, "SetCurrentTimecode")
                if callable(method):
                    method(tc)
                    print(json.dumps({"status": "success", "message": f"Moved to TC {tc} using SetCurrentTimecode fallback"}))
                    navigated = True
                else:
                    print(json.dumps({"status": "error", "message": "SetCurrentTimecode is not callable"}))
            else:
                 print(json.dumps({"status": "error", "message": "No navigation method found on timeline"}))
                 
        if not target_frame and not target_tc:
            print(json.dumps({"status": "error", "message": "No valid frame or tc provided in JSON payload."}))

    except Exception as e:
        print(json.dumps({"status": "error", "message": f"Navigation failed: {str(e)}"}))

except Exception as e:
    # Catch-all for top-level crashes (ImportError, etc.)
    print(json.dumps({"error": f"Critical Script Crash: {str(e)}", "traceback": traceback.format_exc()}))
    sys.exit(1)
