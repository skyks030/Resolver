---
name: resolve-script-bridge
description: Conventions for writing or modifying Python scripts under Resolver/Scripts/Resolve/** and their Swift call sites, so the PyScriptRunner contract and DaVinci Resolve API connection pattern stay consistent. Use whenever adding a new Resolve script, changing how a script returns data to Swift, or wiring a new PyScriptRunner.run(scriptName:) call site.
user-invocable: false
---

# Resolve Script Bridge

Background knowledge for keeping Python scripts under `Resolver/Scripts/Resolve/**` consistent with how
`PyScriptRunner.swift` invokes them. Apply this automatically whenever creating or editing a script in that
tree, or a Swift call site that runs one — don't wait to be asked.

## Connection pattern (canonical: `Tools/check_resolve.py`)

Every script that talks to Resolve should load the API the same way, with distinct exit/error codes per
failure point so failures are diagnosable from the log file alone:

1. Import `DaVinciResolveScript` from
   `/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules/DaVinciResolveScript.py`
   (or via the `RESOLVE_SCRIPT_API`/`PYTHONPATH` env vars Resolve sets when it launches scripts itself — check
   `check_resolve.py` for the exact fallback chain before assuming one).
2. `dvr = bmd.scriptapp("Resolve")` — if this returns `None`, Resolve isn't running or external scripting
   isn't enabled (Preferences > System > General > External scripting using = Local/Network). Fail with a
   distinct message, don't silently continue.
3. `pm = dvr.GetProjectManager()`, then `project = pm.GetCurrentProject()` — each can independently fail if
   no project is open; give each its own error path rather than one generic catch-all.

## Swift ↔ Python data contract

- `scriptName` passed to `PyScriptRunner.run(scriptName:)` is a path relative to `Scripts/`, **without** the
  `.py` extension, e.g. `"Resolve/VFX/clip-indexing"`.
- Large/structured return data must go through the `RESOLVER_OUTPUT_FILE` env var (a temp JSON path Swift
  provides), **not** stdout — stdout can deadlock on large output. Small status/log lines can still go to
  stdout since it's tee'd into the crash log.
- Before adding a new call site in Swift, check whether the script writes JSON to `RESOLVER_OUTPUT_FILE` or
  prints to stdout, and read it back the matching way — don't assume.
- In dev mode, `PyScriptRunner` runs `/Users/skymuller/Git/Resolver/Resolver/Scripts/<scriptName>.py` directly
  if it exists (a convenience specific to the original dev machine, not portable). Otherwise it resolves the
  script inside the app bundle's `Scripts/` resource directory.
- All subprocess output (stdout+stderr) is tee'd into a persistent log via `CrashManager.shared.createLogFile`
  — don't add a second, separate logging path in new scripts.

## When writing a new script

- Put it under the right subtree: `VFX/` for the main clip indexing/grouping/marker/thumbnail workflows that
  drive the main app UI, `Tools/` for standalone diagnostic/utility scripts, `render-done/` for the
  render-notification mini-toolset.
- Decide up front whether it returns structured data (→ `RESOLVER_OUTPUT_FILE` JSON) or is fire-and-forget
  (→ stdout status lines + exit code), and keep that decision consistent with how the new Swift call site
  reads it back.
- Reuse the connection/error-code pattern above rather than inventing a new one per script.
