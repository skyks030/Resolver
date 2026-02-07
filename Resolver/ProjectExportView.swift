import SwiftUI

struct ProjectExportView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var selection: Set<UUID> = []
    @State private var selectedRunId: UUID?
    @State private var showDeleteConfirmation = false
    @State private var isEditing = false
    @State private var showRenameAlert = false
    @State private var showDeleteProjectConfirmation = false
    @State private var editingProjectName = ""
    
    // Column Toggles
    @State private var showVfxName = true
    @State private var showTcIn = true
    @State private var showTcOut = true
    @State private var showSourceTcIn = true
    @State private var showSourceTcOut = true
    @State private var showFileNames = true
    @State private var showReelName = true

    var body: some View {

        VStack(spacing: 0) {
            if let project = projectManager.currentProject {
                headerView(project: project)
                
                Divider()
                
                toolbarView(project: project)
                
                // Table
                if let runBinding = currentRunBinding {
                    ScrollView([.vertical, .horizontal]) {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                            headerRow
                            
                            Divider()
                            
                            dataRows(runBinding: runBinding)
                        }
                        .padding(.vertical)
                    }
                } else {
                    Spacer()
                    Text("Select an indexing run to view clips.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
            } else {
                Spacer()
                Text("No Project Selected")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .alert("Rename Project", isPresented: $showRenameAlert) {
            TextField("New Name", text: $editingProjectName)
            Button("Rename") {
                if let project = projectManager.currentProject {
                    projectManager.renameProject(id: project.id, newName: editingProjectName)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Delete Project?", isPresented: $showDeleteProjectConfirmation) {
            Button("Delete", role: .destructive) {
                if let project = projectManager.currentProject {
                    projectManager.deleteProject(project.id)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this project and all its data? This cannot be undone.")
        }
        .onAppear {
            if let project = projectManager.currentProject, let lastRun = project.runs.last {
                selectedRunId = lastRun.id
            }
        }
        .onChange(of: projectManager.currentProject?.id) { _ in
            if let project = projectManager.currentProject, let lastRun = project.runs.last {
                selectedRunId = lastRun.id
            }
        }
        .onChange(of: projectManager.currentProject?.runs.count) { _ in
            if let project = projectManager.currentProject, let lastRun = project.runs.last {
                selectedRunId = lastRun.id
            }
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func headerView(project: Project) -> some View {
        HStack {
            VStack(alignment: .leading) {
                // Project Selector
                Menu {
                    Button("Rename Project...") {
                        if let p = projectManager.currentProject {
                            editingProjectName = p.name
                            showRenameAlert = true
                        }
                    }
                    
                    Button("Delete Project...", role: .destructive) {
                        showDeleteProjectConfirmation = true
                    }
                    
                    Divider()
                    
                    ForEach(projectManager.projects) { p in
                        Button(action: {
                            projectManager.selectProject(p.id)
                        }) {
                            if p.id == project.id {
                                Label(p.name, systemImage: "checkmark")
                            } else {
                                Text(p.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(project.name)
                            .font(.title)
                            .bold()
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Summary
                if let run = getSelectedRun(project: project) {
                    HStack(spacing: 12) {
                        Label("\(countScenes(in: run)) Scenes", systemImage: "clapperboard")
                        Label("\(run.clips.count) Clips", systemImage: "film")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                }
                
                if !project.runs.isEmpty {
                    Picker("Run:", selection: $selectedRunId) {
                        ForEach(project.runs.sorted(by: { $0.date > $1.date })) { run in
                            Text("\(Formatter.date.string(from: run.date)) (\(run.clips.count) Clips)")
                                .tag(run.id as UUID?)
                        }
                    }
                    .frame(width: 250)
                } else {
                    Text("No indexing runs yet.")
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if selectedRunId != nil {
                Button(isEditing ? "Save Changes" : "Edit Mode") {
                    if isEditing {
                        projectManager.save()
                    }
                    isEditing.toggle()
                }
                .buttonStyle(.borderedProminent)
                .tint(isEditing ? .green : .accentColor)
                
                Button("Delete Run") {
                    showDeleteConfirmation = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .alert("Delete Indexing Run?", isPresented: $showDeleteConfirmation) {
                    Button("Delete", role: .destructive) {
                        deleteCurrentRun(project: project)
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This action cannot be undone.")
                }
                
                Divider().padding(.horizontal, 8)

                Button {
                    PyScriptRunner.run(scriptName: "Resolve/Tools/clean_all_resolver_markers", showOutput: false)
                } label: {
                    Label("Clean Markers", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Delete ALL Resolver Markers (Scene & VFX) from the Timeline")
                
                Divider().padding(.horizontal, 8)
                
                // Marker Toggles
                HStack(spacing: 12) {
                    // Scene Markers
                    VStack(spacing: 2) {
                        Text("Scenes").font(.caption2).foregroundColor(.secondary)
                        ControlGroup {
                            Button { performBatchOp(type: "scene", action: "create", project: project) } label: { Image(systemName: "eye") }
                                .help("Show Scene Markers")
                            Button { performBatchOp(type: "scene", action: "delete", project: project) } label: { Image(systemName: "eye.slash") }
                                .help("Hide Scene Markers")

                        }
                        .controlGroupStyle(.navigation)
                    }
                    
                    // VFX Markers
                    VStack(spacing: 2) {
                        Text("VFX").font(.caption2).foregroundColor(.secondary)
                        ControlGroup {
                            Button { performBatchOp(type: "vfx", action: "create", project: project) } label: { Image(systemName: "eye") }
                                .help("Show VFX Markers")
                            Button { performBatchOp(type: "vfx", action: "delete", project: project) } label: { Image(systemName: "eye.slash") }
                                .help("Hide VFX Markers")

                        }
                        .controlGroupStyle(.navigation)
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func toolbarView(project: Project) -> some View {
        HStack {
            Toggle("VFX Name", isOn: $showVfxName)
            Toggle("TC In", isOn: $showTcIn)
            Toggle("TC Out", isOn: $showTcOut)
            Toggle("Source In", isOn: $showSourceTcIn)
            Toggle("Source Out", isOn: $showSourceTcOut)
            Toggle("Files", isOn: $showFileNames)
            Toggle("Reel", isOn: $showReelName)
            
            Spacer()
            
            Button("Export CSV") {
                if let run = getSelectedRun(project: project) {
                    exportCSV(project: project, run: run)
                }
            }
            .disabled(selectedRunId == nil)
        }
        .padding()
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var headerRow: some View {
        GridRow {
            if showVfxName { Text("VFX Name").bold() }
            if showTcIn { Text("TC In").bold() }
            if showTcOut { Text("TC Out").bold() }
            if showSourceTcIn { Text("Source In").bold() }
            if showSourceTcOut { Text("Source Out").bold() }
            if showReelName { Text("Reel Name").bold() }
            if showFileNames { Text("File Names").bold() }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func dataRows(runBinding: Binding<IndexingRun>) -> some View {
        ForEach(runBinding.clips) { $clip in
            GridRow {
                if showVfxName {
                    if isEditing { TextField("", text: $clip.vfxName).textFieldStyle(.plain) }
                    else { Text(clip.vfxName).lineLimit(1).fixedSize() }
                }
                if showTcIn {
                    if isEditing { TextField("", text: $clip.tcIn).textFieldStyle(.plain) }
                    else { Text(clip.tcIn).lineLimit(1).fixedSize() }
                }
                if showTcOut {
                    if isEditing { TextField("", text: $clip.tcOut).textFieldStyle(.plain) }
                    else { Text(clip.tcOut).lineLimit(1).fixedSize() }
                }
                if showSourceTcIn {
                    if isEditing { TextField("", text: $clip.sourceTcIn).textFieldStyle(.plain) }
                    else { Text(clip.sourceTcIn).lineLimit(1).fixedSize() }
                }
                if showSourceTcOut {
                    if isEditing { TextField("", text: $clip.sourceTcOut).textFieldStyle(.plain) }
                    else { Text(clip.sourceTcOut).lineLimit(1).fixedSize() }
                }
                if showReelName {
                    if isEditing { TextField("", text: $clip.reelName).textFieldStyle(.plain) }
                    else { Text(clip.reelName).lineLimit(1).fixedSize() }
                }
                if showFileNames {
                    if isEditing { TextField("", text: $clip.fileNames).textFieldStyle(.plain) }
                    else { Text(clip.fileNames).lineLimit(1).fixedSize() }
                }
            }
            .padding(.horizontal)
            
            Divider()
        }
    }

    
    // Helpers
    private var currentRunBinding: Binding<IndexingRun>? {
        guard let projectId = projectManager.currentProject?.id,
              let runId = selectedRunId,
              let pIndex = projectManager.projects.firstIndex(where: { $0.id == projectId }),
              let rIndex = projectManager.projects[pIndex].runs.firstIndex(where: { $0.id == runId })
        else { return nil }
        
        return $projectManager.projects[pIndex].runs[rIndex]
    }
    
    private func countScenes(in run: IndexingRun) -> Int {
        let prefixes = run.clips.compactMap { clip -> String? in
            let parts = clip.vfxName.split(separator: "_")
            return parts.first.map(String.init)
        }
        return Set(prefixes).count
    }

    private func getSelectedRun(project: Project) -> IndexingRun? {
        guard let id = selectedRunId else { return nil }
        return project.runs.first(where: { $0.id == id })
    }
    
    private func deleteCurrentRun(project: Project) {
        guard let runId = selectedRunId else { return }
        projectManager.deleteIndexingRun(projectId: project.id, runId: runId)
        // Reset selection if needed
        if let newLast = projectManager.currentProject?.runs.last {
            selectedRunId = newLast.id
        } else {
            selectedRunId = nil
        }
    }
    
    private func performBatchOp(type: String, action: String, project: Project) {
        guard let run = getSelectedRun(project: project) else { return }
        
        var markers: [MarkerData] = []
        
        if type == "scene" {
            markers = run.sceneMarkers ?? []
            if markers.isEmpty {
                return // No data or empty
            }
        } else if type == "vfx" {
            // Convert Clips to Markers
            for clip in run.clips {
                // Validation: Need frames
                guard let start = clip.frameStart, let end = clip.frameEnd else { continue }
                
                // Green Start
                markers.append(MarkerData(frameId: start, color: "Green", name: clip.vfxName, note: "Resolver-Vfx-Marker", duration: 1))
                
                // Red End
                markers.append(MarkerData(frameId: end - 1, color: "Red", name: clip.vfxName, note: "Resolver-Vfx-Marker", duration: 1))
            }
            
            // Warn if clips exist but no frames
            if markers.isEmpty && !run.clips.isEmpty {
                print("⚠️ Run has clips but no frame data (legacy run). Cannot toggle markers.")
                return
            }
        }
        
        // Serialize
        struct BatchPayload: Codable {
            let action: String
            let markers: [MarkerData]
        }
        
        let payload = BatchPayload(action: action, markers: markers)
        
        do {
            let data = try JSONEncoder().encode(payload)
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("resolver_batch_ops.json")
            try data.write(to: tmpURL)
            
            // Path matches Script directory
            PyScriptRunner.run(scriptName: "Resolve/Tools/batch_marker_op", args: [tmpURL.path], showOutput: false, enableDownload: false) { output in
                if let out = output { print("Batch Op Result: \(out)") }
            }
        } catch {
            print("Batch Op Error: \(error)")
        }
    }
    
    private func exportCSV(project: Project, run: IndexingRun) {
        var headers: [String] = []
        if showVfxName { headers.append("VFX-Name") }
        if showTcIn { headers.append("Rec-TC-In") }
        if showTcOut { headers.append("Rec-TC-Out") }
        if showSourceTcIn { headers.append("Source-TC-In") }
        if showSourceTcOut { headers.append("Source-TC-Out") }
        if showReelName { headers.append("Reel-Name") }
        if showFileNames { headers.append("File-Names") }
        
        let rows = run.clips.map { clip -> String in
            var columns: [String] = []
            if showVfxName { columns.append(clip.vfxName) }
            if showTcIn { columns.append(clip.tcIn) }
            if showTcOut { columns.append(clip.tcOut) }
            if showSourceTcIn { columns.append(clip.sourceTcIn) }
            if showSourceTcOut { columns.append(clip.sourceTcOut) }
            if showReelName { columns.append(clip.reelName) }
            if showFileNames { columns.append(clip.fileNames) }
            return columns.joined(separator: ",")
        }
        
        let csvContent = ([headers.joined(separator: ",")] + rows).joined(separator: "\n")
        
        let panel = NSSavePanel()
        panel.title = "Export Indexing Run"
        panel.allowedContentTypes = [.commaSeparatedText]
        let dateStr = Formatter.filename.string(from: run.date)
        panel.nameFieldStringValue = "\(project.name)_\(dateStr).csv"
        
        if panel.runModal() == .OK, let url = panel.url {
            try? csvContent.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// Date Formatter Helper
extension Formatter {
    static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()
    static let filename: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        return f
    }()
}
