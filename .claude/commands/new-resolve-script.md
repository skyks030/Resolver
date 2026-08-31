---
description: Scaffold a new Python script under Resolver/Scripts/Resolve/** with the standard Resolve connection boilerplate and Swift bridge output pattern
argument-hint: <VFX|Tools|render-done>/<script-name> [stdout|output-file]
---

Create a new Resolve Python script and (if useful) its Swift call site.

Arguments: `$ARGUMENTS` — first token is `<category>/<script-name>` (category is `VFX`, `Tools`, or
`render-done`, matching the subfolders under `Resolver/Scripts/Resolve/`), second optional token is
`stdout` or `output-file` to pick the Swift data-return channel (default: `output-file` if the script needs to
return structured data, `stdout` if it's fire-and-forget).

Load [[resolve-script-bridge]] skill conventions (connection pattern, `RESOLVER_OUTPUT_FILE` vs stdout
contract, `scriptName` path rules) and apply them here — don't reinvent the pattern.

1. Create `Resolver/Scripts/Resolve/<category>/<script-name>.py` with:
   - The canonical Resolve connection chain from `Tools/check_resolve.py` (import `DaVinciResolveScript`,
     `scriptapp("Resolve")`, `GetProjectManager()`, `GetCurrentProject()`), each step with its own error exit
     code/message.
   - If `output-file`: read `RESOLVER_OUTPUT_FILE` from `os.environ`, build the result as a dict, write it as
     JSON there, and also print a short human-readable status line to stdout.
   - If `stdout`: print status/result lines directly, no `RESOLVER_OUTPUT_FILE` handling.
2. Ask whether a Swift call site is also wanted; if yes, show (don't necessarily create, unless asked) the
   `PyScriptRunner.run(scriptName: "Resolve/<category>/<script-name>", ...)` call and the matching read-back
   (temp-file JSON decode, or captured stdout) so it matches what the script actually writes.
3. Remind: `scriptName` passed to `PyScriptRunner` is relative to `Scripts/`, without `.py`.
