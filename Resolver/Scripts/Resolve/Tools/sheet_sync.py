#!/usr/bin/env python3
"""
sheet_sync.py
Reads or writes rows in a linked Microsoft Excel Online (OneDrive for Business/SharePoint) or
Google Sheets document, given an already-valid OAuth access token. Sign-in itself happens natively
in Swift (ASWebAuthenticationSession needs a live window, so it can't run in a subprocess) — this
script only ever makes already-authenticated REST calls, using nothing beyond the Python standard
library (no extra pip dependency to install for this feature).

Input (argv[1], a JSON file):
  {
    "action": "fetch" | "write" | "whoami",
    "provider": "microsoft" | "google",
    "accessToken": "...",
    "link": "https://...",                  # the pasted share/document URL — not needed for "whoami"
    "sheetName": "Sheet1" or null,           # null = first sheet/worksheet
    "rows": [ {"col": "value", ...}, ... ],  # only for action == "write" — upserted by the
                                              # "VFX Name" column, appended if not found/blank
    "columnOrder": ["VFX Name", ...] or null # only for action == "write" — the master list's
                                              # current display order, used for any brand-new
                                              # column a fresh/empty sheet doesn't have yet
  }

Output (stdout, single JSON line):
  fetch:   {"status": "success", "rows": [ {"col": "value", ...}, ... ], "sheetName": "..."}
  write:   {"status": "success", "written": N}
  whoami:  {"status": "success", "name": "...", "email": "..."} — used by Settings' "Test
           Sign-In", to confirm a Client ID/Secret + sign-in actually works before ever linking
           a real sheet.
  or:      {"error": "..."}
"""

import sys
import os
import json
import re
import base64
import urllib.request
import urllib.parse
import urllib.error


def log(message):
    """Debug breadcrumb, shown in Resolver's Debug Mode console."""
    print(json.dumps({"status": "debug", "message": message}))
    sys.stdout.flush()


def http_json(method, url, token, body=None):
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise Exception(f"HTTP {e.code} from {url}: {detail}")


# === Shared row <-> 2D-values conversion ===

# Which column identifies "the same shot" between an outgoing row and an existing sheet row, so a
# repeat sync updates that row in place instead of appending a duplicate. Real shot data — a
# synced sheet, unlike a DaVinci Resolve import, reliably carries an actual VFX Name — rather than
# a synthetic per-clip ID (Resolver doesn't generate one; see MergeManager's column-aware matcher).
UPSERT_KEY_COLUMN = "VFX Name"


def values_to_rows(values):
    if not values:
        return []
    header = [str(h) for h in values[0]]
    rows = []
    for raw_row in values[1:]:
        if not any(str(v).strip() for v in raw_row):
            continue
        row = {}
        for i, col_name in enumerate(header):
            row[col_name] = str(raw_row[i]) if i < len(raw_row) else ""
        rows.append(row)
    return rows


def build_header(existing_values, rows, column_order=None):
    """Union of the sheet's current header (order preserved) and every column appearing in the
    rows about to be pushed, so a brand-new/empty sheet — or one missing a column Resolver now
    wants to write — gets its header widened instead of silently dropping that data. No column is
    force-injected here beyond what the data actually contains.

    New columns (nothing existing to anchor an order on) follow `column_order` — the master
    list's current display order, passed by Swift — rather than a row dict's key order, which
    Swift's JSON encoding doesn't preserve at all (so without this, a brand-new sheet's very
    first write would land its columns in an effectively random order)."""
    header = [str(h) for h in existing_values[0]] if existing_values else []
    seen = set(header)
    ordered_new_cols = list(column_order or [])
    all_cols = set()
    for row in rows:
        all_cols.update(row.keys())
    # column_order may be missing/stale columns (e.g. a column added after it was captured) —
    # append those at the end, still in a stable (sorted) order rather than dict-iteration order.
    ordered_new_cols += sorted(all_cols - set(ordered_new_cols))
    for col in ordered_new_cols:
        if col in all_cols and col not in seen:
            header.append(col)
            seen.add(col)
    return header


def build_id_index(header, existing_values):
    """Maps each existing row's UPSERT_KEY_COLUMN value to its 1-indexed data row. Every raw cell
    value is coerced through `str()` before comparing — both Excel and Google Sheets can hand a
    cell back as a native number/bool instead of the original text (e.g. Microsoft Graph's own
    docs note it "may remove leading zeros... and convert codes like '5E2' into the number 500"),
    so a VFX Name that merely *looks* numeric would otherwise never match the plain string Swift
    sends, and get silently appended as a duplicate row forever instead of updating in place.
    `values_to_rows` (the fetch/compare path) already does this same coercion; this just makes
    the write/upsert path consistent with it."""
    if UPSERT_KEY_COLUMN not in header:
        return {}
    id_col_idx = header.index(UPSERT_KEY_COLUMN)
    id_row_index = {}
    for i, raw_row in enumerate(existing_values[1:] if existing_values else [], start=1):
        raw_value = raw_row[id_col_idx] if id_col_idx < len(raw_row) else None
        rid = str(raw_value) if raw_value not in (None, "") else None
        if rid:
            id_row_index[rid] = i
    return id_row_index


def plan_upserts(existing_values, rows, column_order=None):
    """Builds a *minimal* write plan instead of a full rewritten grid: only the header (if it
    genuinely widened), the specific existing rows that actually changed, and any brand-new rows
    to append. Nothing else already in the sheet is ever touched or resent.

    This replaces an earlier version that read the whole used range, rebuilt one big rectangular
    grid locally, and PATCHed the entire thing back. That had a real bug: widening the header row
    to fit a newly-introduced column left every *untouched* data row at its old (shorter) length,
    so the grid being written was jagged — not a problem for reading a row back (a missing
    trailing cell just reads as ""), but Microsoft Graph's range PATCH requires a perfectly
    rectangular array matching the target address exactly, and rejected it with "the number of
    rows or columns in the input array doesn't match the size or dimensions of the range"
    (InvalidArgument). Writing only the rows that actually changed, each individually sized to
    its own content, can't hit that class of bug at all — every single write is trivially
    rectangular (one row, or one contiguous new-rows block, each padded to exactly its own
    column count)."""
    old_header = [str(h) for h in existing_values[0]] if existing_values else []
    header = build_header(existing_values, rows, column_order)
    id_row_index = build_id_index(header, existing_values)  # UPSERT_KEY_COLUMN value -> 1-indexed sheet row

    # De-duplicate this batch by the upsert key first — two rows in the same write sharing a VFX
    # Name would otherwise either produce two separate PATCHes to the *same* existing sheet row
    # (Microsoft: the second silently overwrites the first with no error; Google: two identical
    # ranges in one batchUpdate call, untested/risky) or two "new" rows appended with the same
    # name. Last one in wins, deliberately, keeping the order Swift already sent them in — same
    # semantics as before, just made explicit instead of an accidental side effect of two writes
    # landing on the same address.
    deduped_rows = []
    index_by_key = {}
    for row in rows:
        rid = row.get(UPSERT_KEY_COLUMN)
        if rid and rid in index_by_key:
            deduped_rows[index_by_key[rid]] = row
        else:
            if rid:
                index_by_key[rid] = len(deduped_rows)
            deduped_rows.append(row)

    updates = []   # [(row_number, [values]), ...] — existing rows being overwritten in place
    appended = []  # [[values], ...] — brand-new rows, written as one contiguous block
    for row in deduped_rows:
        rid = row.get(UPSERT_KEY_COLUMN)
        new_row = [row.get(col, "") for col in header]
        if rid and rid in id_row_index:
            updates.append((id_row_index[rid] + 1, new_row))
        else:
            appended.append(new_row)

    existing_row_count = len(existing_values)  # includes the header row, if any
    append_start_row = (existing_row_count if existing_row_count > 0 else 1) + 1

    return {
        "header": header if header != old_header else None,
        "updates": updates,
        "appended": appended,
        "append_start_row": append_start_row,
    }


def col_letter(n):
    # 1-indexed column count -> spreadsheet column letter(s), e.g. 27 -> "AA"
    letters = ""
    while n > 0:
        n, rem = divmod(n - 1, 26)
        letters = chr(65 + rem) + letters
    return letters


# === Microsoft Excel (Graph API) ===

def ms_share_id(link):
    """Encodes a sharing URL into the 'shareId' the /shares endpoint expects: base64url of the
    raw URL, no padding, prefixed 'u!'. See:
    https://learn.microsoft.com/en-us/graph/api/shares-get"""
    b64 = base64.urlsafe_b64encode(link.encode("utf-8")).decode("ascii").rstrip("=")
    return "u!" + b64


def ms_resolve_drive_item(link, token):
    share_id = ms_share_id(link)
    url = f"https://graph.microsoft.com/v1.0/shares/{share_id}/driveItem"
    item = http_json("GET", url, token)
    drive_id = (item.get("parentReference") or {}).get("driveId")
    item_id = item.get("id")
    if not drive_id or not item_id:
        raise Exception(
            "Could not resolve the shared file from this link. Make sure it's an \"Edit\" share "
            "link for a file on OneDrive for Business or SharePoint (personal/consumer OneDrive "
            "isn't supported by Excel's workbook API)."
        )
    return drive_id, item_id


def ms_first_worksheet_name(drive_id, item_id, token):
    url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/items/{item_id}/workbook/worksheets"
    result = http_json("GET", url, token)
    sheets = result.get("value", [])
    if not sheets:
        raise Exception("The workbook has no worksheets.")
    return sheets[0]["name"]


def ms_used_range_url(drive_id, item_id, sheet_name):
    encoded_sheet = urllib.parse.quote(sheet_name)
    return f"https://graph.microsoft.com/v1.0/drives/{drive_id}/items/{item_id}/workbook/worksheets('{encoded_sheet}')/usedRange(valuesOnly=true)"


def ms_fetch(link, sheet_name, token):
    log("Resolving Excel share link via Microsoft Graph...")
    drive_id, item_id = ms_resolve_drive_item(link, token)
    if not sheet_name:
        sheet_name = ms_first_worksheet_name(drive_id, item_id, token)
    log(f"Reading worksheet '{sheet_name}'...")
    result = http_json("GET", ms_used_range_url(drive_id, item_id, sheet_name), token)
    return values_to_rows(result.get("values", [])), sheet_name


def text_number_format(values_2d):
    """A numberFormat grid matching `values_2d`'s shape, forcing every written cell to Excel's
    literal "Text" format ("@") — sent alongside `values` in the same PATCH, per Microsoft's
    documented pattern for exactly this. Without it, Excel silently reinterprets some written
    text as a different type on its own (their own docs: it "may remove leading zeros... and
    convert codes like '5E2' into the number 500") — which doesn't just show the wrong value, it
    also permanently breaks this script's own text-based row matching on the *next* sync, since
    the cell no longer contains the string that was actually written (see build_id_index)."""
    return [["@"] * len(row) for row in values_2d]


def ms_write(link, sheet_name, rows, token, column_order=None):
    log("Resolving Excel share link via Microsoft Graph...")
    drive_id, item_id = ms_resolve_drive_item(link, token)
    if not sheet_name:
        sheet_name = ms_first_worksheet_name(drive_id, item_id, token)

    log(f"Reading current worksheet '{sheet_name}' to plan the write...")
    existing = http_json("GET", ms_used_range_url(drive_id, item_id, sheet_name), token)
    existing_values = existing.get("values", [])
    plan = plan_upserts(existing_values, rows, column_order)

    encoded_sheet = urllib.parse.quote(sheet_name)

    def range_url(address):
        return f"https://graph.microsoft.com/v1.0/drives/{drive_id}/items/{item_id}/workbook/worksheets('{encoded_sheet}')/range(address='{address}')"

    # Each planned write is its own Graph call, so each one completing is a genuine step —
    # report it as it happens (Resolver's SyncReviewView shows this as a counting status bar)
    # rather than only after everything's done.
    total_writes = (1 if plan["header"] is not None else 0) + len(plan["updates"]) + (1 if plan["appended"] else 0)
    done = 0

    def report():
        nonlocal done
        done += 1
        print(f"PROGRESS: {done}/{total_writes}")
        sys.stdout.flush()

    if plan["header"] is not None:
        address = f"A1:{col_letter(len(plan['header']))}1"
        grid = [plan["header"]]
        http_json("PATCH", range_url(address), token, body={"values": grid, "numberFormat": text_number_format(grid)})
        report()

    for row_number, values in plan["updates"]:
        address = f"A{row_number}:{col_letter(len(values))}{row_number}"
        grid = [values]
        http_json("PATCH", range_url(address), token, body={"values": grid, "numberFormat": text_number_format(grid)})
        report()

    if plan["appended"]:
        start = plan["append_start_row"]
        end = start + len(plan["appended"]) - 1
        width = max(len(r) for r in plan["appended"])
        address = f"A{start}:{col_letter(width)}{end}"
        http_json("PATCH", range_url(address), token, body={"values": plan["appended"], "numberFormat": text_number_format(plan["appended"])})
        report()

    log(f"Wrote {len(plan['updates'])} updated + {len(plan['appended'])} new row(s) to '{sheet_name}'"
        f"{' (header widened)' if plan['header'] is not None else ''}.")
    return len(rows)


# === Google Sheets ===

def google_spreadsheet_id(link):
    m = re.search(r"/spreadsheets/d/([a-zA-Z0-9-_]+)", link)
    if not m:
        raise Exception("Could not find a spreadsheet ID in this link.")
    return m.group(1)


def google_first_sheet_name(spreadsheet_id, token):
    url = f"https://sheets.googleapis.com/v4/spreadsheets/{spreadsheet_id}?fields=sheets.properties.title"
    result = http_json("GET", url, token)
    sheets = result.get("sheets", [])
    if not sheets:
        raise Exception("The spreadsheet has no sheets.")
    return sheets[0]["properties"]["title"]


def google_fetch(link, sheet_name, token):
    spreadsheet_id = google_spreadsheet_id(link)
    if not sheet_name:
        sheet_name = google_first_sheet_name(spreadsheet_id, token)
    log(f"Reading sheet '{sheet_name}'...")
    url = f"https://sheets.googleapis.com/v4/spreadsheets/{spreadsheet_id}/values/{urllib.parse.quote(sheet_name)}"
    result = http_json("GET", url, token)
    return values_to_rows(result.get("values", [])), sheet_name


def google_a1_sheet(sheet_name):
    # A1-notation sheet reference for a batchUpdate range string (not a URL path segment) —
    # always single-quoted, since that's valid even for a plain name and required for one with
    # spaces/special characters; a literal quote in the name itself is escaped by doubling it,
    # per spreadsheet convention.
    return "'" + sheet_name.replace("'", "''") + "'"


def google_write(link, sheet_name, rows, token, column_order=None):
    spreadsheet_id = google_spreadsheet_id(link)
    if not sheet_name:
        sheet_name = google_first_sheet_name(spreadsheet_id, token)

    log(f"Reading current sheet '{sheet_name}' to plan the write...")
    range_ = urllib.parse.quote(sheet_name)
    url = f"https://sheets.googleapis.com/v4/spreadsheets/{spreadsheet_id}/values/{range_}"
    existing = http_json("GET", url, token)
    existing_values = existing.get("values", [])
    plan = plan_upserts(existing_values, rows, column_order)

    a1_sheet = google_a1_sheet(sheet_name)
    data = []
    if plan["header"] is not None:
        data.append({"range": f"{a1_sheet}!A1", "values": [plan["header"]]})
    for row_number, values in plan["updates"]:
        data.append({"range": f"{a1_sheet}!A{row_number}", "values": [values]})
    if plan["appended"]:
        data.append({"range": f"{a1_sheet}!A{plan['append_start_row']}", "values": plan["appended"]})

    if data:
        # One batched request for everything — Sheets' API (unlike Graph's per-range PATCH)
        # supports multiple discontiguous ranges in a single call, and each entry's range only
        # needs a starting cell — the values array's own shape determines its extent. There's only
        # ever one real network step here, so progress is coarse (0/1 → 1/1) rather than per-row —
        # still enough for Resolver's status bar to show something is actively happening.
        print("PROGRESS: 0/1")
        sys.stdout.flush()
        batch_url = f"https://sheets.googleapis.com/v4/spreadsheets/{spreadsheet_id}/values:batchUpdate"
        http_json("POST", batch_url, token, body={"valueInputOption": "RAW", "data": data})
        print("PROGRESS: 1/1")
        sys.stdout.flush()

    log(f"Wrote {len(plan['updates'])} updated + {len(plan['appended'])} new row(s) to '{sheet_name}'"
        f"{' (header widened)' if plan['header'] is not None else ''}.")
    return len(rows)


def ms_whoami(token):
    result = http_json("GET", "https://graph.microsoft.com/v1.0/me", token)
    name = result.get("displayName") or ""
    email = result.get("mail") or result.get("userPrincipalName") or ""
    return name, email


def google_whoami(token):
    result = http_json("GET", "https://www.googleapis.com/oauth2/v2/userinfo", token)
    name = result.get("name") or ""
    email = result.get("email") or ""
    return name, email


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "Missing JSON input file path"}))
        sys.exit(1)

    with open(sys.argv[1], "r") as f:
        data = json.load(f)

    action = data.get("action")
    provider = data.get("provider")
    token = data.get("accessToken")
    link = data.get("link")
    sheet_name = data.get("sheetName") or None

    if action not in ("fetch", "write", "whoami"):
        print(json.dumps({"error": "Invalid action. Must be 'fetch', 'write', or 'whoami'."}))
        sys.exit(1)
    if provider not in ("microsoft", "google"):
        print(json.dumps({"error": "Invalid provider. Must be 'microsoft' or 'google'."}))
        sys.exit(1)
    if not token:
        print(json.dumps({"error": "Missing accessToken."}))
        sys.exit(1)
    if action != "whoami" and not link:
        print(json.dumps({"error": "Missing link."}))
        sys.exit(1)

    log(f"provider={provider} action={action}")

    try:
        if action == "whoami":
            if provider == "microsoft":
                name, email = ms_whoami(token)
            else:
                name, email = google_whoami(token)
            log(f"Signed in as '{name}' <{email}>")
            print(json.dumps({"status": "success", "name": name, "email": email}))
        elif action == "fetch":
            if provider == "microsoft":
                rows, resolved_sheet = ms_fetch(link, sheet_name, token)
            else:
                rows, resolved_sheet = google_fetch(link, sheet_name, token)
            log(f"Fetched {len(rows)} row(s).")
            print(json.dumps({"status": "success", "rows": rows, "sheetName": resolved_sheet}))
        else:
            rows = data.get("rows", [])
            column_order = data.get("columnOrder")
            if provider == "microsoft":
                count = ms_write(link, sheet_name, rows, token, column_order)
            else:
                count = google_write(link, sheet_name, rows, token, column_order)
            log(f"Wrote {count} row(s).")
            print(json.dumps({"status": "success", "written": count}))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
