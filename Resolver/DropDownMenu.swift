import SwiftUI


struct DropDownMenu: View {
    @State private var showOutput = true
    @State private var enableDownload = true
    
    // VFX Input State
    @State private var showVfxInput = false
    @State private var vfxTrack = ""
    
    var body: some View {
        VStack(spacing: 10) {
            if showVfxInput {
                // Input View
                VStack(spacing: 8) {
                    Text("VFX Video Spur")
                        .font(.headline)
                    
                    TextField("#", text: $vfxTrack)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 50)
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
                    
                    HStack {
                        Button("Cancel") {
                            withAnimation { showVfxInput = false }
                            vfxTrack = ""
                        }
                        
                        Button("Run") {
                            if !vfxTrack.isEmpty {
                                PyScriptRunner.run(scriptName: "clip-grouping", args: [vfxTrack], showOutput: showOutput, enableDownload: enableDownload)
                                withAnimation { showVfxInput = false }
                                vfxTrack = ""
                            }
                        }
                        .disabled(vfxTrack.isEmpty)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding()
                .transition(.opacity)
                
                
            } else {
                // Main Menu View
                HoverButton(title: "VFX") {
                    withAnimation { showVfxInput = true }
                }
                
                Divider()
                
                HStack {
                    // Version Info on the left
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text("v\(version)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Gear Menu on the right
                    Menu {
                        Button("Check for Update") {
                            UpdateChecker.runUpdateCheck(showOutput: true)
                        }
                        Button("Quit") {
                            NSApplication.shared.terminate(nil)
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.body)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.top, 4)
            }
        }
        .frame(minWidth: 100, maxWidth: 150)
        .padding()
    }
}

