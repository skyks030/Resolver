import SwiftUI


struct DropDownMenu: View {
    @State private var showOutput = true
    @State private var enableDownload = true
    
    // VFX Input State
    @State private var showVfxInput = false
    @State private var vfxTrack = ""
    @State private var showMarkerMgmt = false
    
    var body: some View {
        VStack(spacing: 5) {
            if showVfxInput {
                // Input View
                VStack(spacing: 6) {
                    Text("VFX Video Spur")
                        .font(.headline)
                        .scaleEffect(0.9)
                    
                    TextField("#", text: $vfxTrack)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 40)
                        .multilineTextAlignment(.center)
                        // Filter for numbers only
                        .onChange(of: vfxTrack) { newValue in
                            let filtered = newValue.filter { "0123456789".contains($0) }
                            if filtered != newValue {
                                vfxTrack = filtered
                            }
                            // Limit to 1 digit
                            if vfxTrack.count > 1 {
                                vfxTrack = String(vfxTrack.prefix(1))
                            }
                        }
                    
                    HStack(spacing: 15) {
                        Button("Cancel") {
                            withAnimation { showVfxInput = false }
                            vfxTrack = ""
                        }
                        .controlSize(.small)
                        
                        Button("Run") {
                            if !vfxTrack.isEmpty {
                                PyScriptRunner.run(scriptName: "clip-indexing", args: [vfxTrack], showOutput: showOutput, enableDownload: enableDownload)
                                withAnimation { showVfxInput = false }
                                vfxTrack = ""
                            }
                        }
                        .controlSize(.small)
                        .disabled(vfxTrack.isEmpty)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .transition(.opacity)
                
                
            } else if showMarkerMgmt {
                // Marker Management View
                VStack(spacing: 6) {
                    Text("Marker Mgmt")
                        .font(.headline)
                        .scaleEffect(0.9)
                    
                    Text("Del. Resolver Markers?")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    Button("Delete All") {
                        PyScriptRunner.run(scriptName: "clean-markers", showOutput: showOutput, enableDownload: false)
                        withAnimation { showMarkerMgmt = false }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                    
                    Button("Cancel") {
                        withAnimation { showMarkerMgmt = false }
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .transition(.opacity)

            } else {
                // Main Menu View
                HoverButton(title: "VFX") {
                    withAnimation { showVfxInput = true }
                }
                
                HoverButton(title: "Marker Management") {
                    withAnimation { showMarkerMgmt = true }
                }
                
                Divider()
                    .padding(.vertical, 2)
                
                // Footer View
                VStack(alignment: .leading, spacing: 6) {
                    Button("Help") {
                        if let url = URL(string: "https://github.com/skyks030/Resolver") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() }
                        else { NSCursor.pop() }
                    }

                    Button("Check Update") {
                        UpdateChecker.runUpdateCheck(showOutput: true)
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() }
                        else { NSCursor.pop() }
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() }
                        else { NSCursor.pop() }
                    }
                    
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text("v\(version)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            }
        }
        .frame(minWidth: 100, maxWidth: 140)
        .padding(10)
    }
}

