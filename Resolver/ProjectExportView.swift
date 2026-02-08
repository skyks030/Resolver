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
    @State private var showThumbnails = true
    @State private var showVfxName = true
    
    // Thumbnail Refresh & Alerts
    @State private var thumbnailRefreshID = UUID()
    @State private var showDeleteThumbnailsAlert = false
    @State private var isProcessing = false // Loading State
    @State private var showTcIn = true
    @State private var showTcOut = true
    @State private var showSourceTcIn = true
    @State private var showSourceTcOut = true
    @State private var showFileNames = true
    @State private var showReelName = true
    
    // Settings
    @AppStorage("thumbnailFormat") private var thumbnailFormat: String = "jpg"
    @AppStorage("thumbnailHeight") private var thumbnailHeight: Int = 512

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

                // Marker Operations
                VStack(spacing: 8) {
                    // Row 1: Marker Operations
                    HStack(spacing: 12) {
                        Button { performBatchOp(type: "scene", action: "create", project: project) } label: {
                             Label("Add Scenes", systemImage: "film")
                        }
                        .help("Re-create Scene Markers in Timeline")

                        Button { performBatchOp(type: "vfx", action: "create", project: project) } label: {
                            Label("Add VFX", systemImage: "wand.and.stars")
                        }
                        .help("Create VFX Markers depending on Indexing Run")

                        Button {
                            PyScriptRunner.run(scriptName: "Resolve/Tools/clean_all_resolver_markers", showOutput: false)
                        } label: {
                            Label("Clean All", systemImage: "trash")
                        }
                        .help("Delete ALL Resolver Markers (Scene & VFX) from the Timeline")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    // Row 2: Grouping Operations
                    HStack(spacing: 12) {
                        Button {
                            // Default to Track 1 if not set, but ideally user sets it in menu
                            let track = project.vfxTrackIndex?.isEmpty == false ? project.vfxTrackIndex! : "1"
                            PyScriptRunner.run(scriptName: "Resolve/VFX/clip-grouping", args: [track], showOutput: true)
                        } label: {
                            Label("Show Color Groups", systemImage: "paintpalette")
                        }
                        .help("Create Color Groups for Clips based on VFX Track")
                        
                        Button {
                            PyScriptRunner.run(scriptName: "Resolve/VFX/clean-groups", showOutput: false)
                        } label: {
                            Label("Delete Color Groups", systemImage: "paintpalette.fill")
                        }
                        .help("Remove all Resolver Color Groups")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .fixedSize(horizontal: false, vertical: true)
        .overlay {
            if isProcessing {
                LoadingOverlay(message: "Generating Thumbnails...")
            }
        }
        .onAppear {
            // Window Open -> Dock Icon visible
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @ViewBuilder
    private func toolbarView(project: Project) -> some View {
        HStack {
            Toggle("Thumbnails", isOn: $showThumbnails)
            Toggle("VFX Name", isOn: $showVfxName)
            Toggle("TC In", isOn: $showTcIn)
            Toggle("TC Out", isOn: $showTcOut)
            Toggle("Source In", isOn: $showSourceTcIn)
            Toggle("Source Out", isOn: $showSourceTcOut)
            Toggle("Files", isOn: $showFileNames)
            Toggle("Reel", isOn: $showReelName)
            
            Spacer()
            
            HStack(spacing: 0) {
                Button {
                    if let run = getSelectedRun(project: project) {
                        generateThumbnails(project: project, run: run)
                    }
                } label: {
                    Label("Create Thumbnails", systemImage: "photo.tv")
                }
                .disabled(selectedRunId == nil)
                
                Divider()
                
                Button {
                     showDeleteThumbnailsAlert = true
                } label: {
                     Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .help("Delete All Thumbnails for this Project")
            }
            .buttonStyle(.bordered)
            .alert("Delete Thumbnails?", isPresented: $showDeleteThumbnailsAlert) {
                Button("Delete", role: .destructive) {
                    deleteThumbnails(project: project)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete all thumbnails for this project?")
            }
            
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
            if showThumbnails { Text("Thumb").bold() }
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
                if showThumbnails {
                    if let project = projectManager.currentProject,
                       let url = getThumbnailURL(project: project, run: runBinding.wrappedValue, clip: clip) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fit)
                            case .failure(_):
                                Image(systemName: "photo").foregroundColor(.secondary)
                            case .empty:
                                ProgressView().controlSize(.small)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(width: 50, height: 30)
                        .id(thumbnailRefreshID) // Force reload on update
                    } else {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary.opacity(0.3))
                            .frame(width: 50, height: 30)
                    }
                }
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
        return run.sceneMarkers?.count ?? 0
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
    
    private func generateThumbnails(project: Project, run: IndexingRun) {
        // Start Loading
        isProcessing = true
        
        // 1. Setup Directories
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            isProcessing = false
            return
        }
        
        // Path: com.skyks030.Resolver/Thumbnails/<ProjectID>/
        // We store at Project Level so they persist across runs and are shared.
        let thumbnailsDir = appSupport
            .appendingPathComponent("com.skyks030.Resolver")
            .appendingPathComponent("Thumbnails")
            .appendingPathComponent(project.id.uuidString)
            
        do {
            try fileManager.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
        } catch {
            print("Failed to create thumbnail dir: \(error)")
            isProcessing = false
            return
        }
        
        // 2. Prepare Payload
        let targetTrack = Int(project.vfxTrackIndex ?? "1") ?? 1
        
        let clipsData = run.clips.map { clip -> [String: String] in
            return [
                "name": clip.vfxName,
                "tc": clip.tcIn,
                "frame": String(clip.frameStart ?? 0)
            ]
        }
        
        let payload: [String: Any] = [
            "outputDir": thumbnailsDir.path,
            "targetTrack": targetTrack,
            "clips": clipsData,
            "format": thumbnailFormat,
            "resizeHeight": thumbnailHeight
        ]
        
        // 3. Write JSON & Run Script
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            let tmpURL = fileManager.temporaryDirectory.appendingPathComponent("resolver_thumbnails.json")
            try data.write(to: tmpURL)
            
            // Run silently (showOutput: false) as requested.
            PyScriptRunner.run(scriptName: "Resolve/VFX/generate-thumbnails", args: [tmpURL.path], showOutput: false) { _ in
                // Force UI update
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.thumbnailRefreshID = UUID()
                }
            }
        } catch {
            print("Thumbnail Generation Error: \(error)")
            isProcessing = false
        }
    }

    private func deleteThumbnails(project: Project) {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        
        let projectThumbnailsDir = appSupport
            .appendingPathComponent("com.skyks030.Resolver")
            .appendingPathComponent("Thumbnails")
            .appendingPathComponent(project.id.uuidString)
            
        do {
            if fileManager.fileExists(atPath: projectThumbnailsDir.path) {
                try fileManager.removeItem(at: projectThumbnailsDir)
                // Force UI update
                DispatchQueue.main.async {
                    self.thumbnailRefreshID = UUID()
                }
            }
        } catch {
            print("Failed to delete thumbnails: \(error)")
        }
    }

    private func getThumbnailURL(project: Project, run: IndexingRun, clip: ClipData) -> URL? {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        
        let dirURL = appSupport
            .appendingPathComponent("com.skyks030.Resolver")
            .appendingPathComponent("Thumbnails")
            .appendingPathComponent(project.id.uuidString)
            
        // Resolve often adds prefixes like "1.1.1_" or suffixes.
        // We scan the directory for a file *containing* the VFX Name.
        do {
            let files = try fileManager.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
            if let match = files.first(where: { $0.lastPathComponent.contains(clip.vfxName) }) {
                return match
            }
        } catch {
            // Directory might not exist yet or empty
            return nil
        }
            
        return nil
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
