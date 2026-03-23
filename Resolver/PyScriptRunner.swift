import Foundation
import AppKit

class PyScriptRunner {
    static func run(scriptName: String, args: [String] = [], showOutput: Bool = false, enableDownload: Bool = false, onProgress: ((String) -> Void)? = nil, completion: ((String?) -> Void)? = nil) {

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
        print("🚀 PyScriptRunner Executing: python3 \(arguments.joined(separator: " "))")
        task.arguments = arguments
        
        // Environment for File-Based Output (to avoid Pipe Deadlocks)
        var env = ProcessInfo.processInfo.environment
        let tempOutputFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        env["RESOLVER_OUTPUT_FILE"] = tempOutputFile.path
        // Specific Fix for macOS GUI Apps knowing where to look for modules if needed
        env["PYTHONUNBUFFERED"] = "1" 
        task.environment = env
        
        let isDebugMode = UserDefaults.standard.bool(forKey: "isDebugMode")
        let needsOutput = showOutput || completion != nil || isDebugMode

        if needsOutput {
            // Create Persistent Log File using CrashManager
            let safeName = scriptName.replacingOccurrences(of: "/", with: "_")
            let logFile = CrashManager.shared.createLogFile(name: safeName)
            
            // Create Pipe
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            // Prepare File Handle
            FileManager.default.createFile(atPath: logFile.path, contents: nil, attributes: nil)
            let logHandle = try? FileHandle(forWritingTo: logFile)
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try task.run()
                    
                    let fileHandle = pipe.fileHandleForReading
                    var fullOutput = Data()
                    
                    // Read loop
                    fileHandle.readabilityHandler = { handle in
                        let data = handle.availableData
                        if !data.isEmpty {
                            fullOutput.append(data)
                            do {
                                try logHandle?.write(contentsOf: data)
                            } catch {
                                print("FileHandle write error safely ignored: \(error)")
                            }
                            
                            // Parse Progress & Log
                            if let str = String(data: data, encoding: .utf8) {
                                let lines = str.components(separatedBy: .newlines)
                                for line in lines {
                                    if line.contains("PROGRESS:") {
                                        DispatchQueue.main.async {
                                            onProgress?(line)
                                        }
                                    } else {
                                        let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !cleanLine.isEmpty {
                                            DispatchQueue.main.async {
                                                ConsoleLogger.shared.log("🐍 [\(scriptName)] \(cleanLine)")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    task.waitUntilExit()
                    
                    // Cleanup
                    fileHandle.readabilityHandler = nil
                    try? logHandle?.close()
                    
                    let outputString = String(data: fullOutput, encoding: .utf8) ?? ""
                    let status = task.terminationStatus
                    
                    DispatchQueue.main.async {
                        // 1. Check JSON Output
                        if FileManager.default.fileExists(atPath: tempOutputFile.path),
                           let fileData = try? Data(contentsOf: tempOutputFile),
                           !fileData.isEmpty,
                           let fileOutput = String(data: fileData, encoding: .utf8) {
                            
                            try? FileManager.default.removeItem(at: tempOutputFile)
                            
                            if showOutput {
                                showOutputWindow(outputString, enableDownload: enableDownload)
                            }
                            completion?(fileOutput)
                            return
                        }
                        
                        // 2. Fallback Output
                        if !outputString.isEmpty {
                             if outputString.contains("MISSING_DEP:") {
                                 handleMissingDependency(outputString) { success in
                                     if success { print("✅ Dependency installed.") }
                                 }
                             }
                             
                             if showOutput {
                                 showOutputWindow(outputString, enableDownload: enableDownload)
                             }
                             completion?(outputString)
                        } else {
                             if status != 0 {
                                 completion?("{\"error\": \"Script failed with Exit Code: \(status)\"}")
                             } else {
                                 completion?("{\"error\": \"No output from Python script\"}")
                             }
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        print("❌ Execution error: \(error.localizedDescription)")
                        completion?("{\"error\": \"Execution failed: \(error.localizedDescription)\"}")
                    }
                }
            }
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try task.run()
                    task.waitUntilExit()
                    DispatchQueue.main.async {
                        completion?("")
                    }
                } catch {
                    DispatchQueue.main.async {
                        print("❌ Execution error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    // Helper to show output window (moved to main thread check inside async block)
    private static func handleMissingDependency(_ output: String, completion: @escaping (Bool) -> Void) {
        // Parse module name (e.g. MISSING_DEP:xlsxwriter)
        guard let range = output.range(of: "MISSING_DEP:"),
              let endRange = output[range.upperBound...].range(of: "\"") else {
            return
        }
        
        let module = String(output[range.upperBound..<endRange.lowerBound])
        
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Missing Python Library"
            alert.informativeText = "Resolver require the '\(module)' library to perform this action. Would you like to install it now?\n\n(Requires internet connection)"
            alert.addButton(withTitle: "Install Now")
            alert.addButton(withTitle: "Cancel")
            
            if alert.runModal() == .alertFirstButtonReturn {
                installModule(module, completion: completion)
            } else {
                completion(false)
            }
        }
    }
    
    private static func installModule(_ module: String, completion: @escaping (Bool) -> Void) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = ["-m", "pip", "install", module]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            DispatchQueue.main.async {
                let success = task.terminationStatus == 0
                let alert = NSAlert()
                alert.messageText = success ? "Installation Successful" : "Installation Failed"
                alert.informativeText = success ?
                    "The '\(module)' library has been installed. Please try your action again." :
                    "Failed to install '\(module)'. Please try running 'pip3 install \(module)' manually in the Terminal."
                alert.addButton(withTitle: "OK")
                alert.runModal()
                completion(success)
            }
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Installation Error"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.runModal()
                completion(false)
            }
        }
    }
    
    private static func showOutputWindow(_ output: String, enableDownload: Bool) {
        let alert = NSAlert()
        alert.messageText = "Resolver Debug Log:"
        
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = output
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        
        scrollView.documentView = textView
        alert.accessoryView = scrollView
        alert.addButton(withTitle: "OK")

        if enableDownload {
            alert.addButton(withTitle: "Herunterladen")
        }
        
        alert.addButton(withTitle: "Copy Log")

        let response = alert.runModal()

        if enableDownload && response == .alertSecondButtonReturn {
            let panel = NSSavePanel()
            panel.title = "Speichere CSV-Ausgabe"
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "output.csv"

            if panel.runModal() == .OK, let url = panel.url {
                try? output.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        
        let copyButtonResponse: NSApplication.ModalResponse = enableDownload ? .alertThirdButtonReturn : .alertSecondButtonReturn
        
        if response == copyButtonResponse {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(output, forType: .string)
        }
    }
}
    
