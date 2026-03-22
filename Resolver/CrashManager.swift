import Foundation
import AppKit
import SwiftUI

class CrashManager: ObservableObject {
    static let shared = CrashManager()
    
    private let logDirectory: URL
    private let lockFileURL: URL
    
    @Published var lastCrashLog: String? = nil
    @Published var hasCrashReport: Bool = false
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let resolverDir = appSupport.appendingPathComponent("Resolver")
        self.logDirectory = resolverDir.appendingPathComponent("Logs")
        self.lockFileURL = resolverDir.appendingPathComponent("app.lock")
        
        // Create Logs dir if needed
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }
    
    func checkForCrash() {
        if FileManager.default.fileExists(atPath: lockFileURL.path) {
            print("🚨 App was not closed properly. Checking for logs.")
            // Find most recent log
            if let lastLog = getMostRecentLog() {
                self.lastCrashLog = lastLog
                self.hasCrashReport = true
            }
            // Cleanup lock
            try? FileManager.default.removeItem(at: lockFileURL)
        }
    }
    
    func startSession() {
        // Create lock file
        FileManager.default.createFile(atPath: lockFileURL.path, contents: Data(), attributes: nil)
    }
    
    func endSession() {
        // Remove lock file (clean exit)
        try? FileManager.default.removeItem(at: lockFileURL)
    }
    
    func createLogFile(name: String) -> URL {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = "\(timestamp)_\(name).log"
        return logDirectory.appendingPathComponent(filename)
    }
    
    private func getMostRecentLog() -> String? {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            
            if let mostRecent = files.filter({ $0.pathExtension == "log" }).sorted(by: {
                let date1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }).first {
                return try String(contentsOf: mostRecent, encoding: .utf8)
            }
        } catch {
            print("Error reading logs: \(error)")
        }
        return nil
    }
}

struct CrashReportView: View {
    @ObservedObject var crashManager = CrashManager.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.largeTitle)
                VStack(alignment: .leading) {
                    Text("Resolver closed unexpectedly")
                        .font(.headline)
                    Text("Here is the log from the last session:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.top)
            
            if let log = crashManager.lastCrashLog {
                ScrollView {
                    Text(log)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)
                .border(Color.secondary.opacity(0.2), width: 1)
            } else {
                Text("No log file found.")
                    .font(.caption)
            }
            
            HStack {
                Button("Copy to Clipboard") {
                    if let log = crashManager.lastCrashLog {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(log, forType: .string)
                    }
                }
                Spacer()
                Button("Close") {
                    crashManager.hasCrashReport = false
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom)
        }
        .padding()
        .frame(width: 600, height: 450)
    }
}
