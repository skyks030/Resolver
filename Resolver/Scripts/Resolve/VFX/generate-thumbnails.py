#!/usr/bin/env python3

import sys
import os
import importlib.util
import json
import time
import subprocess
import traceback

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

# === Helper: Frames to TC ===
def frames_to_tc(frames, fps):
    try:
        if not fps or float(fps) == 0.0: return "00:00:00:00"
        fps_float = float(fps)
        total_seconds = frames / fps_float
        hours = int(total_seconds // 3600)
        minutes = int((total_seconds % 3600) // 60)
        seconds = int(total_seconds % 60)
        frame_part = int(frames % fps_float)
        return "{:02}:{:02}:{:02}:{:02}".format(hours, minutes, seconds, frame_part)
    except:
        return "00:00:00:00"

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

output_dir = data.get("outputDir")
clips = data.get("clips", [])
export_format = data.get("format", "jpg")
resize_height = int(data.get("resizeHeight", 512))

if not output_dir or not clips:
    print(json.dumps({"error": "Invalid JSON data (missing outputDir or clips)"}))
    sys.exit(1)

# Create Output Directory
if not os.path.exists(output_dir):
    try:
        os.makedirs(output_dir)
    except Exception as e:
        print(json.dumps({"error": f"Failed to create output directory: {e}"}))
        sys.exit(1)

# === Resolve API Setup ===
try:
    sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
    sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")

    spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
    dvr = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dvr)

    import DaVinciResolveScript as dvr
    log("Connecting to Resolve...")
    resolve = dvr.scriptapp("Resolve")

    if not resolve:
        raise Exception("Could not connect to Resolve (scriptapp returned None)")

    log("Getting Project Manager...")
    pm = resolve.GetProjectManager()
    if not pm:
        raise Exception("GetProjectManager() returned None")

    log("Getting Current Project...")
    project = pm.GetCurrentProject()
    if not project:
         raise Exception("No active project")

    # May be None (e.g. right after a project switch, nothing open yet in the Edit page) — that's
    # only a problem for a clip whose own timeline hint can't be resolved either, so don't gate
    # on it up front.
    original_timeline = project.GetCurrentTimeline()
    log(f"Original timeline: {original_timeline.GetName() if original_timeline else 'None currently open'}")

    target_track_index = int(data.get("targetTrack", 1))
    log(f"{len(clips)} shot(s) requested, target track={target_track_index}")

    # Group clips by resolved target timeline (per-clip "timelineUniqueId"/"timelineName", set
    # client-side from the Episode Manager). A clip with no hint — or an unresolvable one — falls
    # back to whatever is currently open, preserving single-timeline behavior when Episodes
    # aren't in use.
    groups_by_timeline = []  # [(timeline, [clips])]
    index_by_timeline_id = {}

    def group_for(tl):
        key = id(tl)
        if key not in index_by_timeline_id:
            index_by_timeline_id[key] = len(groups_by_timeline)
            groups_by_timeline.append((tl, []))
        return groups_by_timeline[index_by_timeline_id[key]][1]

    skipped_no_timeline = 0
    for clip in clips:
        tl = None
        uid = clip.get("timelineUniqueId")
        name = clip.get("timelineName")
        if uid or name:
            tl = find_timeline(project, uid, name)
        if tl is None:
            tl = original_timeline
        if tl is None:
            # Neither an explicit hint nor a currently-open timeline — nothing we can do for
            # this one shot; skip it rather than aborting the whole batch.
            skipped_no_timeline += 1
            continue
        group_for(tl).append(clip)

    if not groups_by_timeline:
        raise Exception("No active timeline, and none of the provided shots resolved to a registered episode timeline.")
    if skipped_no_timeline:
        log(f"Skipped {skipped_no_timeline} shot(s) with no resolvable timeline.")
    log(f"Grouped {len(clips)} shot(s) into {len(groups_by_timeline)} timeline group(s): {[tl.GetName() for tl, _ in groups_by_timeline]}")

    # WRAP EVERYTHING in try/finally to ensure the originally-open timeline is restored
    try:
        log("Switching to Color Page...")
        if not resolve.OpenPage("color"):
             log("OpenPage returned False (might be already open or failed)")

        # === Gallery / Album Management (project-level, done once) ===
        log("Getting Gallery...")
        gallery = project.GetGallery()
        if not gallery:
            raise Exception("Could not access Gallery (GetGallery returned None)")

        # === Album Management ===
        # SIMPLIFIED STRATEGY for Production Stability
        # 1. Try to get Current Album. If it exists, use it.
        # 2. If valid albums exist, use the first one.
        # 3. Only try to find "resolver_temp_stills" if we have options, but don't force it if it breaks things.

        log("Getting Current Still Album...")

        albums = gallery.GetGalleryStillAlbums()
        target_album = gallery.GetCurrentStillAlbum()

        if not target_album and albums:
            target_album = albums[0]

        if target_album:
             lbl = target_album.GetLabel()
             if not lbl:
                 print(json.dumps({"status": "warning", "message": "Album is nameless. Renaming to 'Resolver_Stills'."}))
                 if target_album.SetLabel("Resolver_Stills"):
                     lbl = "Resolver_Stills"
                 else:
                     print(json.dumps({"status": "error", "message": "Failed to rename nameless album."}))

             log(f"Using album: {lbl}")
             gallery.SetCurrentStillAlbum(target_album)

        if not target_album:
            err_msg = "No valid Still Album found (and list is empty). Please create a 'Stills' album in Color Page."
            print(json.dumps({"status": "error", "message": err_msg}))
            raise Exception(err_msg) # Abort immediately

        # === Main Loop, grouped per resolved timeline ===
        processed_count = 0
        total_clips = len(clips)

        print(json.dumps({"status": "starting", "count": total_clips}))
        print(f"PROGRESS: 0/{max(total_clips, 1)}")
        sys.stdout.flush()

        for timeline, group_clips in groups_by_timeline:
            log(f"Switching to timeline '{timeline.GetName()}' ({len(group_clips)} shot(s))...")
            try:
                project.SetCurrentTimeline(timeline)
            except Exception as e:
                print(json.dumps({"status": "error", "message": f"Failed to switch to timeline '{timeline.GetName()}', skipping {len(group_clips)} shots: {e}"}))
                processed_count += len(group_clips)
                print(f"PROGRESS: {processed_count}/{total_clips}")
                sys.stdout.flush()
                continue

            # === Track Management (per timeline — each timeline has its own track layout) ===
            track_states = {}
            track_count = timeline.GetTrackCount("video")
            try:
                for i in range(1, track_count + 1):
                     try:
                         # API Check: Some versions use GetTrackEnable, others GetIsTrackEnabled
                         if hasattr(timeline, "GetIsTrackEnabled"):
                             state = timeline.GetIsTrackEnabled("video", i)
                         elif hasattr(timeline, "GetTrackEnable"):
                             state = timeline.GetTrackEnable("video", i)
                         else:
                             state = True

                         track_states[i] = state
                     except Exception as e:
                         print(json.dumps({"status": "warning", "message": f"Failed to read track state {i}: {e}"}))
                         track_states[i] = True

                # Solo Target Track
                for i in range(1, track_count + 1):
                     should_enable = (i == target_track_index)
                     if hasattr(timeline, "SetTrackEnable"):
                         timeline.SetTrackEnable("video", i, should_enable)
            except Exception as e:
                print(json.dumps({"status": "error", "message": f"Track Setup Failed on '{timeline.GetName()}': {e}"}))

            try:
                for clip in group_clips:
                    name = clip["name"]
                    try:
                        frame_start = int(clip.get("frameStart", 0))
                        frame_end = int(clip.get("frameEnd", 0))

                        # Get timeline frame rate
                        fps = timeline.GetSetting("timelineFrameRate")

                        # Revert to First Frame (User Request)
                        # We use the provided 'tc' (which is Start TC) or calculate from frameStart
                        target_tc = clip.get("tc", "")
                        if not target_tc and frame_start > 0:
                             target_tc = frames_to_tc(frame_start, fps)

                        if target_tc:
                             timeline.SetCurrentTimecode(target_tc)
                             time.sleep(0.2) # Allow Resolve to seek

                        # Force Switch to Target Album to ensure GrabStill puts it there
                        if target_album:
                            gallery.SetCurrentStillAlbum(target_album)

                        # Grab Still
                        log(f"Grabbing still for '{name}' at {target_tc or frame_start} ({processed_count + 1}/{total_clips})...")
                        still = timeline.GrabStill()
                        time.sleep(0.05) # Brief pause to ensures still is ready

                        if not still:
                            # Retry once immediately without sleep
                            still = timeline.GrabStill()

                        if still:
                            # Clean up existing files for this clip name to prevent duplicates/stale files
                            # === ROBUST EXPORT STRATEGY ===

                            # 1. Snapshot valid files before
                            files_before = set(os.listdir(output_dir))

                            # 2. Export with UNIQUE Name (UUID) to avoid collisions/overwriting
                            import uuid
                            temp_export_name = str(uuid.uuid4())

                            # === EXPORT STRATEGY: BRUTE FORCE ===
                            # GrabStill puts the still somewhere. If we can't find it in Current, check ALL albums.

                            success = False
                            export_album = None

                            # Build list of albums to try (Current first, then others)
                            albums_to_try = []

                            # Trust Current Album first and foremost
                            current = gallery.GetCurrentStillAlbum()
                            if current:
                                albums_to_try.append(current)

                            all_albums = gallery.GetGalleryStillAlbums()
                            if all_albums:
                                for a in all_albums:
                                    # Don't skip nameless albums - Production might only have one!
                                    is_duplicate = False
                                    if current:
                                         if a.GetLabel() and current.GetLabel() and a.GetLabel() == current.GetLabel():
                                             is_duplicate = True

                                    if not is_duplicate:
                                        albums_to_try.append(a)

                            # Fallback
                            if not albums_to_try and target_album:
                                albums_to_try.append(target_album)

                            album_names = [a.GetLabel() if a.GetLabel() else "Nameless" for a in albums_to_try]

                            # Try Export
                            for album in albums_to_try:
                                # Validate output dir access
                                if not os.access(output_dir, os.W_OK):
                                     print(json.dumps({"status": "error", "message": f"Output dir not writable: {output_dir}"}))

                                if album.ExportStills([still], output_dir, temp_export_name, export_format):
                                    success = True
                                    export_album = album
                                    break
                                else:
                                     pass

                            if not success:
                                # FATAL ERROR - Abort Script
                                err_msg = f"FATAL: ExportStills failed from ALL {len(albums_to_try)} albums for {name}. Albums: {album_names} Dir: {output_dir}"
                                print(json.dumps({"status": "error", "message": err_msg}))

                                # Try to cleanup the still so it doesn't pile up
                                try:
                                    if current: current.DeleteStills([still])
                                    elif target_album: target_album.DeleteStills([still])
                                except:
                                    pass

                                raise Exception(err_msg) # Abort processing
                            else:
                                # Cleanup success
                                export_album.DeleteStills([still])

                                # 3. Snapshot files after
                                files_after = set(os.listdir(output_dir))
                                new_files = list(files_after - files_before)

                                # Filter for our export format
                                image_files = [f for f in new_files if f.lower().endswith(f".{export_format}")]

                                if len(image_files) >= 1:
                                    # We found a new file! Rename it to what we want: `vfxName.jpg`.
                                    exported_filename = image_files[0]
                                    exported_path = os.path.join(output_dir, exported_filename)

                                    target_filename = f"{name}.{export_format}"
                                    target_path = os.path.join(output_dir, target_filename)

                                    if exported_filename != target_filename:
                                        try:
                                            if os.path.exists(target_path):
                                                os.remove(target_path)
                                            os.rename(exported_path, target_path)
                                        except Exception as mv_err:
                                            print(json.dumps({"status": "warning", "message": f"Failed to rename {exported_filename}: {mv_err}"}))
                                            target_path = exported_path

                                    # 4. Resize
                                    try:
                                        result = subprocess.run(
                                            ["sips", "--resampleHeight", str(resize_height), target_path],
                                            capture_output=True,
                                            text=True,
                                            check=False
                                        )
                                    except Exception as sips_err:
                                            print(json.dumps({"status": "warning", "message": f"Sips error: {sips_err}"}))

                                else:
                                     print(json.dumps({"status": "warning", "message": f"No new image file detected for {name} (Export requested as {temp_export_name})."}))

                                processed_count += 1

                                # === Progress Update ===
                                print(f"PROGRESS: {processed_count}/{total_clips}")
                                sys.stdout.flush()
                        else:
                            print(json.dumps({"status": "debug", "message": "GrabStill returned None"}))

                    except Exception as ex:
                         print(json.dumps({"status": "error", "message": f"Error processing {clip.get('name')}: {ex}"}))
                         # Re-raise FATAL errors to stop the loop
                         if "FATAL" in str(ex):
                             raise

                         traceback.print_exc()
                         # Continue to next
            finally:
                # Restore this timeline's track states before moving to the next group.
                for i, state in track_states.items():
                    if hasattr(timeline, "SetTrackEnable"):
                        timeline.SetTrackEnable("video", i, state)
            log(f"Finished timeline '{timeline.GetName()}'. Total processed so far: {processed_count}/{total_clips}")
    finally:
        # Restore whatever timeline was open before this run, so Resolve's UI doesn't end up
        # parked on the last-processed episode.
        if original_timeline is not None:
            log(f"Restoring original timeline '{original_timeline.GetName()}'...")
            try:
                project.SetCurrentTimeline(original_timeline)
            except Exception:
                pass

    # === Cleanup .drx files ===
    # Resolve exports .drx files with stills (grading data). We only want the images.
    log("Cleaning up .drx files...")
    try:
        if os.path.exists(output_dir):
            for filename in os.listdir(output_dir):
                if filename.lower().endswith(".drx"):
                    file_path = os.path.join(output_dir, filename)
                    os.remove(file_path)
    except Exception as cleanup_Ex:
        print(f"Warning: Failed to cleanup .drx files: {cleanup_Ex}")

    log(f"Done. processed={processed_count}/{total_clips}")
    print(json.dumps({"status": "success", "processed": processed_count, "folder": output_dir}))

except Exception as e:
    print(json.dumps({"error": f"Script Error: {str(e)}"}))
