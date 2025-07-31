import Foundation
import AppKit

class PyScriptRunner {
    static func run(scriptName: String, showOutput: Bool = false) {
        guard let scriptURL = Bundle.main.url(forResource: scriptName, withExtension: "py") else {
            print("❌ Skript nicht gefunden.")
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
                    showOutputWindow(output)
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

    private static func showOutputWindow(_ output: String) {
        let alert = NSAlert()
        alert.messageText = "Resolver:"
        alert.informativeText = output
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
