import SwiftUI

struct DoubleClipIssue: Identifiable, Codable {
    var id = UUID()
    let type: String
    let name: String
    let startFrame: Int
    let tc: Int // Redundant but consistent with script? Script sends 'tc' as frame or generic. keeping startFrame is safer.
    
    enum CodingKeys: String, CodingKey {
        case type, name, startFrame, tc
    }
}

struct DoubleClipsView: View {
    @State private var trackIndex: Int = 1
    @State private var issues: [DoubleClipIssue] = []
    @State private var isScanning = false
    @State private var statusMessage: String = "Ready to scan."
    
    // Alert State
    @State private var showErrorAlert = false
    @State private var alertMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // ... (Header) ...
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(.accentColor)
                Text("Double Clip Finder")
                    .font(.headline)
                
                Spacer()
                
                HStack {
                    Text("Track:")
                    TextField("1", value: $trackIndex, formatter: NumberFormatter())
                        .frame(width: 40)
                        .textFieldStyle(.roundedBorder)
                    
                    Button(action: scanTracks) {
                        Label("Scan", systemImage: "magnifyingglass")
                    }
                    .disabled(isScanning)
                }
            }
            .padding()
            .liquidGlassBar()

            Divider()
            
            // List
            if isScanning {
                Spacer()
                ProgressView("Scanning Timeline...")
                Spacer()
            } else if issues.isEmpty {
                Spacer()
                Text(statusMessage)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(issues) { issue in
                    HStack {
                        Image(systemName: issue.type == "Solid Color" ? "paintpalette.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(issue.type == "Solid Color" ? .blue : .orange)
                        
                        VStack(alignment: .leading) {
                            Text(issue.type)
                                .font(.headline)
                            Text(issue.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("Frame: \(issue.startFrame)")
                            .font(.monospacedDigit(.caption)())
                            .foregroundColor(.secondary)
                        
                        Button("Jump") {
                            jumpTo(frame: issue.startFrame)
                        }
                        .liquidGlassButton(prominent: true)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                Text("Found \(issues.count) issues.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Clear Results") {
                    issues = []
                    statusMessage = "Ready to scan."
                }
                .disabled(issues.isEmpty)
                
                // Status Text
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .liquidGlassBar()
        }
        .frame(minWidth: 400, minHeight: 300)
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Actions
    
    private func scanTracks() {
        isScanning = true
        issues = []
        statusMessage = "Scanning..."
        
        let payload: [String: Any] = ["trackIndex": trackIndex]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("resolver_scan_request.json")
            try data.write(to: tmpURL)
            
            PyScriptRunner.run(scriptName: "Resolve/Tools/find_double_clips", args: [tmpURL.path], showOutput: false, completion: { output in
                DispatchQueue.main.async {
                    isScanning = false
                    
                    if let output = output {
                        if output.contains("\"error\":") {
                             statusMessage = "Script Error"
                             alertMessage = "Scan Error: \(output)"
                             showErrorAlert = true
                        } else {
                            parseOutput(output)
                        }
                    } else {
                        statusMessage = "Script failed to run (No Output)."
                        alertMessage = "Script produced no output."
                        showErrorAlert = true
                    }
                }
            })
        } catch {
            isScanning = false
            statusMessage = "Failed to create payload."
            alertMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func parseOutput(_ output: String) {
        // Output might contain debug info. Look for JSON block.
        // Assuming PyScriptRunner output logic...
        // Actually, PyScriptRunner output is just the stdout captured.
        // The script prints one JSON line at the end usually.
        // We should try to find the JSON line.
        
        // Simple strategy: Try to parse entire string, if fail, split lines.
        if let data = output.data(using: .utf8),
           let response = try? JSONDecoder().decode(ScanResponse.self, from: data) {
            self.issues = response.issues
            self.statusMessage = self.issues.isEmpty ? "No duplicate clips or solid colors found." : "Scan complete."
        } else {
            // Debug: print(output)
            statusMessage = "Failed to parse script output."
        }
    }

    private func jumpTo(frame: Int) {
        print("Jump requested to frame: \(frame)")
        let payload: [String: Any] = ["frame": frame]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("resolver_jump_request.json")
            try data.write(to: tmpURL)
            
            PyScriptRunner.run(scriptName: "Resolve/Tools/navigate_to_frame", args: [tmpURL.path], showOutput: false, completion: { output in
                if let output = output, output.contains("\"error\":") {
                    DispatchQueue.main.async {
                        self.statusMessage = "Jump Failed"
                        self.alertMessage = "Jump Error: \(output)"
                        self.showErrorAlert = true
                    }
                }
            })
        } catch {
             statusMessage = "Jump Request Failed"
             alertMessage = error.localizedDescription
             showErrorAlert = true
        }
    }
}

struct ScanResponse: Codable {
    let issues: [DoubleClipIssue]
}
