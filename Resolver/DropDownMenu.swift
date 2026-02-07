import SwiftUI

struct DropDownMenu: View {
    @EnvironmentObject var projectManager: ProjectManager
    @Environment(\.openWindow) var openWindow // Requires macOS 13+
    
    @State private var showOutput = true
    @State private var enableDownload = true
    
    // VFX Input State
    @State private var showVfxInput = false
    @State private var vfxTrack = ""
    @State private var showMarkerMgmt = false
    @State private var showGroupMgmt = false
    
    // Project State
    @State private var showNewProjectInput = false
    @State private var newProjectName = ""
    
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
                        .onChange(of: vfxTrack) { newValue in
                            let filtered = newValue.filter { "0123456789".contains($0) }
                            if filtered != newValue { vfxTrack = filtered }
                            if vfxTrack.count > 1 { vfxTrack = String(vfxTrack.prefix(1)) }
                        }
                    
                    HStack(spacing: 15) {
                        Button("Cancel") {
                            withAnimation { showVfxInput = false }
                            vfxTrack = ""
                        }
                        .controlSize(.small)
                        
                        Button("Run") {
                            runVfxScript()
                        }
                        .controlSize(.small)
                        .disabled(vfxTrack.isEmpty)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .transition(.opacity)
                
            } else if showNewProjectInput {
                // New Project Input
                VStack(spacing: 6) {
                    Text("Neues Projekt")
                        .font(.headline)
                        .scaleEffect(0.9)
                    
                    TextField("Name", text: $newProjectName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 120)
                        .multilineTextAlignment(.center)
                    
                    HStack(spacing: 15) {
                        Button("Cancel") {
                            withAnimation { showNewProjectInput = false }
                            newProjectName = ""
                        }
                        .controlSize(.small)
                        
                        Button("Create") {
                            if !newProjectName.isEmpty {
                                projectManager.addProject(name: newProjectName)
                                withAnimation { showNewProjectInput = false }
                                newProjectName = ""
                            }
                        }
                        .controlSize(.small)
                        .disabled(newProjectName.isEmpty)
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
                
                // Project Selector
                Menu {
                    Button("Kein Projekt") {
                        projectManager.selectProject(nil)
                    }
                    Divider()
                    ForEach(projectManager.projects) { project in
                        Button(action: {
                            projectManager.selectProject(project.id)
                        }) {
                            HStack {
                                Text(project.name)
                                if project.id == projectManager.currentProject?.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Projekt hinzufügen...") {
                        withAnimation { showNewProjectInput = true }
                    }
                } label: {
                    HStack {
                        Text(projectManager.currentProject?.name ?? "Kein Projekt")
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.1)) // Slight background for dropdown
                    .cornerRadius(4)
                }
                .menuStyle(.borderlessButton)
                .padding(.bottom, 2)
                
                if projectManager.currentProject != nil {
                    MenuRow(title: "Export Data") {
                        openWindow(id: "export")
                    }
                    Divider().padding(.vertical, 4)
                }

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
    
    private func runVfxScript() {
        guard !vfxTrack.isEmpty else { return }
        
        let trackArg = vfxTrack
        // If project selected, we do NOT show global alert (we consume it).
        // If NO project selected, we show alert (legacy).
        let shouldShowOutput = projectManager.currentProject == nil
        
        PyScriptRunner.run(scriptName: "clip-indexing", args: [trackArg], showOutput: false, enableDownload: false) { output in
            // Handle output on Main Thread
            DispatchQueue.main.async {
                withAnimation { showVfxInput = false }
                vfxTrack = ""
                
                guard let output = output, let data = output.data(using: .utf8) else { return }
                
                // Try to decode JSON
                if let clips = try? JSONDecoder().decode([ClipData].self, from: data) {
                    if let project = projectManager.currentProject {
                        // Add to project
                        projectManager.addClips(to: project.id, clips: clips)
                        // Maybe play a sound or show a small checkmark?
                        print("Saved \(clips.count) clips to project")
                    } else {
                        // Legacy handling: Convert to CSV and show Alert
                        let header = "VFX-Name,Rec-TC-In,Rec-TC-Out,File-Names\n"
                        let rows = clips.map { "\($0.vfxName),\($0.tcIn),\($0.tcOut),\($0.fileNames)" }.joined(separator: "\n")
                        let csv = header + rows
                        showAlert(csv)
                    }
                } else {
                    // Fallback if not valid JSON (e.g. error message)
                    if shouldShowOutput {
                        showAlert(output)
                    }
                }
            }
        }
    }
    
    private func showAlert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Resolver Output"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Download CSV")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            let panel = NSSavePanel()
            panel.title = "Save CSV"
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "output.csv"
            if panel.runModal() == .OK, let url = panel.url {
                 try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
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

