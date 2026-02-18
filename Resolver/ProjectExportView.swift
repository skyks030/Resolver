import SwiftUI
import UniformTypeIdentifiers

struct ProjectExportView: View {
    @EnvironmentObject var projectManager: ProjectManager
    // Scene Filter
    @State private var selectedScenePrefix: String? = nil // Nil = All Scenes
    
    @State private var selection: Set<UUID> = []
    @State private var selectedRunId: UUID?
    @State private var showDeleteConfirmation = false
    @State private var isEditing = false
    @State private var showRenameAlert = false
    @State private var showDeleteProjectConfirmation = false
    @State private var editingProjectName = ""
    
    // Indexing Error Alert
    @State private var showIndexingError = false
    @State private var indexingErrorMessage = ""
    
    // Indexing Warning Alert
    @State private var showIndexingWarning = false
    @State private var indexingWarningMessage = ""
    
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
    @State private var showDuration = true
    
    // VFX Indexing State
    @State private var vfxTrack: String = "1"
    @State private var vfxThumbnailTrack: String = "1"
    
    @State private var isIndexing = false
    @State private var loadingMessage = ""
    @State private var indexingProgress: Double = 0.0
    @State private var indexingTotal: Int = 0
    @State private var indexingCurrent: Int = 0
    
    // Export Formats
    enum ExportFormat {
        case csv
        case excel
    }
    
    // Settings
    @AppStorage("thumbnailFormat") private var thumbnailFormat: String = "jpg"
    @AppStorage("thumbnailHeight") private var thumbnailHeight: Int = 512

    var body: some View {

        VStack(spacing: 0) {
            if let project = projectManager.currentProject {
                headerView(project: project)
                
                // Scene Filter Toolbar
                HStack {
                    Text("Filter by Scene:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $selectedScenePrefix) {
                        Text("All Scenes").tag(String?.none)
                        
                        if let run = getSelectedRun(project: project) {
                            let scenes = getDerivedScenes(run: run)
                            ForEach(scenes, id: \.self) { scenePrefix in
                                let count = countClipsForScenePrefix(prefix: scenePrefix, run: run)
                                Text("Scene \(scenePrefix) (\(count))").tag(scenePrefix as String?)
                            }
                        }
                    }
                    .frame(width: 200)
                    .controlSize(.small)
                    
                    if selectedScenePrefix != nil {
                        Button {
                            selectedScenePrefix = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    if let run = getSelectedRun(project: project), let filteredCount = filteredClipsCount(run: run) {
                         Text("Showing \(filteredCount) / \(run.clips.count) clips")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                
                Divider()
                
                toolbarView(project: project)
                
                // Table
                if let runBinding = currentRunBinding {
                    ScrollView([.vertical, .horizontal]) {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                            headerRow
                            
                            Divider()
                            
                            // We need to pass filtered INDICES to dataRows to maintain Bindings
                            // We do this by iterating over the filtered indices
                            filteredDataRows(runBinding: runBinding)
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
        .overlay {
            if isIndexing || isProcessing {
                LoadingOverlay(
                    message: loadingMessage.isEmpty ? (isIndexing ? "Indexing VFX Clips..." : "Generating Thumbnails...") : loadingMessage,
                    progress: (isIndexing || isProcessing) ? indexingProgress : nil,
                    current: (isIndexing || isProcessing) ? indexingCurrent : nil,
                    total: (isIndexing || isProcessing) ? indexingTotal : nil
                )
            }
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
        .alert("Indexing Error", isPresented: $showIndexingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(indexingErrorMessage)
        }
        .alert("Indexing Warning", isPresented: $showIndexingWarning) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(indexingWarningMessage)
        }
        .onAppear {
            if let project = projectManager.currentProject {
                if let lastRun = project.runs.last {
                    selectedRunId = lastRun.id
                }
                vfxTrack = project.vfxTrackIndex ?? "1"
                vfxThumbnailTrack = project.vfxThumbnailTrackIndex ?? "1"
            }
        }
        .onChange(of: projectManager.currentProject?.id) { _ in
            if let project = projectManager.currentProject {
                if let lastRun = project.runs.last {
                    selectedRunId = lastRun.id
                }
                vfxTrack = project.vfxTrackIndex ?? "1"
                vfxThumbnailTrack = project.vfxThumbnailTrackIndex ?? "1"
                selectedScenePrefix = nil // Reset filter on project change
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
                // Row 1: Project Name, Rename, Delete, Spacer, Indexing
                HStack(spacing: 15) {
                    Menu {
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
                                .font(.title2)
                                .bold()
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.down")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    HStack(spacing: 8) {
                        Button {
                            editingProjectName = project.name
                            showRenameAlert = true
                        } label: {
                            Image(systemName: "pencil.line")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Rename Project")
                        
                        Button {
                            showDeleteProjectConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Delete Project")
                    }
                    
                    Spacer()
                    
                    // VFX Indexing Controls (on same line)
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Video Track")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                            TextField("", text: $vfxTrack)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 40)
                                .multilineTextAlignment(.center)
                                .onChange(of: vfxTrack) { newValue in
                                    let filtered = newValue.filter { "0123456789".contains($0) }
                                    if filtered != newValue { vfxTrack = filtered }
                                    if vfxTrack.count > 2 { vfxTrack = String(vfxTrack.prefix(2)) }
                                }
                        }
                        
                        Button(action: { runIndexing(project: project) }) {
                            Label("Index VFX Clips", systemImage: "bolt.fill")
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(isIndexing || vfxTrack.isEmpty)
                    }
                }
                .padding(.bottom, 2)
                
                // Row 2: Summary and Run Picker
                HStack(spacing: 20) {
                    if let run = getSelectedRun(project: project) {
                        HStack(spacing: 12) {
                            Label("\(countScenes(in: run)) Scenes", systemImage: "clapperboard")
                            Label("\(run.clips.count) Clips", systemImage: "film")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                    if !project.runs.isEmpty {
                        Picker("Run:", selection: $selectedRunId) {
                            ForEach(project.runs.sorted(by: { $0.date > $1.date })) { run in
                                Text("\(Formatter.date.string(from: run.date)) (\(run.clips.count) Clips)")
                                    .tag(run.id as UUID?)
                            }
                        }
                        .frame(width: 300)
                        .controlSize(.small)
                        .onChange(of: selectedRunId) { _ in
                            selectedScenePrefix = nil // Reset filter when changing run
                        }
                    } else {
                        Text("No indexing runs yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if selectedRunId != nil {
                Button(isEditing ? "Save Changes" : "Edit Mode") {
                    if isEditing {
                        // SAVE CHANGES
                        if let project = projectManager.currentProject, let runId = selectedRunId {
                            // Find changes
                            var updates: [String: String] = [:]
                            
                            // CRITICAL FIX: Read from `project` (which is currentProject) because it has the Binding updates
                            if let run = project.runs.first(where: { $0.id == runId }) {
                                
                                for clip in run.clips {
                                    // Use UniqueID if available, else fallback to OriginalName
                                    if let key = clip.uniqueId ?? clip.originalVfxName {
                                         if clip.vfxName != clip.originalVfxName { // Check if renamed
                                             // Note: We map Key -> New Name.
                                             print("📝 Detected Rename: \(clip.originalVfxName ?? "nil") -> \(clip.vfxName) (Key: \(key))")
                                             updates[key] = clip.vfxName
                                         }
                                    }
                                }
                                print("✅ Total Updates to Save: \(updates.count)")
                            }
                            
                            if !updates.isEmpty {
                                projectManager.updateVfxRenamingMap(projectId: project.id, updates: updates)
                            } else {
                                projectManager.save() 
                            }
                        }
                    } else {
                        // ENTER EDIT MODE
                        // Backfill originalVfxName if missing
                        if let project = projectManager.currentProject, let runId = selectedRunId,
                           let pIndex = projectManager.projects.firstIndex(where: { $0.id == project.id }),
                           let rIndex = projectManager.projects[pIndex].runs.firstIndex(where: { $0.id == runId }) {
                            
                            var run = projectManager.projects[pIndex].runs[rIndex]
                            var changed = false
                            for i in 0..<run.clips.count {
                                if run.clips[i].originalVfxName == nil {
                                    run.clips[i].originalVfxName = run.clips[i].vfxName
                                    changed = true
                                }
                            }
                            if changed {
                                projectManager.projects[pIndex].runs[rIndex] = run
                                // Do not save yet, just update state for editing
                                if projectManager.currentProject?.id == project.id {
                                    projectManager.currentProject = projectManager.projects[pIndex]
                                }
                            }
                        }
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
                    // Row 1: Marker Operations
                    HStack(spacing: 16) {
                        // Scene Group
                        HStack(spacing: 0) {
                            Button { performBatchOp(type: "scene", action: "create", project: project) } label: {
                                Label("Add Scenes", systemImage: "film")
                            }
                            .help("Re-create Scene Markers in Timeline")
                            
                            Divider().frame(height: 16)
                            
                            Button { performBatchOp(type: "scene", action: "delete", project: project) } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .help("Delete Scene Markers")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        // VFX Group
                        HStack(spacing: 0) {
                            Button { performBatchOp(type: "vfx", action: "create", project: project) } label: {
                                Label("Add VFX", systemImage: "wand.and.stars")
                            }
                            .help("Create VFX Markers depending on Indexing Run")
                            
                            Divider().frame(height: 16)
                            
                            Button { performBatchOp(type: "vfx", action: "delete", project: project) } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .help("Delete VFX Markers")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    // Row 2: Grouping Operations
                    HStack(spacing: 12) {
                        Button {
                            // Default to Track 1 if not set, but ideally user sets it in menu
                            let track = project.vfxTrackIndex?.isEmpty == false ? project.vfxTrackIndex! : "1"
                            
                            // START LOADING
                            isProcessing = true
                            loadingMessage = "Grouping Clips..."
                            indexingProgress = 0.0
                            indexingCurrent = 0
                            indexingTotal = 0
                            
                            // Progress Handler
                            let progressHandler: (String) -> Void = { progressLine in
                                if let range = progressLine.range(of: "PROGRESS: ") {
                                    let valueStr = String(progressLine[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                                    let parts = valueStr.components(separatedBy: "/")
                                    if parts.count == 2, let current = Int(parts[0]), let total = Int(parts[1]) {
                                         DispatchQueue.main.async {
                                             self.indexingCurrent = current
                                             self.indexingTotal = total
                                             if total > 0 {
                                                 self.indexingProgress = Double(current) / Double(total)
                                             }
                                         }
                                    }
                                }
                            }
                            
                            // Completion Handler
                            let completionHandler: (String?) -> Void = { _ in
                                DispatchQueue.main.async {
                                    self.isProcessing = false
                                    self.loadingMessage = ""
                                }
                            }
                            
                            // Serialize Clip Data for Script
                            // We need to pass the *latest* data, so we fetch from manager
                            if let pIndex = projectManager.projects.firstIndex(where: { $0.id == project.id }),
                               let run = getSelectedRun(project: projectManager.projects[pIndex]) {
                                
                                struct ClipPayload: Codable {
                                    let vfxName: String
                                    let originalVfxName: String?
                                    let uniqueId: String?
                                    let frameStart: Int
                                    let frameEnd: Int
                                }
                                
                                let clipsPayload = run.clips.compactMap { clip -> ClipPayload? in
                                    guard let start = clip.frameStart, let end = clip.frameEnd else { return nil }
                                    return ClipPayload(vfxName: clip.vfxName, originalVfxName: clip.originalVfxName, uniqueId: clip.uniqueId, frameStart: start, frameEnd: end)
                                }
                                
                                do {
                                    let data = try JSONEncoder().encode(clipsPayload)
                                    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("resolver_grouping_clips.json")
                                    try data.write(to: tmpURL)
                                    
                                    print("🚀 Calling clip-grouping with Track: \(track), JSON: \(tmpURL.path)")
                                    
                                    PyScriptRunner.run(scriptName: "Resolve/VFX/clip-grouping", args: [track, tmpURL.path], showOutput: true, onProgress: progressHandler, completion: completionHandler)
                                } catch {
                                    print("Failed to encode clips for grouping: \(error)")
                                    isProcessing = false // Reset on error
                                }
                            } else {
                                // Fallback if no run selected
                                PyScriptRunner.run(scriptName: "Resolve/VFX/clip-grouping", args: [track], showOutput: true, onProgress: progressHandler, completion: completionHandler)
                            }
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

        .onAppear {
            // Window Open -> Dock Icon visible
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @ViewBuilder
    private func toolbarView(project: Project) -> some View {
        HStack(alignment: .bottom) {
            // Left: Compact Column Toggles (2 Rows, Scrollable)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Toggle("Thumbnails", isOn: $showThumbnails).controlSize(.small)
                        Toggle("VFX Name", isOn: $showVfxName).controlSize(.small)
                        Toggle("Duration", isOn: $showDuration).controlSize(.small)
                        Toggle("Files", isOn: $showFileNames).controlSize(.small)
                        Toggle("Reel", isOn: $showReelName).controlSize(.small)
                    }
                    HStack(spacing: 12) {
                        Toggle("TC In", isOn: $showTcIn).controlSize(.small)
                        Toggle("TC Out", isOn: $showTcOut).controlSize(.small)
                        Toggle("Source In", isOn: $showSourceTcIn).controlSize(.small)
                        Toggle("Source Out", isOn: $showSourceTcOut).controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 50) // Valid height for 2 rows
            
            Spacer()
            
            // Right: Actions
            HStack(spacing: 16) {
                // Thumbnail Generation (Strictly Horizontal)
                HStack(spacing: 10) {
                    Text("Source Track:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("", text: $vfxThumbnailTrack)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 30)
                        .multilineTextAlignment(.center)
                        .controlSize(.small)
                        .onChange(of: vfxThumbnailTrack) { newValue in
                            let filtered = newValue.filter { "0123456789".contains($0) }
                            if filtered != newValue { vfxThumbnailTrack = filtered }
                            if vfxThumbnailTrack.count > 2 { vfxThumbnailTrack = String(vfxThumbnailTrack.prefix(2)) }
                            
                            // Persist
                            if let project = projectManager.currentProject {
                                projectManager.updateVfxThumbnailTrack(projectId: project.id, track: vfxThumbnailTrack)
                            }
                        }
                    
                    Button {
                        if let run = getSelectedRun(project: project) {
                            generateThumbnails(project: project, run: run)
                        }
                    } label: {
                        Label("Create Thumbnails", systemImage: "photo.tv")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(selectedRunId == nil)
                    .help("Generate Thumbnails from specified Track")
                    
                    Button {
                         showDeleteThumbnailsAlert = true
                    } label: {
                         Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Delete All Thumbnails")
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                
                // Export Menu (Standard Size)
                Menu {
                    Button {
                        if let run = getSelectedRun(project: project) {
                            exportCSV(project: project, run: run)
                        }
                    } label: {
                        Label("CSV Export", systemImage: "doc.text")
                    }
                    
                    Button {
                        if let run = getSelectedRun(project: project) {
                            exportExcel(project: project, run: run)
                        }
                    } label: {
                        Label("Excel Export (with Images)", systemImage: "doc.zipper")
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.button)
                .buttonStyle(.borderedProminent)
                .disabled(selectedRunId == nil)
                .controlSize(.regular)
                .fixedSize() // Prevent expansion
            }
            .alert("Delete Thumbnails?", isPresented: $showDeleteThumbnailsAlert) {
                Button("Delete", role: .destructive) {
                    deleteThumbnails(project: project)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete all thumbnails for this project?")
            }
        }
        .padding()
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var headerRow: some View {
        GridRow {
            if showThumbnails { Text("Thumb").bold() }
            if showVfxName { Text("VFX Name").bold() }
            if showDuration { Text("Duration").bold() }
            if showTcIn { Text("TC In").bold() }
            if showTcOut { Text("TC Out").bold() }
            if showSourceTcIn { Text("Source In").bold() }
            if showSourceTcOut { Text("Source Out").bold() }
            if showReelName { Text("Reel Name").bold() }
            if showFileNames { Text("File Names").bold() }
        }
        .padding(.horizontal)
    }
    
    // Replacement for dataRows that supports filtering
    @ViewBuilder
    private func filteredDataRows(runBinding: Binding<IndexingRun>) -> some View {
        // 1. Get List of Selected Indices to maintain valid Bindings
        let indices = getFilteredIndices(run: runBinding.wrappedValue)
        
        ForEach(indices, id: \.self) { index in
            // Correctly bind to the specific index in the array
            let clipBinding = runBinding.clips[index]
            
            GridRow {
                if showThumbnails {
                    if let project = projectManager.currentProject,
                       let url = getThumbnailURL(project: project, run: runBinding.wrappedValue, clip: clipBinding.wrappedValue) {
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
                    if isEditing { TextField("", text: clipBinding.vfxName).textFieldStyle(.plain) }
                    else { Text(clipBinding.wrappedValue.vfxName).lineLimit(1).fixedSize() }
                }
                if showDuration {
                    Text(String(clipBinding.wrappedValue.duration ?? 0))
                }
                if showTcIn {
                    if isEditing { TextField("", text: clipBinding.tcIn).textFieldStyle(.plain) }
                    else { Text(clipBinding.wrappedValue.tcIn).lineLimit(1).fixedSize() }
                }
                if showTcOut {
                    if isEditing { TextField("", text: clipBinding.tcOut).textFieldStyle(.plain) }
                    else { Text(clipBinding.wrappedValue.tcOut).lineLimit(1).fixedSize() }
                }
                if showSourceTcIn {
                    if isEditing { TextField("", text: clipBinding.sourceTcIn).textFieldStyle(.plain) }
                    else { Text(clipBinding.wrappedValue.sourceTcIn).lineLimit(1).fixedSize() }
                }
                if showSourceTcOut {
                    if isEditing { TextField("", text: clipBinding.sourceTcOut).textFieldStyle(.plain) }
                    else { Text(clipBinding.wrappedValue.sourceTcOut).lineLimit(1).fixedSize() }
                }
                if showReelName {
                    if isEditing { TextField("", text: clipBinding.reelName).textFieldStyle(.plain) }
                    else { Text(clipBinding.wrappedValue.reelName).lineLimit(1).fixedSize() }
                }
                if showFileNames {
                    if isEditing { TextField("", text: clipBinding.fileNames).textFieldStyle(.plain) }
                    else { Text(clipBinding.wrappedValue.fileNames).lineLimit(1).fixedSize() }
                }
            }
            .padding(.horizontal)
            
            Divider()
        }
    }

    /*
    @ViewBuilder
    private func dataRows(runBinding: Binding<IndexingRun>) -> some View {
        ForEach(runBinding.clips) { $clip in
            // Original implementation (Kept for reference if needed, but replaced by filteredDataRows)
             GridRow { ... }
        }
    }
     */
    
    // Helpers
    private func getDerivedScenes(run: IndexingRun) -> [String] {
        let prefixes = run.clips.compactMap { clip -> String? in
            let parts = clip.vfxName.split(separator: "_")
            if !parts.isEmpty {
                return String(parts[0])
            }
            return nil
        }
        // distinct and sorted
        return Array(Set(prefixes)).sorted()
    }

    private func countClipsForScenePrefix(prefix: String, run: IndexingRun) -> Int {
        return run.clips.filter { clip in
             clip.vfxName.hasPrefix(prefix + "_") || clip.vfxName == prefix
        }.count
    }

    private func getFilteredIndices(run: IndexingRun) -> [Int] {
        guard let prefix = selectedScenePrefix else {
            // No filter -> All indices
            return Array(run.clips.indices)
        }
        
        return run.clips.indices.filter { i in
            let name = run.clips[i].vfxName
            return name.hasPrefix(prefix + "_") || name == prefix
        }
    }
    
    private func filteredClipsCount(run: IndexingRun) -> Int? {
        guard selectedScenePrefix != nil else { return nil }
        return getFilteredIndices(run: run).count
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
        // Fetch FRESH project data to ensure we use renamed clips
        guard let pIndex = projectManager.projects.firstIndex(where: { $0.id == project.id }) else { return }
        let freshProject = projectManager.projects[pIndex]
        
        guard let run = getSelectedRun(project: freshProject) else { return }
        
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
                
                // Red End (Only if enabled)
                if project.vfxEndMarkerEnabled == true {
                    markers.append(MarkerData(frameId: end - 1, color: "Red", name: clip.vfxName, note: "Resolver-Vfx-Marker", duration: 1))
                }
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
            PyScriptRunner.run(scriptName: "Resolve/Tools/batch_marker_op", args: [tmpURL.path], showOutput: false, enableDownload: false, completion: { output in
                if let out = output { print("Batch Op Result: \(out)") }
            })
        } catch {
            print("Batch Op Error: \(error)")
        }
    }
    
    private func generateThumbnails(project: Project, run: IndexingRun) {
        // Start Loading
        isProcessing = true
        
        // 0. Fetch FRESH Data
        // The passed 'project' and 'run' might be stale copies from the View.
        // We must reach into projectManager to get the source of truth.
        guard let pIndex = projectManager.projects.firstIndex(where: { $0.id == project.id }),
              let rIndex = projectManager.projects[pIndex].runs.firstIndex(where: { $0.id == run.id }) else {
            print("❌ Could not find fresh project/run data for thumbnails.")
            isProcessing = false
            return
        }
        
        let freshProject = projectManager.projects[pIndex]
        let freshRun = freshProject.runs[rIndex]
        
        print("📸 Generating Thumbnails for \(freshRun.clips.count) clips (View had: \(run.clips.count)) from Track: \(self.vfxThumbnailTrack)")
        
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
            .appendingPathComponent(freshProject.id.uuidString)
            
        do {
            try fileManager.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
        } catch {
            print("Failed to create thumbnail dir: \(error)")
            isProcessing = false
            return
        }
        
        // 2. Prepare Payload
        let targetTrack = Int(self.vfxThumbnailTrack) ?? 1
        
        let clipsData = freshRun.clips.map { clip -> [String: String] in
            return [
                "name": clip.vfxName,
                "tc": clip.tcIn,
                "frameStart": String(clip.frameStart ?? 0),
                "frameEnd": String(clip.frameEnd ?? 0)
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
            
            // Run silently (showOutput: false) as requested, but with progress
            PyScriptRunner.run(scriptName: "Resolve/VFX/generate-thumbnails", args: [tmpURL.path], showOutput: false, onProgress: { progressLine in
                // Parse PROGRESS: 1/10
                if let range = progressLine.range(of: "PROGRESS: ") {
                    let valueStr = String(progressLine[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let parts = valueStr.components(separatedBy: "/")
                    if parts.count == 2, let current = Int(parts[0]), let total = Int(parts[1]) {
                         DispatchQueue.main.async {
                             self.indexingCurrent = current
                             self.indexingTotal = total
                             if total > 0 {
                                 // We use indexingProgress variable for simplicity, maybe rename it to 'progress' later
                                 self.indexingProgress = Double(current) / Double(total)
                             }
                         }
                    }
                }
            }) { _ in
                // Force UI update
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.indexingCurrent = 0
                    self.indexingTotal = 0
                    self.indexingProgress = 0.0
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
        if showDuration { headers.append("Duration") }
        if showTcIn { headers.append("Rec-TC-In") }
        if showTcOut { headers.append("Rec-TC-Out") }
        if showSourceTcIn { headers.append("Source-TC-In") }
        if showSourceTcOut { headers.append("Source-TC-Out") }
        if showReelName { headers.append("Reel-Name") }
        if showFileNames { headers.append("File-Names") }
        
        let rows = run.clips.map { clip -> String in
            var columns: [String] = []
            if showVfxName { columns.append(clip.vfxName) }
            if showDuration { columns.append(String(clip.duration ?? 0)) }
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
    
    private func exportExcel(project: Project, run: IndexingRun) {
        var headers: [String] = []
        if showThumbnails { headers.append("Thumbnail") }
        if showVfxName { headers.append("VFX-Name") }
        if showDuration { headers.append("Duration") }
        if showTcIn { headers.append("Rec-TC-In") }
        if showTcOut { headers.append("Rec-TC-Out") }
        if showSourceTcIn { headers.append("Source-TC-In") }
        if showSourceTcOut { headers.append("Source-TC-Out") }
        if showReelName { headers.append("Reel-Name") }
        if showFileNames { headers.append("File-Names") }
        
        let clipsData = run.clips.map { clip -> [String: String] in
            var dict: [String: String] = [:]
            if showThumbnails {
                if let url = getThumbnailURL(project: project, run: run, clip: clip) {
                    dict["thumbnail"] = url.path
                } else {
                    dict["thumbnail"] = ""
                }
            }
            if showVfxName { dict["vfxName"] = clip.vfxName }
            if showDuration { dict["duration"] = String(clip.duration ?? 0) }
            if showTcIn { dict["tcIn"] = clip.tcIn }
            if showTcOut { dict["tcOut"] = clip.tcOut }
            if showSourceTcIn { dict["sourceTcIn"] = clip.sourceTcIn }
            if showSourceTcOut { dict["sourceTcOut"] = clip.sourceTcOut }
            if showReelName { dict["reelName"] = clip.reelName }
            if showFileNames { dict["fileNames"] = clip.fileNames }
            return dict
        }
        
        let panel = NSSavePanel()
        panel.title = "Export Excel with Images"
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")].compactMap { $0 }
        let dateStr = Formatter.filename.string(from: run.date)
        panel.nameFieldStringValue = "\(project.name)_\(dateStr).xlsx"
        
        if panel.runModal() == .OK, let outputURL = panel.url {
            let payload: [String: Any] = [
                "headers": headers,
                "clips": clipsData,
                "outputPath": outputURL.path
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: payload)
                let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("resolver_excel_export.json")
                try jsonData.write(to: tmpURL)
                
                PyScriptRunner.run(scriptName: "Resolve/Tools/export_excel", args: [tmpURL.path], showOutput: false, completion: { output in
                    if let out = output { print("Excel Export Result: \(out)") }
                })
            } catch {
                print("Excel Export Data Error: \(error)")
            }
        }
    }
    
    private func runIndexing(project: Project) {
        isIndexing = true
        loadingMessage = "Connecting to Resolve..."
        
        // Save track choice
        projectManager.updateVfxTrack(projectId: project.id, track: vfxTrack)
        
        let endMarkerEnabled = project.vfxEndMarkerEnabled ?? false
        let endMarkerArg = endMarkerEnabled ? "true" : "false"
        
        // Prepare Renaming Map
        var renamingMapArg = ""
        if let map = project.vfxRenamingMap, !map.isEmpty {
            do {
                let data = try JSONEncoder().encode(map)
                let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("resolver_renaming_map.json")
                try data.write(to: tmpURL)
                renamingMapArg = tmpURL.path
            } catch {
                print("Failed to encode renaming map: \(error)")
            }
        }
        
        // Args: [track, endMarkerEnabled, renamingMapJSON]
        var args = [vfxTrack, endMarkerArg]
        if !renamingMapArg.isEmpty {
            args.append(renamingMapArg)
        }

        PyScriptRunner.run(scriptName: "Resolve/VFX/clip-indexing", args: args, showOutput: false, onProgress: { progressLine in
            // Parse PROGRESS: 1/10
            if let range = progressLine.range(of: "PROGRESS: ") {
                let valueStr = String(progressLine[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = valueStr.components(separatedBy: "/")
                if parts.count == 2, let current = Int(parts[0]), let total = Int(parts[1]) {
                     DispatchQueue.main.async {
                         self.indexingCurrent = current
                         self.indexingTotal = total
                         if total > 0 {
                             self.indexingProgress = Double(current) / Double(total)
                         }
                     }
                }
            }
        }) { output in
            DispatchQueue.main.async {
                self.isIndexing = false
                self.loadingMessage = ""
                
                guard let output = output else { return }
                
                var jsonString = output
                if let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}") {
                    if start <= end { jsonString = String(output[start...end]) }
                } else if let start = output.firstIndex(of: "["), let end = output.lastIndex(of: "]") {
                     if start <= end { jsonString = String(output[start...end]) }
                }
                
                print("🔍 Indexing Output (Track: \(self.vfxTrack)): \(jsonString)")
                
                guard let data = jsonString.data(using: .utf8) else { return }
                
                do {
                    // Match the logic from DropDownMenu
                    struct IncomingRunData: Decodable {
                        let clips: [IncomingClipData]
                        let sceneMarkers: [IncomingMarkerData]
                        let warning: String?
                    }
                    struct IncomingClipData: Decodable {
                        let vfxName, tcIn, tcOut, sourceTcIn, sourceTcOut, fileNames, reelName: String
                        let frameStart, frameEnd, duration: Int?
                    }
                    struct IncomingMarkerData: Decodable {
                        let frameId: Int
                        let color, name, note: String
                        let duration: Int
                    }
                    
                    let runData = try JSONDecoder().decode(IncomingRunData.self, from: data)
                    
                    // Check for warnings
                    if let warning = runData.warning, !warning.isEmpty {
                        self.indexingWarningMessage = warning
                        self.showIndexingWarning = true
                    }
                    
                    let clips = runData.clips.map { raw in
                        ClipData(vfxName: raw.vfxName, tcIn: raw.tcIn, tcOut: raw.tcOut, sourceTcIn: raw.sourceTcIn, sourceTcOut: raw.sourceTcOut, fileNames: raw.fileNames, reelName: raw.reelName, frameStart: raw.frameStart, frameEnd: raw.frameEnd, duration: raw.duration)
                    }
                    let markers = runData.sceneMarkers.map { raw in
                        MarkerData(frameId: raw.frameId, color: raw.color, name: raw.name, note: raw.note, duration: raw.duration)
                    }
                    projectManager.addIndexingRun(to: project.id, clips: clips, sceneMarkers: markers)
                } catch {
                    print("Indexing Error: \(error)")
                    self.indexingErrorMessage = "Failed to process indexing data: \(error.localizedDescription)"
                    self.showIndexingError = true
                }
            }
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
