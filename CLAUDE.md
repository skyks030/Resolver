# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Resolver is a macOS menu-bar app (SwiftUI + AppKit, `MenuBarExtra`) that helps VFX/episode teams manage clip
metadata for DaVinci Resolve projects. It bundles a set of Python scripts that talk to DaVinci Resolve's
Scripting API (via the `DaVinciResolveScript` module Resolve/Studio installs locally) to read/write markers,
clip names, groups, thumbnails, etc. from inside the running Resolve session, and a Swift UI layer on top for
project/episode/scene management, CSV import/export, and merging edits back into DaVinci.

## Build & run

There is no Swift package manifest — it's a standard Xcode project (`Resolver.xcodeproj`, scheme `Resolver`).

```bash
# Build (Debug) from the command line
xcodebuild -scheme Resolver -configuration Debug build

# Build a Release universal binary (arm64 + x86_64), same as deploy.sh does
xcodebuild -scheme Resolver -configuration Release -derivedDataPath Build/build_xcode ARCHS="arm64 x86_64" clean build
```

There is no automated Swift test target in this project — verification is manual, by running the app against
a real DaVinci Resolve session (Resolve must be running with Preferences > System > General >
"External scripting using" set to Local/Network).

Full release flow (version bump, build, DMG creation with styled Finder window, commit + push) is scripted in
`Resolver/deploy.sh` — run it interactively from `Resolver/`; it prompts for the new version number and expects
`MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` to be bumped together in `project.pbxproj`.

### Python scripts

Scripts under `Resolver/Scripts/Resolve/**` have no separate build step; they run via `/usr/bin/python3` on
the host, invoked by the Swift app (see below). To smoke-test one standalone, DaVinci Resolve must be open:

```bash
python3 Resolver/Scripts/Resolve/Tools/check_resolve.py
```

## Architecture

### Swift ↔ Python bridge (`PyScriptRunner.swift`)

This is the core integration point and the thing most features route through. `PyScriptRunner.run(scriptName:...)`:

- In **dev mode**, if `/Users/skymuller/Git/Resolver/Resolver/Scripts/<scriptName>.py` exists on disk, it runs
  that file directly (this hardcoded path only works on the original dev machine — it's a convenience fallback,
  not something to rely on elsewhere).
- Otherwise it resolves the script inside the app bundle's `Scripts/` resource directory (several lookup
  strategies are tried since folder-reference vs. group behavior differs).
- The script is run as a subprocess of `/usr/bin/python3`. Because stdout pipes can deadlock on large output,
  scripts also get a `RESOLVER_OUTPUT_FILE` env var pointing at a temp JSON file — scripts that need to return
  structured data write JSON there rather than (or in addition to) stdout. Any Swift call site adding a new
  script that returns data must know whether that script writes to stdout or to `RESOLVER_OUTPUT_FILE`.
- All subprocess output is also tee'd into a persistent log file via `CrashManager.shared.createLogFile`.
- `scriptName` is a path relative to `Scripts/`, without extension, e.g. `"Resolve/VFX/clip-indexing"`.

When adding or modifying a Python script that's meant to be called from Swift, keep it consistent with this
contract (env var name, JSON shape, exit behavior) — don't assume stdin/stdout is a safe channel for large data.

### Python scripts (`Resolver/Scripts/Resolve/`)

- `VFX/` — the main clip workflow: indexing/naming clips (`clip-indexing.py`), grouping (`clip-grouping.py`),
  cleaning groups/markers, exporting scene markers, generating thumbnails. These are the scripts the main app
  UI drives.
- `Tools/` — smaller diagnostic/utility scripts (checking the Resolve connection, listing timelines/markers,
  Excel export, finding duplicate clips) — several are usable standalone for debugging a Resolve connection
  issue.
- `render-done/` — separate mini-toolset (per-user variants `render-done-simon.py` / `render-done-sky.py`,
  a webhook sender, transcription) for notifying when a render finishes; less coupled to the rest of the app.

All scripts talk to Resolve through `DaVinciResolveScript`, loaded from
`/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules/DaVinciResolveScript.py`
(see `Tools/check_resolve.py` for the canonical connection/health-check pattern: load API → `dvr.scriptapp("Resolve")`
→ `GetProjectManager()` → `GetCurrentProject()`, with distinct error codes for each failure point).

### Swift data & persistence layer

- **`ProjectManager`** (`ProjectManager.swift`) is the app's central `ObservableObject`/state store, injected via
  `.environmentObject` from `ResolverApp`. It owns the list of `Project`s and the currently active project's
  `currentMasterList` ([`ClipData`]), `currentScenes`, and `currentEpisodes`. Each project's data is persisted
  as JSON files under `Application Support/Resolver/<project>/` (separate load/save pairs for scenes, episodes,
  and the master clip list — see `loadScenes`/`saveScenes`, `loadEpisodes`/`saveEpisodes`,
  `loadMasterList`/`saveMasterList`).
- **`ClipData`** (in `ProjectManager.swift`) is the core clip record. It's backed by a single `[String: String]`
  dictionary (`dict`) rather than fixed fields, so it can carry arbitrary custom metadata columns (from CSV
  import etc.) alongside well-known keys (`VFX Name`, `TC In/Out`, `Source TC In/Out`, `Frame Start/End`,
  `Duration`, `Reel Name`, `Resolve Unique ID`, ...). Convenience computed properties wrap `dict` lookups —
  add new well-known fields the same way rather than introducing parallel stored properties. Its `Codable`
  implementation has a custom decoder to stay backward-compatible with older saved JSON that used discrete
  keys instead of `dict`.
- **`MergeManager`** (`MergeManager.swift`) implements the diff/merge between the project's master `[ClipData]`
  and a freshly imported/fetched list (DaVinci Resolve index, CSV, or a linked Sheet Sync provider).
  `compareColumnAware` matches each imported clip to a master clip in two passes — first the cheap, precise
  exact-signal tiers (Resolve Unique ID → source range → source trim → clip name, reconform-aware), then a
  generic column-overlap scorer for whatever's left (every remaining pair scores by how many dict columns
  agree, assigned highest-score-first) — so a shot survives a rename/retrim as long as it still shares enough
  other columns, without a manual "force this field" override. Unmatched imports become `.new` (with
  near-miss `candidateMasterClips` to seed manual relinking); `MergeManager.missingItems` wraps master clips
  no import claimed as `.missing` (used only by the one-way DaVinci/CSV import flow — a shot Resolve no
  longer has is a discrepancy, resolved either by dismissing it or flagging it `ClipData.isRemoved`, a
  reversible soft-delete, never an actual row deletion). `applyMerge` writes each item's per-column
  `fieldWinners` decision into the master list, skipping anything not yet `isResolved`; `quickMerge` is a
  no-review variant for the menu-bar quick-reindex shortcut. `SyncReviewView` is the one shared review window
  (DaVinci/CSV import and Sheet Sync's "Compare Now" both present it) for resolving matches, relinking, and
  per-column conflicts before applying — see its own doc comment for the full model.
- **`CrashManager`** (`CrashManager.swift`) is a singleton that writes a lock file on session start
  (`Application Support/Resolver/app.lock`) and checks for it on next launch to detect unclean shutdowns,
  surfacing the most recent log via `CrashReportView`. It also owns log-file creation used by `PyScriptRunner`.
- **`UserManager`** is a minimal static two-user registry (Simon/Sky) used to route render-done notifications
  to per-user webhook URLs — not a real auth system.

### UI layer

SwiftUI views live flat under `Resolver/` (no subfolders): `ProjectExportView` is the main window;
`EpisodeManagementView`/`SceneManagementView` manage episode/scene metadata; `CSVImportView` +
`DaVinciImportSheet`/`ThumbnailImportSheet` handle import flows into the merge pipeline; `MarkerToolView` and
`DoubleClipsView` are auxiliary tool windows; `DropDownMenu` is the menu-bar UI. Windows/scenes are declared
centrally in `ResolverApp.swift` (`WindowGroup`/`Window`/`MenuBarExtra`/`Settings`), each wired to
`ProjectManager` via `.environmentObject`.

`UpdateChecker` runs an update check at launch (`ResolverApp.init`); `AppDelegate` handles NSApplication-level
lifecycle hooks alongside the SwiftUI App struct.
