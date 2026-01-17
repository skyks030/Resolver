import Foundation
import AppKit

class PyScriptRunner {
    static func run(scriptName: String, showOutput: Bool = false, enableDownload: Bool = false) {

        // Dev Mode: Check if local file exists
        let devScriptPath = "/Users/skymuller/Git/Resolver/Resolver-mac/Resolver/Scripts/\(scriptName).py"
        let scriptURL: URL
        
        if FileManager.default.fileExists(atPath: devScriptPath) {
            print("🔧 Dev-Mode: Nutze lokales Skript \(devScriptPath)")
            scriptURL = URL(fileURLWithPath: devScriptPath)
        } else if let bundleURL = Bundle.main.url(forResource: scriptName, withExtension: "py") {
            scriptURL = bundleURL
        } else {
            print("❌ Skript nicht gefunden: \(scriptName)")
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = [scriptURL.path]

        if showOutput {
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    showOutputWindow(output, enableDownload: enableDownload)
                }
            } catch {
                print("❌ Fehler: \(error.localizedDescription)")
            }
        } else {
            do { try task.run() } catch {
                print("❌ Fehler: \(error.localizedDescription)")
            }
        }
    }
    
    private static func showOutputWindow(_ output: String, enableDownload: Bool) {
        let alert = NSAlert()
        alert.messageText = "Resolver:"
        alert.informativeText = output
        alert.addButton(withTitle: "OK")

        if enableDownload {
            alert.addButton(withTitle: "Herunterladen")
        }

        let response = alert.runModal()

        if enableDownload && response == .alertSecondButtonReturn {
            let panel = NSSavePanel()
            panel.title = "Speichere CSV-Ausgabe"
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "output.csv"

            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try output.write(to: url, atomically: true, encoding: .utf8)
                    print("✅ CSV gespeichert: \(url.path)")
                } catch {
                    print("❌ Fehler beim Speichern der Datei: \(error.localizedDescription)")
                }
            }
        }
    }
}
    
