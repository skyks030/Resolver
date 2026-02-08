#!/usr/bin/env python
import sys
import os
import importlib.util
import json

# === Load JSON Payload ===
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

# === Resolve API Setup ===
try:
    # Try standard macOS path for DaVinciResolveScript.py
    sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
    sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")
    
    if os.path.exists(sdk_file):
        spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
        dvr = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(dvr)
        
        # Critical: Import the module we just loaded
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
             sys.exit(1)

    resolve = scriptapp("Resolve")
    if not resolve:
         sys.exit(1)

    projectManager = resolve.GetProjectManager()
    project = projectManager.GetCurrentProject()
    if not project:
         sys.exit(1)

    timeline = project.GetCurrentTimeline()
    if not timeline:
         sys.exit(1)

except Exception:
    sys.exit(1)

# === Main Logic ===
track_index = int(data.get("trackIndex", 1))

# Validate Track
track_type = "video"
track_count = timeline.GetTrackCount(track_type)
if track_index > track_count:
    print(json.dumps({"error": f"Track {track_index} does not exist. Total tracks: {track_count}"}))
    sys.exit(1)

clips = timeline.GetItemListInTrack(track_type, track_index)
issues = []
previous_clip_name = None
previous_clip_end = -1 # Frame count

for clip in clips:
    name = clip.GetName()
    start = clip.GetStart()
    end = clip.GetEnd()
    
    # Check for Double Clips (Same name, adjacent)
    # Note: "Adjacent" in Resolve usually means strictly touching frames implies cut, 
    # but here we just check if previous clip name was same. 
    # Logic: if index > 0 and name == prev_name: issue.
    # Refinement: Only if they are physically next to each other? 
    # User said: "direkt nebeneinanderliegen". 
    # In a timeline list, they are ordered by time.
    # If `start` of current == `end` of previous (roughly), they are touching.
    # But even if there is a gap, user might likely mean "sequential in the edit".
    # User said "direkt nebeneinanderliegen" -> likely touching or close.
    # But simply "next in list" with "same name" is the best indicator of a "double clip" (cut made in same clip).
    
    is_adjacent = False
    if previous_clip_end != -1:
        # Check if gap is small (e.g. 0 or 1 frame)
        if abs(start - previous_clip_end) <= 1:
            is_adjacent = True
            
    if previous_clip_name and name == previous_clip_name and is_adjacent:
        issues.append({
            "type": "Double Clip",
            "name": name,
            "startFrame": start,
            "tc": clip.GetStart() # GetStart returns frames, need ToTimecode later or let python do it?
                                  # Timeline object has internal settings. 
                                  # We can get TC string via creating a marker? No.
                                  # Clip doesn't easy give TC string relative to timeline without calculation.
                                  # BUT: timeline.GetStart() gives timeline start frame.
                                  # Easier to just pass Frame and let Swift calculate or navigate by Frame?
                                  # Resolve API `SetCurrentTimecode` takes string.
                                  # `SetCurrentTime` takes frames? No.
                                  # `CurrentTime` property takes frames!
                                  # So passing `startFrame` is best.
        })
        
    # Check for Solid Color
    # Usually name is "Solid Color" or checking GetMediaPoolItem properties
    # Solid Colors often don't have a MediaPoolItem or it has a specific type.
    mp_item = clip.GetMediaPoolItem()
    is_solid = False
    
    if name == "Solid Color":
        is_solid = True
    elif mp_item:
        # Check media pool item properties if needed
        pass
    else:
        # No MP item might indicate generator or offline
        # But "Solid Color" usually has a name.
        pass
        
    # Check for Fusion Generator "Solid Color" or similar names
    if "Solid Color" in name or "Adjustment Clip" in name: # User specifically said "Solid Color".
        # Let's stick to "Solid Color" case-insensitive?
        pass

    if name.lower() == "solid color" or name.lower() == "solidcolor":
        issues.append({
            "type": "Solid Color",
            "name": name,
            "startFrame": start,
            "tc": start 
        })

    previous_clip_name = name
    previous_clip_end = end

# Output
print(json.dumps({"status": "success", "issues": issues, "trackIndex": track_index}))
