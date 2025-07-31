#!/usr/bin/env python3

import os
import sys
import importlib.util
import time

import urllib.request
import ssl

def ssl_check_via_https():
    try:
        with urllib.request.urlopen("https://www.google.com", timeout=5) as response:
            return response.status == 200
    except ssl.SSLError as e:
        print(f"❌ SSL-Fehler: {e}")
        return False
    except Exception as e:
        print(f"⚠️ Verbindungsfehler (nicht SSL-spezifisch): {e}")
        return False

# Beispielverwendung
if not ssl_check_via_https():
    print("🚨 Deine Python-Installation scheint keine gültigen SSL-Zertifikate zu haben.")
    print("Bitte führe folgendes Skript einmalig aus")
    print("which python3")
    print("/Applications/Python\ 3.*/Install\ Certificates.command")
    exit(1)



# === Pfad zur DaVinci Resolve Scripting API (macOS) ===
sdk_path = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
sdk_file = os.path.join(sdk_path, "DaVinciResolveScript.py")

if not os.path.exists(sdk_file):
    print(f"❌ SDK-Datei nicht gefunden: {sdk_file}")
    sys.exit(1)

spec = importlib.util.spec_from_file_location("DaVinciResolveScript", sdk_file)
dvr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dvr)

import DaVinciResolveScript as dvr

resolve = dvr.scriptapp("Resolve")
if not resolve:
    print("❌ Verbindung zu DaVinci Resolve konnte nicht hergestellt werden.")
    sys.exit(1)

def IsRenderingInProgress( resolve ):
    projectManager = resolve.GetProjectManager()
    project = projectManager.GetCurrentProject()
    if not project:
        return False

    return project.IsRenderingInProgress()

def WaitForRenderingCompletion( resolve ):
    while IsRenderingInProgress(resolve):
        time.sleep(1)
    return

import http.client
import json
from urllib.parse import urlparse

# === HIER DEIN WEBHOOK EINTRAGEN ===
WEBHOOK_URL = "https://prod-52.westeurope.logic.azure.com:443/workflows/b3e5ac260605402d993614b3ae30047f/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=8rVW6W0GQkEidvHA6KwTw9yh3FPGnFPoftEQJ0Tan6M"

def send_teams_message(message):
    url = urlparse(WEBHOOK_URL)
    conn = http.client.HTTPSConnection(url.hostname, url.port or 443)

    headers = { "Content-Type": "application/json" }
    body = json.dumps({ "text": message })

    try:
        conn.request("POST", url.path + "?" + url.query, body, headers)
        response = conn.getresponse()
        print(f"✅ Nachricht gesendet")
    except Exception as e:
        print(f"❌ Fehler beim Senden: {e}")
    finally:
        conn.close()

WaitForRenderingCompletion(resolve)

send_teams_message("✅ Done.")
