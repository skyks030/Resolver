#!/usr/bin/env python3

import sys
import os
import importlib.util
import json

def check_davinci():
    try:
        # 1. API Installation Check
        sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
        sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")
        
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
            
        # 4. Timeline Check
        timeline = project.GetCurrentTimeline()
        
        if not timeline:
            return {
                "success": False,
                "error_code": "NO_TIMELINE",
                "message": "Es ist momentan keine Timeline in DaVinci Resolve geöffnet.",
                "tips": [
                    "Bitte öffnen Sie die Timeline, mit der Sie in Resolver arbeiten möchten."
                ]
            }
            
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
    print(json.dumps(result, indent=2))
