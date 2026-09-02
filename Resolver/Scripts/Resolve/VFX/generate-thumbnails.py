#!/usr/bin/env python3

import sys
import os
import re
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

# === Helper: Frames to TC / TC to Frames ===
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
    except Exception:
        return "00:00:00:00"

def tc_to_frames(tc, fps):
    try:
        if not tc: return None
        parts = tc.split(':')
        if len(parts) != 4: return None
        h, m, s, f = map(int, parts)
        if not fps or float(fps) == 0.0: return None
        return int((h * 3600 + m * 60 + s) * float(fps) + f)
    except Exception:
        return None

def target_frame_for(tc_in, tc_out, fps, frame_position):
    """Resolves which timeline frame to grab the still from, per the user's chosen
    First/Middle/Last Frame option — computed from the shot's own Record TC In/Out, not a
    separately-tracked frame count (which isn't reliably populated for every clip)."""
    in_frame = tc_to_frames(tc_in, fps)
    if in_frame is None:
        return None
    out_frame = tc_to_frames(tc_out, fps)
    if out_frame is None or out_frame <= in_frame:
        # No usable out point (or a degenerate/zero-length range) — first frame is the only
        # position we can trust.
        return in_frame

    last_frame = out_frame - 1  # Record TC Out is exclusive — one frame past the shot's last frame.
    if frame_position == "end":
        return max(in_frame, last_frame)
    if frame_position == "middle":
        return in_frame + (last_frame - in_frame) // 2
    return in_frame

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
resize_height = int(data.get("resizeHeight", 512))  # 0 = Original / no downscale
frame_position = data.get("framePosition", "start")  # "start" | "middle" | "end"

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

    log(f"{len(clips)} shot(s) requested, frame position={frame_position}")

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
        # A dedicated, deterministically-named album owned by this script — created once and
        # reused on later runs, rather than guessing among whatever albums happen to already
        # exist (the album name is looked up/set via Gallery.GetAlbumName/SetAlbumName; those are
        # the only documented rename calls — GalleryStillAlbum.GetLabel/SetLabel are a different,
        # per-still API and were being called on the album by mistake in an earlier version of
        # this script, which is why the album could never actually get renamed and kept showing
        # up "Nameless" on every run).
        ALBUM_NAME = "Resolver_Stills"
        log("Getting Gallery Still Albums...")

        albums = gallery.GetGalleryStillAlbums() or []
        target_album = next((a for a in albums if gallery.GetAlbumName(a) == ALBUM_NAME), None)

        if not target_album:
            log(f"No existing '{ALBUM_NAME}' album — creating one.")
            target_album = gallery.CreateGalleryStillAlbum()
            if target_album and not gallery.SetAlbumName(target_album, ALBUM_NAME):
                print(json.dumps({"status": "warning", "message": f"Created a still album but couldn't rename it to '{ALBUM_NAME}'."}))

        if not target_album:
            err_msg = "Could not find or create a Gallery Still Album (CreateGalleryStillAlbum failed). Please create one manually in Color Page > Gallery."
            print(json.dumps({"status": "error", "message": err_msg}))
            raise Exception(err_msg) # Abort immediately

        log(f"Using album: {gallery.GetAlbumName(target_album) or ALBUM_NAME}")
        gallery.SetCurrentStillAlbum(target_album)

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

            # No track soloing — the still is grabbed exactly as the timeline currently looks
            # (whatever video tracks/clips are enabled/visible stay that way).
            try:
                for clip in group_clips:
                    name = clip["name"]
                    try:
                        # Get timeline frame rate
                        fps = timeline.GetSetting("timelineFrameRate")

                        tc_in = clip.get("tcIn", "")
                        tc_out = clip.get("tcOut", "")
                        target_frame = target_frame_for(tc_in, tc_out, fps, frame_position)
                        target_tc = frames_to_tc(target_frame, fps) if target_frame is not None else tc_in

                        if target_tc:
                             timeline.SetCurrentTimecode(target_tc)
                             time.sleep(0.2) # Allow Resolve to seek

                        # Force Switch to Target Album to ensure GrabStill puts it there
                        if target_album:
                            gallery.SetCurrentStillAlbum(target_album)

                        # Grab Still
                        log(f"Grabbing still for '{name}' at {target_tc} ({processed_count + 1}/{total_clips})...")
                        still = timeline.GrabStill()
                        time.sleep(0.05) # Brief pause to ensures still is ready

                        if not still:
                            # Retry once immediately without sleep
                            still = timeline.GrabStill()

                        if still:
                            # === EXPORT ===
                            # 1. Snapshot valid files before
                            files_before = set(os.listdir(output_dir))

                            # 2. Export with UNIQUE Name (UUID) to avoid collisions/overwriting
                            import uuid
                            temp_export_name = str(uuid.uuid4())

                            if not os.access(output_dir, os.W_OK):
                                print(json.dumps({"status": "error", "message": f"Output dir not writable: {output_dir}"}))

                            # Export straight to our own dedicated album (see Album Management
                            # above) — no more guessing across every album in the project. One
                            # retry after a brief pause in case Resolve's Gallery state needs a
                            # moment to catch up right after GrabStill.
                            success = target_album.ExportStills([still], output_dir, temp_export_name, export_format)
                            if not success:
                                time.sleep(0.2)
                                success = target_album.ExportStills([still], output_dir, temp_export_name, export_format)

                            if not success:
                                # FATAL ERROR - Abort Script
                                err_msg = (
                                    f"FATAL: ExportStills failed for {name} into album "
                                    f"'{gallery.GetAlbumName(target_album) or ALBUM_NAME}'. Dir: {output_dir}. "
                                    "In DaVinci Resolve, open the Color Page and check the Gallery panel — make "
                                    f"sure a Still Album (ideally named '{ALBUM_NAME}') is visible there, then "
                                    "try again."
                                )
                                print(json.dumps({"status": "error", "message": err_msg}))

                                # Try to cleanup the still so it doesn't pile up
                                try:
                                    target_album.DeleteStills([still])
                                except Exception:
                                    pass

                                raise Exception(err_msg) # Abort processing
                            else:
                                # Cleanup success
                                target_album.DeleteStills([still])

                                # 3. Snapshot files after
                                files_after = set(os.listdir(output_dir))
                                new_files = list(files_after - files_before)

                                # Filter for our export format
                                image_files = [f for f in new_files if f.lower().endswith(f".{export_format}")]

                                if len(image_files) >= 1:
                                    # We found a new file! Rename it to `vfxName_YYYYMMDD-HHMMSS.jpg` —
                                    # the timestamp lets freshness be checked at a glance (on disk, or
                                    # via ClipData's "Thumbnail Updated" column the Swift side stamps
                                    # from this file's modification date) without needing to open it.
                                    exported_filename = image_files[0]
                                    exported_path = os.path.join(output_dir, exported_filename)

                                    timestamp = time.strftime("%Y%m%d-%H%M%S")
                                    target_filename = f"{name}_{timestamp}.{export_format}"
                                    target_path = os.path.join(output_dir, target_filename)

                                    # Remove this exact clip's older thumbnail(s) — both this
                                    # timestamped naming scheme and the old stable `name.ext` one —
                                    # so a regenerate doesn't leave stale files lying around next to
                                    # the new one (which would make "the" thumbnail for this clip
                                    # ambiguous to any by-name file lookup). Matched with a regex
                                    # (not just startswith) so a clip whose name is a strict prefix
                                    # of another's (e.g. "SH010" vs "SH010A") never deletes its
                                    # neighbor's thumbnail.
                                    escaped_name = re.escape(name)
                                    old_pattern = re.compile(
                                        rf"^{escaped_name}(?:_\d{{8}}-\d{{6}})?\.[^.]+$"
                                    )
                                    for f in os.listdir(output_dir):
                                        if f != exported_filename and old_pattern.match(f):
                                            try:
                                                os.remove(os.path.join(output_dir, f))
                                            except Exception:
                                                pass

                                    try:
                                        os.rename(exported_path, target_path)
                                    except Exception as mv_err:
                                        print(json.dumps({"status": "warning", "message": f"Failed to rename {exported_filename}: {mv_err}"}))
                                        target_path = exported_path

                                    # 4. Resize (resize_height <= 0 means "Original" — leave it untouched)
                                    if resize_height > 0:
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
                pass  # No track state to restore — thumbnails no longer solo a track.
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
