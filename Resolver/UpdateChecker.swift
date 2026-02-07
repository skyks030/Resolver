import Foundation
import AppKit

final class UpdateChecker {
    // MARK: - Konfiguration
    static let versionFileURLString = "https://raw.githubusercontent.com/skyks030/Resolver/main/Build/version.txt"
    static let downloadURLString = "https://raw.githubusercontent.com/skyks030/Resolver/main/Build/Resolver.dmg"

    // MARK: - Öffentliche Methode
    static func runUpdateCheck(showOutput: Bool = false) {
        checkIfUpdateAvailable(versionURLString: versionFileURLString, showOutput: showOutput) { updateAvailable, currentVersion, latestVersion in
            if updateAvailable {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Neue Version verfügbar"
                    alert.informativeText = """
                    Lokale Version: \(currentVersion)
                    Verfügbare Version: \(latestVersion)

                    Möchtest du die neue Version jetzt installieren?
                    """
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "Ja, installieren")
                    alert.addButton(withTitle: "Nein")

                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        downloadApp(from: downloadURLString)
                    }
                }
            }
        }
    }

    // MARK: - Versionsprüfung
    private static func checkIfUpdateAvailable(
        versionURLString: String,
        showOutput: Bool,
        completion: @escaping (_ updateAvailable: Bool, _ currentVersion: String, _ latestVersion: String) -> Void
    ) {
        // Add timestamp to bust GitHub cache
        let urlStringWithCacheBust = "\(versionURLString)?t=\(Int(Date().timeIntervalSince1970))"
        
        guard let url = URL(string: urlStringWithCacheBust) else {
            if showOutput {
                showAlert(message: "❌ Ungültige URL für Versionsprüfung.")
            }
            completion(false, "0.0.0", "unbekannt")
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                if showOutput {
                    DispatchQueue.main.async {
                        showAlert(message: "❌ Fehler beim Abrufen der Version: \(error.localizedDescription)")
                    }
                }
                completion(false, "0.0.0", "unbekannt")
                return
            }

            guard let data = data,
                  let latestVersion = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            else {
                if showOutput {
                    DispatchQueue.main.async {
                        showAlert(message: "❌ Konnte Versionsnummer nicht lesen.")
                    }
                }
                completion(false, "0.0.0", "unbekannt")
                return
            }

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            if isVersion(latestVersion, greaterThan: currentVersion) {
                completion(true, currentVersion, latestVersion)
            } else {
                if showOutput {
                    DispatchQueue.main.async {
                        showAlert(message: "Du verwendest bereits die neueste Version: (\(currentVersion))")
                    }
                }
                completion(false, currentVersion, latestVersion)
            }
        }.resume()
    }

    // MARK: - App herunterladen und ersetzen
    private static func downloadApp(from urlString: String) {
        guard let url = URL(string: urlString) else {
            showAlert(message: "❌ Ungültige Download-URL.")
            return
        }

        URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            if let error = error {
                DispatchQueue.main.async {
                    showAlert(message: "❌ Fehler beim Herunterladen: \(error.localizedDescription)")
                }
                return
            }

            guard let tempURL = tempURL else {
                DispatchQueue.main.async {
                    showAlert(message: "❌ Temporäre Datei nicht gefunden.")
                }
                return
            }

            do {
                let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                let destinationURL = downloadsURL.appendingPathComponent("Resolver_Update.dmg")

                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }

                try FileManager.default.moveItem(at: tempURL, to: destinationURL)

                DispatchQueue.main.async {
                    installUpdate(dmgPath: destinationURL.path)
                }

            } catch {
                DispatchQueue.main.async {
                    showAlert(message: "❌ Fehler beim Speichern: \(error.localizedDescription)")
                }
            }
        }.resume()
    }

    // MARK: - Installations-Skript ausführen
    private static func installUpdate(dmgPath: String) {
        let script = """
        #!/bin/bash
        DMG_PATH="\(dmgPath)"
        MOUNT_POINT="/tmp/ResolverUpdateMount"
        APP_NAME="Resolver.app"
        TARGET_APP="/Applications/$APP_NAME"

        # Warten, bis App geschlossen ist (optional, aber sicher)
        sleep 1

        echo "Mounting DMG..."
        hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -quiet

        if [ -d "$MOUNT_POINT/$APP_NAME" ]; then
            echo "Removing old app..."
            rm -rf "$TARGET_APP"
            
            echo "Copying new app..."
            cp -R "$MOUNT_POINT/$APP_NAME" /Applications/
            
            echo "Unmounting..."
            hdiutil detach "$MOUNT_POINT" -quiet
            
            echo "Relaunching..."
            open "$TARGET_APP"
        else
            echo "❌ App in DMG not found!"
            hdiutil detach "$MOUNT_POINT" -quiet
            open "$DMG_PATH" # Fallback: DMG öffnen
        fi
        """

        let scriptPath = "/tmp/resolver_update.sh"
        
        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            
            // Skript ausführbar machen
            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", scriptPath]
            try chmod.run()
            chmod.waitUntilExit()

            // Skript im Hintergrund starten und App beenden
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath]
            try process.run()
            
            NSApp.terminate(nil)
            
        } catch {
            showAlert(message: "❌ Fehler beim Starten des Updates: \(error.localizedDescription)")
        }
    }

    // MARK: - Versionsvergleich
    private static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        let count = max(parts1.count, parts2.count)

        for i in 0..<count {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 != p2 {
                return p1 > p2
            }
        }

        return false
    }

    // MARK: - Alert
    private static func showAlert(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
