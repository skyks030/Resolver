#!/usr/bin/env python3

import sys
import os
import importlib.util
import json

def log(message):
    """Debug breadcrumb, shown in Resolver's Debug Mode console. Every meaningful step prints
    one of these so a hang or crash can be pinpointed to the exact step it happened at."""
    print(json.dumps({"status": "debug", "message": message}))
    sys.stdout.flush()

def check_davinci():
    try:
        # 1. API Installation Check
        sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
        sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")

        log("Checking for DaVinci Resolve Scripting API...")
        if not os.path.exists(sdk_file):
            return {
                "success": False,
                "error_code": "API_NOT_FOUND",
                "message": "Die DaVinci Resolve Scripting API konnte auf Ihrem Mac nicht gefunden werden.",
                "tips": [
                    "Haben Sie DaVinci Resolve Studio installiert? Die Standard/Free Version unterstützt kein externes Scripting.",
                    "Haben Sie die aktuellste Version installiert?"
                ]
            }

        # Try loading API
        log("Loading DaVinci Resolve Scripting API...")
        try:
            spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
            dvr = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(dvr)
            import DaVinciResolveScript as dvr
        except Exception as api_err:
             return {
                "success": False,
                "error_code": "API_LOAD_ERROR",
                "message": f"Die DaVinci Resolve API konnte zwar gefunden, aber nicht geladen werden ({str(api_err)}).",
                "tips": [
                    "Haben Sie die richtige Python-Version installiert (Python 3.6+ empfohlen für DaVinci API)?",
                    "Versuchen Sie DaVinci Resolve neu zu starten."
                ]
            }

        # 2. Connection Check
        log("Connecting to Resolve...")
        resolve = dvr.scriptapp("Resolve")
        if not resolve:
            return {
                "success": False,
                "error_code": "NO_CONNECTION",
                "message": "Resolver konnte keine aktive Verbindung zu DaVinci Resolve herstellen.",
                "tips": [
                    "Ist DaVinci Resolve geöffnet und läuft im Hintergrund?",
                    "Ist unter 'DaVinci Resolve > Preferences > System > General' die Einstellung 'External scripting using' auf 'Local' (oder Network) gesetzt?",
                    "Haben Sie DaVinci Resolve nach dem Ändern dieser Einstellung neugestartet?"
                ]
            }

        # 3. Project Check
        log("Getting project manager and current project...")
        pm = resolve.GetProjectManager()
        project = pm.GetCurrentProject()

        if not project:
            return {
                "success": False,
                "error_code": "NO_PROJECT",
                "message": "Es wurde kein aktives Projekt in DaVinci Resolve gefunden.",
                "tips": [
                    "Bitte öffnen Sie ein Projekt, bevor Sie Daten nach Resolver importieren oder aktualisieren."
                ]
            }

        # NOTE: There used to be a hard "Timeline Check" here (step 4) that failed the whole
        # preflight if no timeline was currently open in Resolve's Edit page. That blocked every
        # episode-aware feature (Index All Episodes, the Groups/Markers toggle buttons, Thumbnails)
        # before they ever got a chance to run — those features are specifically meant to open the
        # right timeline(s) themselves, and shouldn't require the user to have one pre-opened.
        # Whether a specific operation actually needs an active timeline is now checked by that
        # operation's own script (e.g. clip-indexing.py's single-timeline path), which can give a
        # precise, contextual error instead of this generic one blocking unrelated flows.
        log(f"Connected. Project: '{project.GetName() if hasattr(project, 'GetName') else '?'}'")
        return {
            "success": True,
            "error_code": "OK",
            "message": "DaVinci Resolve ist erfolgreich verbunden und einsatzbereit.",
            "tips": []
        }

    except Exception as e:
        return {
            "success": False,
            "error_code": "UNKNOWN_PYTHON_ERROR",
            "message": f"Unerwarteter Python-Systemfehler: {str(e)}",
            "tips": [
                "Bitte senden Sie den Fehler-Code an den Entwickler.",
                "Starten Sie Resolver und DaVinci Resolve neu."
            ]
        }

if __name__ == "__main__":
    result = check_davinci()
    # Single-line JSON, not indent=2: the debug breadcrumbs above are also one JSON object per
    # line, and Resolver's Swift side (DaVinciChecker) now pulls out the LAST JSON-looking line
    # rather than decoding the whole multi-line output as one document — a pretty-printed,
    # multi-line result here would never match that.
    print(json.dumps(result))
