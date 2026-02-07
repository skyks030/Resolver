import Foundation
import AppKit

class PyScriptRunner {
    static func run(scriptName: String, args: [String] = [], showOutput: Bool = false, enableDownload: Bool = false, completion: ((String?) -> Void)? = nil) {

        // Dev Mode: Check if local file exists
        let devScriptPath = "/Users/skymuller/Git/Resolver/Resolver/Scripts/\(scriptName).py"
        let scriptURL: URL
        
        if FileManager.default.fileExists(atPath: devScriptPath) {
            print("🔧 Dev-Mode: Nutze lokales Skript \(devScriptPath)")
            scriptURL = URL(fileURLWithPath: devScriptPath)
        } else {
            // Bundle Lookup Strategy
            var foundURL: URL?
            let fileName = URL(fileURLWithPath: scriptName).lastPathComponent
            let dirName = URL(fileURLWithPath: scriptName).deletingLastPathComponent().path
            let effectiveDir = dirName == "." ? "" : dirName

            // 1. Try "Scripts/<path>/<name>.py" (Folder Reference style)
            if let resources = Bundle.main.resourceURL {
                let fullPath = resources.appendingPathComponent("Scripts").appendingPathComponent(scriptName + ".py")
                if FileManager.default.fileExists(atPath: fullPath.path) {
                    foundURL = fullPath
                }
            }
            
            // 2. Try standard directory search in "Scripts"
            if foundURL == nil {
                let subdir = effectiveDir.isEmpty ? "Scripts" : "Scripts/\(effectiveDir)"
                foundURL = Bundle.main.url(forResource: fileName, withExtension: "py", subdirectory: subdir)
            }

            // 3. Try standard directory search (root)
            if foundURL == nil && !effectiveDir.isEmpty {
                foundURL = Bundle.main.url(forResource: fileName, withExtension: "py", subdirectory: effectiveDir)
            }
            
            // 4. Try flattened / fallback
            if foundURL == nil {
                 foundURL = Bundle.main.url(forResource: fileName, withExtension: "py")
            }

            if let url = foundURL {
                scriptURL = url
            } else {
                let msg = "Script not found in Bundle: \(scriptName)"
                print("❌ \(msg)")
                completion?("{\"error\": \"\(msg)\"}")
                return
            }
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        var arguments = [scriptURL.path]
        arguments.append(contentsOf: args)
        task.arguments = arguments
        
        let needsOutput = showOutput || completion != nil

        if needsOutput {
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    if showOutput {
                        showOutputWindow(output, enableDownload: enableDownload)
                    }
                    completion?(output)
                } else {
                    completion?("{\"error\": \"No output from Python script (Exit Code: \(task.terminationStatus))\"}")
                }
            } catch {
                print("❌ Fehler: \(error.localizedDescription)")
                completion?("{\"error\": \"Execution failed: \(error.localizedDescription)\"}")
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
    
