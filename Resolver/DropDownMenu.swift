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
        VStack(alignment: .leading, spacing: 2) {
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
                    .padding(.vertical, 4)
                
                MenuRow(title: "Help") {
                    if let url = URL(string: "https://github.com/skyks030/Resolver") {
                        NSWorkspace.shared.open(url)
                    }
                }

                MenuRow(title: "Check Update") {
                    UpdateChecker.runUpdateCheck(showOutput: true)
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                MenuRow(title: "Quit", shortcut: "⌘Q") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
                
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("v\(version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8) // Align with text in MenuRow
                        .padding(.top, 2)
                }
            }
        }
        .frame(minWidth: 160, maxWidth: 180) // Slightly wider for padding
        .padding(6) // Reduced outer padding
    }
}

struct MenuRow: View {
    let title: String
    var shortcut: String? = nil
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                if let shortcut = shortcut {
                    Spacer()
                    Text(shortcut)
                        .font(.caption)
                        .foregroundColor(isHovering ? .white.opacity(0.8) : .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color.accentColor : Color.clear)
        )
        .foregroundColor(isHovering ? .white : .primary)
        .onHover { isHovering = $0 }
    }
}

