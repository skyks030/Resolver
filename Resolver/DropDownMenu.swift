import SwiftUI


struct DropDownMenu: View {
    @State private var showOutput = true
    @State private var enableDownload = true
    
    // VFX Input State
    @State private var showVfxInput = false
    @State private var vfxTrack = ""
    @State private var showMarkerMgmt = false
    @State private var showGroupMgmt = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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

            } else if showGroupMgmt {
                // Group Management View
                VStack(spacing: 6) {
                    Text("Group Mgmt")
                        .font(.headline)
                        .scaleEffect(0.9)
                    
                    Text("Del. Resolver Groups?")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    Button("Delete All") {
                        PyScriptRunner.run(scriptName: "clean-groups", showOutput: showOutput, enableDownload: false)
                        withAnimation { showGroupMgmt = false }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                    
                    Button("Cancel") {
                        withAnimation { showGroupMgmt = false }
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .transition(.opacity)

            } else {
                // Main Menu View
                MenuRow(title: "VFX") {
                    withAnimation { showVfxInput = true }
                }

                MenuRow(title: "Marker Management") {
                    withAnimation { showMarkerMgmt = true }
                }
                
                MenuRow(title: "Group Management") {
                    withAnimation { showGroupMgmt = true }
                }
                
                Divider()
                    .padding(.vertical, 2)
                
                MenuRow(title: "Help") {
                    if let url = URL(string: "https://github.com/skyks030/Resolver") {
                        NSWorkspace.shared.open(url)
                    }
                }


                MenuRow(title: "Check Update") {
                    UpdateChecker.runUpdateCheck(showOutput: true)
                }
                
                Divider()
                    .padding(.vertical, 2)
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack {
                        Text("Quit")
                        Spacer()
                        Text("⌘Q")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
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
        }
        .frame(minWidth: 140, maxWidth: 160) // Slightly wider for shortcuts/text
        .padding(10)
    }
}

struct MenuRow: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
    }
}

