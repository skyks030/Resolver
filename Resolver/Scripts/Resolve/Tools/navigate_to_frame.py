#!/usr/bin/env python
import sys
import json
import traceback

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

    try:
        with open(input_file, 'r') as f:
            data = json.load(f)
    except Exception as e:
        print(json.dumps({"error": f"Failed to load JSON: {str(e)}"}))
        sys.exit(1)

    target_frame = int(data.get("frame", 0))

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

        resolve = scriptapp("Resolve")
        if not resolve:
             raise Exception("Could not connect to DaVinci Resolve")

        projectManager = resolve.GetProjectManager()
        project = projectManager.GetCurrentProject()
        if not project:
             raise Exception("No active project")

        timeline = project.GetCurrentTimeline()
        if not timeline:
             raise Exception("No active timeline")

    except Exception as e:
        raise Exception(f"Resolve API Error: {str(e)}")

    # === Navigate ===
    # === Navigate ===
    try:
        navigated = False
        
        # Method 1: SetCurrentTime (Frames)
        if hasattr(timeline, "SetCurrentTime"):
            method = getattr(timeline, "SetCurrentTime")
            if callable(method):
                try:
                    method(target_frame)
                    print(json.dumps({"status": "success", "message": f"Moved to frame {target_frame} using SetCurrentTime"}))
                    navigated = True
                except Exception as e:
                    print(json.dumps({"status": "debug", "message": f"SetCurrentTime failed: {str(e)}"}))
        
        if not navigated:
            # Method 2: SetCurrentTimecode
            fps = float(timeline.GetSetting("timelineFrameRate"))
            tc = frames_to_tc(target_frame, fps)
            
            if hasattr(timeline, "SetCurrentTimecode"):
                method = getattr(timeline, "SetCurrentTimecode")
                if callable(method):
                    method(tc)
                    print(json.dumps({"status": "success", "message": f"Moved to TC {tc} using SetCurrentTimecode"}))
                    navigated = True
                else:
                    print(json.dumps({"status": "error", "message": "SetCurrentTimecode is not callable"}))
            else:
                 print(json.dumps({"status": "error", "message": "No navigation method found on timeline"}))

    except Exception as e:
        print(json.dumps({"status": "error", "message": f"Navigation failed: {str(e)}"}))

except Exception as e:
    # Catch-all for top-level crashes (ImportError, etc.)
    print(json.dumps({"error": f"Critical Script Crash: {str(e)}", "traceback": traceback.format_exc()}))
    sys.exit(1)
