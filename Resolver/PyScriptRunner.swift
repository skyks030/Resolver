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
        
        // Environment for File-Based Output (to avoid Pipe Deadlocks)
        var env = ProcessInfo.processInfo.environment
        let tempOutputFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        env["RESOLVER_OUTPUT_FILE"] = tempOutputFile.path
        // Specific Fix for macOS GUI Apps knowing where to look for modules if needed
        env["PYTHONUNBUFFERED"] = "1" 
        task.environment = env
        
        let isDebugMode = UserDefaults.standard.bool(forKey: "isDebugMode")
        let needsOutput = showOutput || isDebugMode || completion != nil

        if needsOutput {
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                // 1. Priority: Check File Output
                if FileManager.default.fileExists(atPath: tempOutputFile.path),
                   let fileData = try? Data(contentsOf: tempOutputFile),
                   !fileData.isEmpty,
                   let fileOutput = String(data: fileData, encoding: .utf8) {
                    
                    // Cleanup
                    try? FileManager.default.removeItem(at: tempOutputFile)
                    
                    if showOutput || isDebugMode {
                        showOutputWindow(fileOutput, enableDownload: enableDownload)
                    }
                    completion?(fileOutput)
                    return
                }
                
                // 2. Fallback: Pipe Output (Legacy or Error)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    if showOutput || isDebugMode {
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
        alert.messageText = "Resolver Debug Log:"
        alert.informativeText = output
        alert.addButton(withTitle: "OK")

        if enableDownload {
            alert.addButton(withTitle: "Herunterladen")
        }
        
        // Always add Copy button
        alert.addButton(withTitle: "Copy Log")

        let response = alert.runModal()

        // Handle Download
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
        
        // Handle Copy (3rd button if download enabled, 2nd otherwise)
        let copyButtonResponse: NSApplication.ModalResponse = enableDownload ? .alertThirdButtonReturn : .alertSecondButtonReturn
        
        if response == copyButtonResponse {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(output, forType: .string)
            // Optional: Show a small feedback tone or temporary alert? Standard macOS copy is usually silent or just works.
            // We could loop and show message "Copied", but that blocks logic.
        }
    }
}
    
