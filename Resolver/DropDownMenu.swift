import SwiftUI

struct DropDownMenu: View {
    @EnvironmentObject var projectManager: ProjectManager
    @Environment(\.openWindow) var openWindow // Requires macOS 13+
    
    @State private var showOutput = true
    @State private var enableDownload = true
    
    // VFX Input State
    enum VfxAction { case index, group }
    @State private var vfxAction: VfxAction = .index
    @State private var showVfxInput = false
    @State private var vfxTrack = ""
    
    @State private var showDeleteMenu = false
    
    // Project State
    @State private var showNewProjectInput = false
    @State private var newProjectName = ""
    @State private var menuWindow: NSWindow?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            
            if showVfxInput {
                // Input View
                VStack(spacing: 6) {
                    Text(vfxAction == .index ? "Index Clips" : "Group Clips")
                        .font(.headline)
                        .scaleEffect(0.9)
                    
                    Text("VFX Track #")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
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

            } else if showDeleteMenu {
                // Delete Menu View
                VStack(spacing: 8) {
                    Text("Delete Tools")
                        .font(.headline)
                        .scaleEffect(0.9)
                        .padding(.bottom, 2)
                    
                    Button("Del. Resolver Markers") {
                        PyScriptRunner.run(scriptName: "clean-markers", showOutput: showOutput, enableDownload: false)
                        withAnimation { showDeleteMenu = false }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    
                    Button("Del. Resolver Groups") {
                        PyScriptRunner.run(scriptName: "clean-groups", showOutput: showOutput, enableDownload: false)
                        withAnimation { showDeleteMenu = false }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)

                    Button("Del. Scene Markers") {
                        PyScriptRunner.run(scriptName: "clean-scene-markers", showOutput: showOutput, enableDownload: false)
                        withAnimation { showDeleteMenu = false }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    
                    Divider()
                    
                    Button("Cancel") {
                        withAnimation { showDeleteMenu = false }
                    }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
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
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        // Close the menu window safely
                        menuWindow?.orderOut(nil)
                    }
                    Divider().padding(.vertical, 4)
                }

                MenuRow(title: "Index VFX-Clips") {
                    vfxAction = .index
                    if let track = projectManager.currentProject?.vfxTrackIndex {
                        vfxTrack = track
                    }
                    withAnimation { showVfxInput = true }
                }
                
                MenuRow(title: "Create Clip-Groups") {
                    vfxAction = .group
                    if let track = projectManager.currentProject?.vfxTrackIndex {
                        vfxTrack = track
                    }
                    withAnimation { showVfxInput = true }
                }

                MenuRow(title: "Delete...") {
                     withAnimation { showDeleteMenu = true }
                }
                
                MenuRow(title: "Add Scene Marker") {
                    PyScriptRunner.run(scriptName: "add-scene-marker", showOutput: false, enableDownload: false) { _ in
                        DispatchQueue.main.async {
                            NSApplication.shared.hide(nil)
                        }
                    }
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
        .background(WindowAccessor(window: $menuWindow))
    }
    
    private func runVfxScript() {
        guard !vfxTrack.isEmpty else { return }
        
        menuWindow?.orderOut(nil)
        
        let trackArg = vfxTrack
        
        // Save track choice if project exists
        if let project = projectManager.currentProject {
            projectManager.updateVfxTrack(projectId: project.id, track: trackArg)
        }
        
        if vfxAction == .group {
            // Grouping: Just run script, show output if any (it logs CSV-like but we just display it if needed)
            // User didn't ask to save group data to Project, so we treat it like a simple script run.
            PyScriptRunner.run(scriptName: "clip-grouping", args: [trackArg], showOutput: true, enableDownload: false)
            withAnimation { showVfxInput = false }
            vfxTrack = ""
            return
        }
        
        // Indexing: Existing Logic
        let shouldShowOutput = projectManager.currentProject == nil
        
        PyScriptRunner.run(scriptName: "clip-indexing", args: [trackArg], showOutput: false, enableDownload: false) { output in
            DispatchQueue.main.async {
                withAnimation { showVfxInput = false }
                vfxTrack = ""
                
                guard let output = output else { return }
                
                // Robust JSON Extraction: Find outer brackets to ignore potential warnings/logs
                var jsonString = output
                if let start = output.firstIndex(of: "["), let end = output.lastIndex(of: "]") {
                     if start <= end {
                         jsonString = String(output[start...end])
                     }
                }
                
                guard let data = jsonString.data(using: .utf8) else { return }
                
                // Try to decode JSON
                do {
                    // Use intermediate struct to handle missing ID from Python
                    let rawClips = try JSONDecoder().decode([IncomingClipData].self, from: data)
                    
                    // Map to ClipData (generates UUID automatically)
                    let clips = rawClips.map { raw in
                        ClipData(
                            vfxName: raw.vfxName,
                            tcIn: raw.tcIn,
                            tcOut: raw.tcOut,
                            sourceTcIn: raw.sourceTcIn,
                            sourceTcOut: raw.sourceTcOut,
                            fileNames: raw.fileNames,
                            reelName: raw.reelName
                        )
                    }
                    
                    if let project = projectManager.currentProject {
                        projectManager.addIndexingRun(to: project.id, clips: clips)
                        print("Saved run with \(clips.count) clips to project")
                    } else {
                        // Legacy handling
                        let header = "VFX-Name,Rec-TC-In,Rec-TC-Out,File-Names\n"
                        let rows = clips.map { "\($0.vfxName),\($0.tcIn),\($0.tcOut),\($0.fileNames)" }.joined(separator: "\n")
                        let csv = header + rows
                        showAlert(csv)
                    }
                } catch {
                    print("JSON Decode Error: \(error)")
                    // ALWAYS show error if something went wrong, as requested by user
                    showAlert("Fehler beim Lesen der Daten:\n\(error.localizedDescription)\n\nRaw Output:\n\(output)")
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

struct IncomingClipData: Decodable {
    let vfxName: String
    let tcIn: String
    let tcOut: String
    let sourceTcIn: String
    let sourceTcOut: String
    let fileNames: String
    let reelName: String
}

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
