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
    "rows": [ {"col": "value", ...}, ... ]   # only for action == "write" — upserted by the
                                              # "Resolve Unique ID" column, appended if not found
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

RESOLVE_ID_COLUMN = "Resolve Unique ID"


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


def build_header(existing_values, rows):
    """Union of the sheet's current header (order preserved) and every column appearing in the
    rows about to be pushed, so a brand-new/empty sheet — or one missing a column Resolver now
    wants to write — gets its header widened instead of silently dropping that data."""
    header = [str(h) for h in existing_values[0]] if existing_values else []
    seen = set(header)
    for row in rows:
        for col in row.keys():
            if col not in seen:
                header.append(col)
                seen.add(col)
    if RESOLVE_ID_COLUMN not in seen:
        header.append(RESOLVE_ID_COLUMN)
    return header


def build_id_index(header, existing_values):
    id_col_idx = header.index(RESOLVE_ID_COLUMN)
    id_row_index = {}
    for i, raw_row in enumerate(existing_values[1:] if existing_values else [], start=1):
        rid = raw_row[id_col_idx] if id_col_idx < len(raw_row) else None
        if rid:
            id_row_index[rid] = i
    return id_row_index


def apply_upserts(existing_values, rows):
    header = build_header(existing_values, rows)
    id_row_index = build_id_index(header, existing_values)

    values = [list(r) for r in existing_values] if existing_values else []
    if not values:
        values = [header]
    elif len(values[0]) < len(header):
        # Widen the existing header row with any newly-introduced columns. Existing data rows
        # keep their original (shorter) length — reading a missing trailing cell as "" (see
        # build_id_index/values_to_rows) already handles that, so nothing else needs to change.
        values[0] = header

    for row in rows:
        rid = row.get(RESOLVE_ID_COLUMN)
        new_row = [row.get(col, "") for col in header]
        if rid and rid in id_row_index:
            values[id_row_index[rid]] = new_row
        else:
            values.append(new_row)
            if rid:
                id_row_index[rid] = len(values) - 1
    return values


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


def ms_write(link, sheet_name, rows, token):
    log("Resolving Excel share link via Microsoft Graph...")
    drive_id, item_id = ms_resolve_drive_item(link, token)
    if not sheet_name:
        sheet_name = ms_first_worksheet_name(drive_id, item_id, token)

    log(f"Reading current worksheet '{sheet_name}' to merge in new/updated rows...")
    existing = http_json("GET", ms_used_range_url(drive_id, item_id, sheet_name), token)
    existing_values = existing.get("values", [])
    new_values = apply_upserts(existing_values, rows)

    log(f"Writing {len(new_values)} row(s) (incl. header) back to '{sheet_name}'...")
    address = f"A1:{col_letter(len(new_values[0]))}{len(new_values)}"
    encoded_sheet = urllib.parse.quote(sheet_name)
    write_url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/items/{item_id}/workbook/worksheets('{encoded_sheet}')/range(address='{address}')"
    http_json("PATCH", write_url, token, body={"values": new_values})
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


def google_write(link, sheet_name, rows, token):
    spreadsheet_id = google_spreadsheet_id(link)
    if not sheet_name:
        sheet_name = google_first_sheet_name(spreadsheet_id, token)

    log(f"Reading current sheet '{sheet_name}' to merge in new/updated rows...")
    range_ = urllib.parse.quote(sheet_name)
    url = f"https://sheets.googleapis.com/v4/spreadsheets/{spreadsheet_id}/values/{range_}"
    existing = http_json("GET", url, token)
    existing_values = existing.get("values", [])
    new_values = apply_upserts(existing_values, rows)

    log(f"Writing {len(new_values)} row(s) (incl. header) back to '{sheet_name}'...")
    write_url = f"https://sheets.googleapis.com/v4/spreadsheets/{spreadsheet_id}/values/{range_}?valueInputOption=RAW"
    http_json("PUT", write_url, token, body={"values": new_values})
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
            if provider == "microsoft":
                count = ms_write(link, sheet_name, rows, token)
            else:
                count = google_write(link, sheet_name, rows, token)
            log(f"Wrote {count} row(s).")
            print(json.dumps({"status": "success", "written": count}))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
