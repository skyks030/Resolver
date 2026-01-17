
import os
import sys
import importlib.util
import time

import urllib.request
import ssl

import http.client
import json
from urllib.parse import urlparse

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

# ssl_check_via_https()
if not ssl_check_via_https():
    print("🚨 Deine Python-Installation scheint keine gültigen SSL-Zertifikate zu haben.")
    print("Bitte führe folgendes Skript einmalig aus")
    print("which python3")
    print("/Applications/Python\ 3.*/Install\ Certificates.command")
    exit(1)


WEBHOOK_URL_simon = "https://prod-132.westeurope.logic.azure.com:443/workflows/0e729775c9934cdc8f977c11e8699b25/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=KPyErjK1CNb3iTpD3N_auMDYTF95xjSe7uaCfzfUSrE"

WEBHOOK_URL_sky = "https://prod-52.westeurope.logic.azure.com:443/workflows/b3e5ac260605402d993614b3ae30047f/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=8rVW6W0GQkEidvHA6KwTw9yh3FPGnFPoftEQJ0Tan6M"



def send_teams_message(message):
    url = urlparse(WEBHOOK_URL_sky)
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

send_teams_message("✅ Done.")
