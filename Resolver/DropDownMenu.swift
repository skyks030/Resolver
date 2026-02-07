import SwiftUI

struct DropDownMenu: View {
    @EnvironmentObject var projectManager: ProjectManager
    @Environment(\.openWindow) var openWindow // Requires macOS 13+
    
    // Global State
    @State private var showOutput = true
    @State private var enableDownload = true
    @State private var menuWindow: NSWindow?
    
    // Navigation State
    enum MenuPage {
        case main
        case vfxIndex
        case vfxGroup
        case newProject
        case delete
        case tools
        case more
    }
    
    @State private var activePage: MenuPage = .main
    
    // VFX Input State (Shared)
    @State private var vfxTrack = ""
    
    // Project Input State
    @State private var newProjectName = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            switch activePage {
            case .main:
                mainMenuView
                    .transition(.move(edge: .leading))
            case .vfxIndex, .vfxGroup:
                vfxInputView
                    .transition(.move(edge: .trailing))
            case .newProject:
                newProjectView
                    .transition(.move(edge: .trailing))
            case .delete:
                deleteMenuView
                    .transition(.move(edge: .trailing))
            case .tools:
                toolsMenuView
                    .transition(.move(edge: .trailing))
            case .more:
                moreMenuView
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(width: 200) // Fixed width for consistent navigation
        .padding(6)
        .background(WindowAccessor(window: $menuWindow))
        .animation(.easeInOut(duration: 0.2), value: activePage)
    }
    
    // MARK: - Views
    
    var mainMenuView: some View {
        VStack(spacing: 2) {
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
                        if project.id == projectManager.currentProject?.id {
                            Label(project.name, systemImage: "checkmark")
                        } else {
                            Text(project.name)
                        }
                    }
                }
                Divider()
                Button("Projekt hinzufügen...") {
                    withAnimation { activePage = .newProject }
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
                .background(Color.black.opacity(0.1))
                .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .padding(.bottom, 4)
            
            if projectManager.currentProject != nil {
                MenuRow(title: "Export Data") {
                    openWindow(id: "export")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    menuWindow?.orderOut(nil)
                }
                Divider().padding(.vertical, 4)
            }
            
            MenuRow(title: "Index VFX-Clips", icon: "chevron.right") {
                if let track = projectManager.currentProject?.vfxTrackIndex {
                    vfxTrack = track
                }
                withAnimation { activePage = .vfxIndex }
            }
            
            MenuRow(title: "Create Clip-Groups", icon: "chevron.right") {
                if let track = projectManager.currentProject?.vfxTrackIndex {
                    vfxTrack = track
                }
                withAnimation { activePage = .vfxGroup }
            }
            
            MenuRow(title: "Add Scene Marker") {
                PyScriptRunner.run(scriptName: "add-scene-marker", showOutput: true, enableDownload: false) { _ in
                    DispatchQueue.main.async { NSApplication.shared.hide(nil) }
                }
            }
            
            Divider().padding(.vertical, 4)
            
            MenuRow(title: "Delete...", icon: "chevron.right") {
                withAnimation { activePage = .delete }
            }
            
            MenuRow(title: "Tools...", icon: "chevron.right") {
                withAnimation { activePage = .tools }
            }
            
            Divider().padding(.vertical, 4)
            
            MenuRow(title: "More...", icon: "chevron.right") {
                withAnimation { activePage = .more }
            }
        }
    }
    
    var vfxInputView: some View {
        VStack(spacing: 8) {
            header(title: activePage == .vfxIndex ? "Index Clips" : "Group Clips")
            
            Text("VFX Track #")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            TextField("#", text: $vfxTrack)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 50)
                .multilineTextAlignment(.center)
                .onChange(of: vfxTrack) { filterNumeric(newValue: $0) }
            
            HStack {
                Button("Run") { runVfxScript() }
                    .buttonStyle(.borderedProminent)
                    .disabled(vfxTrack.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
    
    var newProjectView: some View {
        VStack(spacing: 8) {
            header(title: "New Project")
            
            TextField("Name", text: $newProjectName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Button("Create") {
                if !newProjectName.isEmpty {
                    projectManager.addProject(name: newProjectName)
                    withAnimation { activePage = .main }
                    newProjectName = ""
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(newProjectName.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
    
    var deleteMenuView: some View {
        VStack(spacing: 4) {
            header(title: "Delete Tools")
            
            MenuRow(title: "Del. Resolver Markers", color: .red) {
                PyScriptRunner.run(scriptName: "clean-markers", showOutput: showOutput)
                withAnimation { activePage = .main }
            }
            
            MenuRow(title: "Del. Resolver Groups", color: .red) {
                PyScriptRunner.run(scriptName: "clean-groups", showOutput: showOutput)
                withAnimation { activePage = .main }
            }
            
            MenuRow(title: "Del. Scene Markers", color: .red) {
                PyScriptRunner.run(scriptName: "clean-scene-markers", showOutput: showOutput)
                withAnimation { activePage = .main }
            }
        }
    }
    
    var toolsMenuView: some View {
        VStack(spacing: 4) {
            header(title: "Tools")
            
            MenuRow(title: "Marker Manager") {
                openWindow(id: "marker-tool")
                NSApplication.shared.activate(ignoringOtherApps: true)
                menuWindow?.orderOut(nil)
            }
        }
    }
    
    var moreMenuView: some View {
        VStack(spacing: 4) {
            header(title: "More Options")
            
            MenuRow(title: "Help") {
                if let url = URL(string: "https://github.com/skyks030/Resolver") {
                    NSWorkspace.shared.open(url)
                }
            }
            
            MenuRow(title: "Check Update") {
                UpdateChecker.runUpdateCheck(showOutput: true)
            }
            
            Divider().padding(.vertical, 4)
            
            MenuRow(title: "Quit", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
            
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("v\(version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
    
    // MARK: - Helpers
    
    func header(title: String) -> some View {
        HStack {
            Button(action: {
                withAnimation { activePage = .main }
            }) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.bold)) // Bolder, larger icon
                    .frame(width: 36, height: 32, alignment: .leading) // Large Hit Area
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Spacer()
            Text(title).font(.headline)
            Spacer()
            
            // Empty view to balance layout
            Image(systemName: "chevron.left")
                .font(.body.weight(.bold))
                .frame(width: 36, height: 32)
                .opacity(0)
        }
        .padding(.bottom, 8)
    }
    
    func filterNumeric(newValue: String) {
        let filtered = newValue.filter { "0123456789".contains($0) }
        if filtered != newValue { vfxTrack = filtered }
        if vfxTrack.count > 1 { vfxTrack = String(vfxTrack.prefix(1)) }
    }
    
    private func runVfxScript() {
        guard !vfxTrack.isEmpty else { return }
        
        let trackArg = vfxTrack
        menuWindow?.orderOut(nil) // Hide window immediately
        
        if let project = projectManager.currentProject {
            projectManager.updateVfxTrack(projectId: project.id, track: trackArg)
        }
        
        // Grouping
        if activePage == .vfxGroup {
            PyScriptRunner.run(scriptName: "clip-grouping", args: [trackArg], showOutput: true)
            withAnimation { activePage = .main }
            vfxTrack = ""
            return
        }
        
        // Indexing
        PyScriptRunner.run(scriptName: "clip-indexing", args: [trackArg], showOutput: false) { output in
            DispatchQueue.main.async {
                withAnimation { activePage = .main }
                vfxTrack = ""
                handleIndexingOutput(output)
            }
        }
    }
    
    private func handleIndexingOutput(_ output: String?) {
        guard let output = output else { return }
        
        var jsonString = output
        if let start = output.firstIndex(of: "["), let end = output.lastIndex(of: "]") {
             if start <= end { jsonString = String(output[start...end]) }
        }
        
        guard let data = jsonString.data(using: .utf8) else { return }
        
        do {
            let rawClips = try JSONDecoder().decode([IncomingClipData].self, from: data)
            let clips = rawClips.map { raw in
                ClipData(vfxName: raw.vfxName, tcIn: raw.tcIn, tcOut: raw.tcOut, sourceTcIn: raw.sourceTcIn, sourceTcOut: raw.sourceTcOut, fileNames: raw.fileNames, reelName: raw.reelName)
            }
            
            if let project = projectManager.currentProject {
                projectManager.addIndexingRun(to: project.id, clips: clips)
            } else {
                showAlert("CSV Output:\n" + clips.map { $0.vfxName }.joined(separator: ","))
            }
        } catch {
            showAlert("Error parsing data: \(error.localizedDescription)")
        }
    }
    
    private func showAlert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Resolver"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Components

struct MenuRow: View {
    let title: String
    var icon: String? = nil
    var shortcut: String? = nil
    var color: Color = .primary
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundColor(isHovering ? .white : color)
                
                Spacer()
                
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(isHovering ? .white.opacity(0.8) : .secondary)
                }
                
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundColor(isHovering ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color.accentColor : Color.clear)
        )
        .onHover { isHovering = $0 }
    }
}

// Re-declare Structs used
struct IncomingClipData: Decodable {
    let vfxName, tcIn, tcOut, sourceTcIn, sourceTcOut, fileNames, reelName: String
}

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { self.window = view.window }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
