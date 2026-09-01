import SwiftUI
import UniformTypeIdentifiers

struct ProjectExportView: View {
    @EnvironmentObject var projectManager: ProjectManager
    // Scene Filter
    @State private var selectedScenePrefix: String? = nil
    
    // UI Interactions
    @State private var customColumnWidths: [String: CGFloat] = [:]
    @State private var dragInitialWidth: CGFloat? = nil
    @State private var draggedColumn: String? = nil // Nil = All Scenes
    
    @State private var selection: Set<UUID> = []
    
    // UI State
    @State private var showRenameAlert = false
    @State private var showDeleteProjectConfirmation = false
    @State private var showNewProjectAlert = false
    @State private var editingProjectName = ""
    @State private var newProjectName = ""
    @FocusState private var newProjectIsFocused: Bool
    
    struct CellID: Hashable { let clipId: UUID; let col: String }
    @State private var editingCell: CellID? = nil
    @FocusState private var focusedField: CellID?
    @State private var showDeleteShotsAlert = false
    @State private var editingHeader: String? = nil
    @FocusState private var focusedHeader: String?
    @State private var headerEditText: String = ""
    @State private var showDeleteColumnAlert = false
    @State private var columnToDelete = ""
    
    @State private var showMergeReview = false
    @State private var pendingMergeItems: [MergeItem] = []
    @State private var pendingImportedClips: [ClipData] = []
    @State private var pendingSceneMarkers: [MarkerData] = []
    @State private var currentMergeKey: MergeKeyOption = .smart
    
    // Scene Manager & Generator States
    @State private var showSceneManager = false
    @State private var showEpisodeManager = false
    @State private var showVfxNameGenerator = false
    
    // Import State
    @State private var showCSVImport = false
    @State private var showDaVinciImport = false
    @State private var showThumbnailImport = false
    @State private var showImportDataSheet = false
    @State private var showExportDataSheet = false
    
    @State private var isEditingMasterlist = false
    @State private var selectedForDelete: Set<UUID> = []
    @State private var lastToggledClipId: UUID? = nil

    // Batch Editor State
    @State private var showBatchEditSheet = false
    @State private var batchEditColumn: String = ""
    @State private var batchEditValue: String = ""

    // Duplicate Scanner State
    @State private var showOnlyDuplicates = false
    
    // Sort & Order
    @State private var sortColumn: String? = nil
    @State private var sortAscending: Bool = true
    @State private var columnOrder: [String] = []
    // Alerts
    @State private var showIndexingError = false
    @State private var indexingErrorMessage = ""
    @State private var showIndexingWarning = false
    @State private var indexingWarningMessage = ""
    
    // Column Toggles
    @State private var hasThumbnailsCache = false
    
    // Dynamic Columns State
    @State private var customColumnVisibility: [String: Bool] = [:]
    
    private var availableCustomColumns: [String] {
        var keys = Set<String>()
        for clip in projectManager.currentMasterList {
            keys.formUnion(clip.dict.keys)
        }
        return keys.sorted()
    }
    
    // VFX Name, Clip Name, [Episode], [Scene], and the TC columns are always
    // pinned at the front, in that order. Episode/Scene are only included when
    // they actually carry data — i.e. when Episodes/Scenes are registered and
    // matched to at least one clip — otherwise they behave like any other
    // (absent) custom column.
    private var fixedColumns: [String] {
        var cols = ["VFX Name", "Clip Name"]
        let available = availableCustomColumns
        if available.contains("Episode") { cols.append("Episode") }
        if available.contains("Scene") { cols.append("Scene") }
        cols.append(contentsOf: ["TC In", "TC Out", "Source TC In", "Source TC Out"])
        return cols
    }

    private var activeColumns: [String] {
        let available = availableCustomColumns
        var cols = columnOrder.filter { available.contains($0) }
        for col in available {
            if !cols.contains(col) { cols.append(col) }
        }

        let fixedCols = fixedColumns
        cols.removeAll(where: { fixedCols.contains($0) })

        // Add them back at the very front
        cols.insert(contentsOf: fixedCols, at: 0)

        return cols
    }
    
    // Thumbnails & Loading
    @State private var thumbnailRefreshID = UUID()
    @State private var showDeleteThumbnailsAlert = false
    @State private var isProcessing = false
    @State private var isIndexing = false
    @State private var loadingMessage = ""
    @State private var indexingProgress: Double = 0.0
    @State private var indexingTotal: Int = 0
    @State private var indexingCurrent: Int = 0
    
    // VFX Indexing State
    @State private var vfxTrack: String = "1"
    @State private var vfxThumbnailTrack: String = "1"
    @State private var indexAllEpisodes: Bool = false
    
    // Settings
    @AppStorage("thumbnailFormat") private var thumbnailFormat: String = "jpg"
    @AppStorage("thumbnailHeight") private var thumbnailHeight: Int = 512

    var body: some View {
        VStack(spacing: 0) {
            if let project = projectManager.currentProject {
                // Top Control Section (Glass Effect)
                VStack(spacing: 0) {
                    headerView(project: project)
                    
                    if !duplicateVFXNames.isEmpty {
                        duplicateWarningBanner
                    }
                    
                    Divider()
                    
                    // Filter + Column Toolbar
                    HStack(spacing: 10) {
                        // Unified Filter menu
                        Menu {
                            Section("Filter by Scene") {
                                Button("All Scenes") { selectedScenePrefix = nil }
                                    .disabled(selectedScenePrefix == nil)
                                ForEach(projectManager.currentScenes) { scene in
                                    Button {
                                        selectedScenePrefix = (selectedScenePrefix == scene.name) ? nil : scene.name
                                    } label: {
                                        if selectedScenePrefix == scene.name {
                                            Label("\(scene.name) (\(scene.startTC))", systemImage: "checkmark")
                                        } else {
                                            Text("\(scene.name) (\(scene.startTC))")
                                        }
                                    }
                                }
                            }
                            Section("Columns") {
                                let customCols = availableCustomColumns
                                if customCols.isEmpty {
                                    Text("No custom columns").foregroundColor(.secondary)
                                }
                                let toggleCols = customCols.filter { !fixedColumns.contains($0) }
                                ForEach(toggleCols, id: \.self) { col in
                                    Toggle(col, isOn: Binding(
                                        get: { customColumnVisibility[col] ?? true },
                                        set: { customColumnVisibility[col] = $0 }
                                    ))
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                Text(selectedScenePrefix != nil ? "Scene: \(selectedScenePrefix!)" : "Filter")
                            }
                        }
                        .menuStyle(.button)
                        .liquidGlassButton(prominent: false)
                        .controlSize(.regular)
                        .fixedSize()
                        
                        // Scenes button
                        Button { showSceneManager = true } label: {
                            countBadgeLabel(title: "Scenes", icon: "film.stack", count: projectManager.currentScenes.count)
                        }
                        .liquidGlassButton(prominent: false)
                        .controlSize(.regular)
                        .fixedSize()

                        // Episodes button
                        Button { showEpisodeManager = true } label: {
                            countBadgeLabel(title: "Episodes", icon: "list.bullet.rectangle.portrait", count: projectManager.currentEpisodes.count)
                        }
                        .liquidGlassButton(prominent: false)
                        .controlSize(.regular)
                        .fixedSize()

                        if selectedScenePrefix != nil {
                            Button { selectedScenePrefix = nil } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Spacer()
                        
                        if let filteredCount = filteredClipsCount(clips: projectManager.currentMasterList) {
                            Text("Showing \(filteredCount) / \(projectManager.currentMasterList.count) clips")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    
                    Divider()
                    
                    toolbarView(project: project)
                }
                .liquidGlassBar()
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 3)
                .zIndex(1) // Keep shadow above the table

                // Master VFX List Table
                if !projectManager.currentMasterList.isEmpty {
                    ScrollView([.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section(header: headerRow.liquidGlassBar()) {
                                filteredDataRows()
                            }
                        }
                        .padding(.vertical)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .background(Color.clear.contentShape(Rectangle()).onTapGesture {
                        if isEditingMasterlist {
                            editingCell = nil
                            focusedField = nil
                            finishHeaderEditing()
                        }
                    })
                } else {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "film")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("Master VFX List is empty.")
                            .font(.title2)
                            .bold()
                        Text("Click 'Import Data' to import clips from DaVinci Resolve or a CSV.")
                            .foregroundColor(.secondary)
                        Button("Import Data") {
                            showImportDataSheet = true
                        }
                        .liquidGlassButton(prominent: true)
                        .padding(.top, 10)
                    }
                    Spacer()
                }
                
            } else {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("No Project Selected")
                        .font(.title2)
                        .bold()
                    Text("Select a project from the drop-down menu or create a new one.")
                        .foregroundColor(.secondary)
                    Button("Create New Project") {
                        showNewProjectAlert = true
                    }
                    .liquidGlassButton(prominent: true)
                    .controlSize(.large)
                    .padding(.top, 10)
                }
                Spacer()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        
        // Modals & Alerts
        .sheet(isPresented: $showImportDataSheet) {
            ImportDataSheet(
                onDaVinciImport: {
                    showImportDataSheet = false
                    DaVinciChecker.performPreflightCheck { diag in
                        if let diag = diag, diag.success {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showDaVinciImport = true }
                        } else {
                            showIndexingError = true
                            indexingErrorMessage = diag != nil ? DaVinciChecker.formatError(diagnostic: diag!) : "DaVinci Check Failed"
                        }
                    }
                },
                onCSVImport: {
                    showImportDataSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showCSVImport = true }
                },
                onCancel: { showImportDataSheet = false }
            )
        }
        .sheet(isPresented: $showExportDataSheet) {
            ExportDataSheet(
                onCSVExport: {
                    showExportDataSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let project = projectManager.currentProject { exportCSV(project: project) }
                    }
                },
                onExcelExport: {
                    showExportDataSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let project = projectManager.currentProject { exportExcel(project: project) }
                    }
                },
                onCancel: { showExportDataSheet = false }
            )
        }
        
        .alert("New Project", isPresented: $showNewProjectAlert) {
            TextField("Project Name", text: $newProjectName)
                .focused($newProjectIsFocused)
                .onAppear {
                    newProjectIsFocused = true
                }
            Button("Create") {
                if !newProjectName.isEmpty {
                    projectManager.addProject(name: newProjectName)
                    newProjectName = ""
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { newProjectName = "" }
        }
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
                    message: loadingMessage.isEmpty ? (isIndexing ? "Indexing VFX Clips..." : "Processing...") : loadingMessage,
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
        .alert("Delete Selected Shots?", isPresented: $showDeleteShotsAlert) {
            Button("Delete", role: .destructive) {
                projectManager.currentMasterList.removeAll { selectedForDelete.contains($0.id) }
                projectManager.saveMasterList()
                selectedForDelete.removeAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete the selected \(selectedForDelete.count) VFX shots? This cannot be undone.")
        }
        .alert("Delete Column", isPresented: $showDeleteColumnAlert) {
            Button("Delete", role: .destructive) {
                for i in 0..<projectManager.currentMasterList.count {
                    projectManager.currentMasterList[i].dict.removeValue(forKey: columnToDelete)
                }
                projectManager.saveMasterList()
                customColumnVisibility.removeValue(forKey: columnToDelete)
                columnOrder.removeAll(where: { $0 == columnToDelete })
                if sortColumn == columnToDelete { sortColumn = nil }
                columnToDelete = ""
            }
            Button("Cancel", role: .cancel) { columnToDelete = "" }
        } message: {
            Text("Are you sure you want to delete the column '\(columnToDelete)' and all its data?")
        }
        .alert("DaVinci Resolve Error", isPresented: $showIndexingError) {
            Button("OK", role: .cancel) { }
        } message: { Text(indexingErrorMessage) }
        .alert("DaVinci Resolve Info", isPresented: $showIndexingWarning) {
            Button("OK", role: .cancel) { }
        } message: { Text(indexingWarningMessage) }
        
        // CSV Selection Sheet
        .fileImporter(isPresented: $showCSVImport, allowedContentTypes: [.commaSeparatedText]) { result in
            switch result {
            case .success(let url):
                // Give security access to requested file
                guard url.startAccessingSecurityScopedResource() else {
                    print("Could not access CSV file.")
                    return
                }
                
                // Open Standalone Window
                CSVImportView.showStandalone(url: url) { clips in
                    // On Import Success
                    url.stopAccessingSecurityScopedResource()
                    self.startMergeReview(importedClips: clips, markers: [])
                }
            case .failure(let error):
                print("Failed to select CSV: \(error)")
            }
        }
        
        // Merge Review Sheet (remains a sheet for consistency)
        .sheet(isPresented: $showMergeReview) {
            MergeReviewView(mergeItems: $pendingMergeItems, mergeKey: $currentMergeKey) {
                // Confirm
                var newMaster = projectManager.currentMasterList
                MergeManager.applyMerge(master: &newMaster, mergeItems: pendingMergeItems)
                
                // Only pass markers if it was a Resolve Index (not a CSV import)
                if !pendingSceneMarkers.isEmpty {
                    projectManager.updateMasterList(with: newMaster, sceneMarkers: pendingSceneMarkers)
                } else {
                    projectManager.updateMasterList(with: newMaster)
                }
                
                showMergeReview = false
            } onCancel: {
                showMergeReview = false
            }
            .onChange(of: currentMergeKey) { newKey in
                pendingMergeItems = MergeManager.compare(master: projectManager.currentMasterList, imported: pendingImportedClips, mergeKey: newKey)
            }
        }
        
        // DaVinci Import Sheet
        .sheet(isPresented: $showDaVinciImport) {
            DaVinciImportSheet(vfxTrack: $vfxTrack, indexAllEpisodes: $indexAllEpisodes, episodesCount: projectManager.currentEpisodes.count) {
                showDaVinciImport = false
                if let p = projectManager.currentProject {
                    runIndexing(project: p, allEpisodes: indexAllEpisodes)
                }
            } onCancel: {
                showDaVinciImport = false
            }
        }
        
        // Thumbnail Import Sheet
        .sheet(isPresented: $showThumbnailImport) {
            ThumbnailImportSheet(
                vfxThumbnailTrack: $vfxThumbnailTrack,
                onStart: {
                    showThumbnailImport = false
                    DaVinciChecker.performPreflightCheck { diag in
                        if let diag = diag, diag.success {
                            if let project = projectManager.currentProject {
                                projectManager.updateVfxThumbnailTrack(projectId: project.id, track: vfxThumbnailTrack)
                                generateThumbnails(project: project)
                            }
                        } else {
                            showIndexingError = true
                            indexingErrorMessage = diag != nil ? DaVinciChecker.formatError(diagnostic: diag!) : "DaVinci Check Failed"
                        }
                    }
                },
                onDelete: {
                    showThumbnailImport = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showDeleteThumbnailsAlert = true
                    }
                },
                onCancel: {
                    showThumbnailImport = false
                }
            )
        }
        
        // Scene Management Sheet
        .sheet(isPresented: $showSceneManager) {
            SceneManagementView(project: projectManager.currentProject!)
        }

        // Episode Management Sheet
        .sheet(isPresented: $showEpisodeManager) {
            EpisodeManagementView(project: projectManager.currentProject!)
        }
        
        // VFX Name Generator Sheet
        .sheet(isPresented: $showVfxNameGenerator) {
            VfxNameGeneratorView(project: projectManager.currentProject!)
        }
        
        .onAppear {
            if let project = projectManager.currentProject {
                vfxTrack = project.vfxTrackIndex ?? "1"
                vfxThumbnailTrack = project.vfxThumbnailTrackIndex ?? "1"
                hasThumbnailsCache = hasThumbnails()
            }
        }
        .onChange(of: projectManager.currentProject?.id) { _ in
            if let project = projectManager.currentProject {
                vfxTrack = project.vfxTrackIndex ?? "1"
                vfxThumbnailTrack = project.vfxThumbnailTrackIndex ?? "1"
                selectedScenePrefix = nil
                hasThumbnailsCache = hasThumbnails()
            }
        }
    }
    
    // MARK: - Subviews

    @ViewBuilder
    private func countBadgeLabel(title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
            Text("\(count)")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .liquidGlassCapsule(tint: .secondary)
        }
    }

    private var duplicateWarningBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
                .font(.title2)
            
            VStack(alignment: .leading) {
                Text("Warning: Duplicate VFX Names Detected")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("Found \(duplicateVFXNames.count) names used multiple times.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                withAnimation { showOnlyDuplicates.toggle() }
            } label: {
                Text(showOnlyDuplicates ? "Show All Clips" : "Filter Duplicates")
                    .fontWeight(.semibold)
            }
            .liquidGlassButton(prominent: true)
            .tint(showOnlyDuplicates ? .blue : .red)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.red.opacity(0.1))
    }
    
    @ViewBuilder
    private func defaultHeaderView(project: Project) -> some View {
        HStack(spacing: 20) {
            // LEFT: Project Selection
            VStack(alignment: .leading, spacing: 4) {
                Text("Project")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .fixedSize()
                
                HStack(spacing: 12) {
                    Menu {
                        Button("New Project...") { showNewProjectAlert = true }
                        Divider()
                        ForEach(projectManager.projects) { p in
                            Button(action: { projectManager.selectProject(p.id) }) {
                                if p.id == project.id {
                                    Label(p.name, systemImage: "checkmark")
                                } else { Text(p.name) }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(project.name)
                                .font(.system(size: 24, weight: .bold, design: .default))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .layoutPriority(1)
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
                        } label: { Image(systemName: "pencil.circle.fill").font(.title3).foregroundColor(.accentColor) }
                        .buttonStyle(.plain)
                        .help("Rename Project")
                        
                        Button { showDeleteProjectConfirmation = true } label: { Image(systemName: "trash.circle.fill").font(.title3).foregroundColor(.red) }
                        .buttonStyle(.plain)
                        .help("Delete Project")
                        
                        // Project Stats
                        Text("Episodes: \(projectManager.currentEpisodes.count) | Scenes: \(projectManager.currentScenes.count) | VFX Shots: \(projectManager.currentMasterList.count)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    }
                }
            }
            
            Spacer(minLength: 16)
            
            // CENTER: Import & Export Buttons
            HStack(spacing: 16) {
                Button { showImportDataSheet = true } label: { Label("Import Data", systemImage: "arrow.down.doc").fixedSize() }
                .liquidGlassButton(prominent: true)
                .controlSize(.large)
                .fixedSize()
                
                Button { showExportDataSheet = true } label: { Label("Export Data", systemImage: "square.and.arrow.up").fixedSize() }
                .liquidGlassButton(prominent: false)
                .controlSize(.large)
                .fixedSize()
            }
            .layoutPriority(2) // Ensure these don't get squished
            
            Spacer(minLength: 16)
            
            // RIGHT: Batch Actions (Naming & Deletion handled by Edit Mode)
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 8) {
                    Menu {
                        Button("Add Scene Markers") { performPreflightAndRunBatchOp(type: "scene", action: "create", project: project) }
                        Button("Delete Scene Markers", role: .destructive) { performPreflightAndRunBatchOp(type: "scene", action: "delete", project: project) }
                        Divider()
                        Button("Add VFX Markers") { performPreflightAndRunBatchOp(type: "vfx", action: "create", project: project) }
                        Button("Delete VFX Markers", role: .destructive) { performPreflightAndRunBatchOp(type: "vfx", action: "delete", project: project) }
                    } label: { Label("Markers", systemImage: "mappin.and.ellipse") }
                    .menuStyle(.button)
                    .liquidGlassButton(prominent: false)
                    .controlSize(.small)
                    .fixedSize()
                    
                    Menu {
                        Button("Create Color Groups") { performPreflightAndRunBatchOp(type: "groups", action: "create", project: project) }
                        Button("Delete Color Groups", role: .destructive) {
                            DaVinciChecker.performPreflightCheck { diag in
                                if let diag = diag, diag.success {
                                    PyScriptRunner.run(scriptName: "Resolve/VFX/clean-groups", showOutput: false, onProgress: { _ in }) { _ in }
                                } else {
                                    showIndexingError = true
                                    indexingErrorMessage = diag != nil ? DaVinciChecker.formatError(diagnostic: diag!) : "DaVinci Check Failed"
                                }
                            }
                        }
                    } label: { Label("Groups", systemImage: "paintpalette") }
                    .menuStyle(.button)
                    .liquidGlassButton(prominent: false)
                    .controlSize(.small)
                    .fixedSize()
                }
            }
            
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func headerView(project: Project) -> some View {
        if isEditingMasterlist {
            HStack(spacing: 16) {
                Text("Edit Masterlist Mode")
                    .font(.headline)
                    .foregroundColor(.accentColor)
                
                Spacer()
                
                Button(action: {
                    var newName = "New Column"
                    var counter = 1
                    let customCols = availableCustomColumns
                    while customCols.contains(newName) {
                        newName = "New Column \(counter)"
                        counter += 1
                    }
                    customColumnVisibility[newName] = true
                    if !columnOrder.contains(newName) { columnOrder.append(newName) }
                    
                    if !projectManager.currentMasterList.isEmpty {
                        for i in 0..<projectManager.currentMasterList.count {
                            projectManager.currentMasterList[i].dict[newName] = ""
                        }
                    }
                    projectManager.saveMasterList()
                }) {
                    Label("Add Column", systemImage: "plus.table.column")
                }
                .liquidGlassButton(prominent: false)
                
                Button(action: {
                    var initialDict: [String: String] = [
                        "VFX Name": "New Shot",
                        "Clip Name": "",
                        "TC In": "",
                        "TC Out": "",
                        "Source TC In": "",
                        "Source TC Out": ""
                    ]
                    for col in availableCustomColumns { 
                        if initialDict[col] == nil { initialDict[col] = "" }
                    }
                    let newClip = ClipData(dict: initialDict)
                    projectManager.currentMasterList.append(newClip)
                    projectManager.saveMasterList() // so it persists instantly
                }) {
                    Label("Add Clip", systemImage: "plus.square.on.square")
                }
                .liquidGlassButton(prominent: false)
                
                Button("Select All") {
                    let visibleIds = getFilteredIndices(clips: projectManager.currentMasterList).map { projectManager.currentMasterList[$0].id }
                    if selectedForDelete.count == visibleIds.count {
                        selectedForDelete.removeAll()
                    } else {
                        selectedForDelete = Set(visibleIds)
                    }
                }
                .liquidGlassButton(prominent: false)
                
                Button("Batch Edit") {
                    batchEditColumn = batchEditableColumns.first ?? ""
                    batchEditValue = ""
                    showBatchEditSheet = true
                }
                .liquidGlassButton(prominent: false)
                .disabled(selectedForDelete.isEmpty)
                .help("Set one column to the same value on all \(selectedForDelete.count) selected shots — shift-click a row's checkbox to select a range.")

                Button("Delete Selected") {
                    showDeleteShotsAlert = true
                }
                .liquidGlassButton(prominent: true)
                .tint(.red)
                .disabled(selectedForDelete.isEmpty)

                Button("Done") {
                    // Save renaming overrides implicitly simply by existing dict mutations
                    var updates: [String: String] = [:]
                    for clip in projectManager.currentMasterList {
                        if let key = clip.uniqueId ?? clip.originalVfxName {
                            if clip.vfxName != clip.originalVfxName {
                                updates[key] = clip.vfxName
                            }
                        }
                    }
                    if !updates.isEmpty {
                        projectManager.updateVfxRenamingMap(projectId: project.id, updates: updates)
                    } else {
                        projectManager.saveMasterList()
                    }
                    isEditingMasterlist = false
                    selectedForDelete.removeAll()
                    lastToggledClipId = nil
                }
                .liquidGlassButton(prominent: true)
                .tint(.green)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .sheet(isPresented: $showBatchEditSheet) {
                BatchEditSheet(
                    columns: batchEditableColumns,
                    selectedCount: selectedForDelete.count,
                    column: $batchEditColumn,
                    value: $batchEditValue,
                    onApply: {
                        applyBatchEdit(column: batchEditColumn, value: batchEditValue)
                        showBatchEditSheet = false
                    },
                    onCancel: { showBatchEditSheet = false }
                )
            }
        } else {
            defaultHeaderView(project: project)
        }
    }
    
    @ViewBuilder
    private func toolbarView(project: Project) -> some View {
        HStack(alignment: .center) {
            Spacer(minLength: 20)
            
            // Right: Actions
            HStack(spacing: 12) {
                if !isEditingMasterlist {
                    Button(action: {
                        isEditingMasterlist = true
                        selectedForDelete.removeAll()
                        lastToggledClipId = nil
                    }) {
                        Label("Edit Masterlist", systemImage: "pencil")
                    }
                    .liquidGlassButton(prominent: false)
                    .controlSize(.regular)
                }
                
                Button(action: { showVfxNameGenerator = true }) {
                    Label("Generate VFX Names", systemImage: "wand.and.stars")
                }
                .liquidGlassButton(prominent: false)
                .controlSize(.regular)
                .fixedSize()
                
                Button("Thumbnails") {
                    showThumbnailImport = true
                }
                .liquidGlassButton(prominent: true)
                .controlSize(.regular)
                .fixedSize()
            }
            .alert("Delete Thumbnails?", isPresented: $showDeleteThumbnailsAlert) {
                Button("Delete", role: .destructive) { deleteThumbnails(project: project) }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Are you sure you want to delete all thumbnails for this project?") }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var headerRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if isEditingMasterlist { 
                    Text("").frame(width: 30)
                        .overlay(Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1).offset(x: 10), alignment: .trailing)
                }
                if hasThumbnailsCache { 
                    Text("Thumb").bold()
                        .frame(width: 60)
                        .overlay(Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1).offset(x: 4), alignment: .trailing)
                }
                
                let cols = activeColumns.filter { customColumnVisibility[$0] ?? true }
                ForEach(cols.indices, id: \.self) { i in
                    let col = cols[i]
                    let isFixed = fixedColumns.contains(col)
                    
                    HStack(spacing: 4) {
                        if isEditingMasterlist && !isFixed {
                            // Drag grip handle
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(.leading, 2)
                                .onHover { isHovering in
                                    if isHovering { NSCursor.openHand.push() } else { NSCursor.pop() }
                                }
                                .onDrag {
                                    self.draggedColumn = col
                                    return NSItemProvider(object: col as NSString)
                                }
                        }
                        
                        if isEditingMasterlist && editingHeader == col {
                            TextField("", text: $headerEditText)
                                .textFieldStyle(.plain)
                                .focused($focusedHeader, equals: col)
                                .onSubmit { finishHeaderEditing() }
                                .onChange(of: focusedHeader) { newValue in
                                    if newValue != col && editingHeader == col { finishHeaderEditing() }
                                }
                                .frame(minWidth: 60)
                        } else {
                            HStack(spacing: 2) {
                                Text(col).bold()
                                if sortColumn == col {
                                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down").font(.caption2)
                                }
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isEditingMasterlist {
                                    headerEditText = col
                                    editingHeader = col
                                    focusedHeader = col
                                } else {
                                    sortList(by: col)
                                }
                            }
                        }
                            
                        if isEditingMasterlist && !isFixed {
                            Button(action: {
                                columnToDelete = col
                                showDeleteColumnAlert = true
                            }) {
                                Image(systemName: "minus.circle.fill").foregroundColor(.red).font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // Disable drop target for fixed columns
                    .onDrop(of: isFixed ? [] : [.plainText], delegate: ColumnDropDelegate(item: col, items: $columnOrder, draggedItem: $draggedColumn, activeColumns: cols, fixedColumns: fixedColumns, onReorder: {}))
                    .frame(width: columnWidth(for: col), alignment: .leading)
                    .padding(.horizontal, 4)
                    .overlay(
                        Group {
                            if i < cols.count - 1 {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(width: 4)
                                    .onHover { isHovering in
                                        if isHovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                                    }
                                    .gesture(
                                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                            .onChanged { value in
                                                if dragInitialWidth == nil {
                                                    dragInitialWidth = columnWidth(for: col)
                                                }
                                                let newWidth = max(60, (dragInitialWidth ?? 120) + value.translation.width)
                                                customColumnWidths[col] = newWidth
                                            }
                                            .onEnded { _ in
                                                dragInitialWidth = nil
                                            }
                                    )
                            }
                        },
                        alignment: .trailing
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()
        }
    }
    
    // Default column widths for consistent HStack alignment
    private func columnWidth(for col: String) -> CGFloat {
        if let userSet = customColumnWidths[col] { return userSet }
        switch col {
        case "File Names": return 250
        case "VFX Name", "Original VFX Name": return 160
        case "Reel Name": return 150
        case "TC In", "TC Out", "Source TC In", "Source TC Out": return 110
        case "Duration", "Frame Start", "Frame End": return 100
        case "Episode": return 80
        case "Scene": return 90
        default: return 120
        }
    }
    
    private var filteredIndicesCache: [Int] {
        getFilteredIndices(clips: projectManager.currentMasterList)
    }
    
    private func jumpToResolveTimecode(for clip: ClipData) {
        guard !clip.tcIn.isEmpty else { return }

        // Resolve which episode this clip belongs to, so we can open the right
        // timeline before jumping — an explicit "Episode" tag (written during
        // indexing) wins, falling back to Start-TC-range matching (same logic
        // as CSV augmentation) when that tag is missing.
        var targetEpisode: EpisodeData? = nil
        if !projectManager.currentEpisodes.isEmpty {
            let taggedNumber = Int(clip.dict["Episode"] ?? "") ?? EpisodeData.matchedEpisodeNumber(for: clip.tcIn, in: projectManager.currentEpisodes)
            if let number = taggedNumber {
                targetEpisode = projectManager.currentEpisodes.first { $0.episodeNumber == number }
            }
        }

        var payload: [String: String] = ["tc": clip.tcIn]
        if let episode = targetEpisode {
            payload["timelineUniqueId"] = episode.timelineUniqueId ?? ""
            payload["timelineName"] = episode.timelineName
        }

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        guard let jsonData = try? JSONEncoder().encode(payload) else { return }
        try? jsonData.write(to: tmpURL)

        PyScriptRunner.run(scriptName: "Resolve/Tools/navigate_to_frame", args: [tmpURL.path], showOutput: false, completion: { _ in
            try? FileManager.default.removeItem(at: tmpURL)
        })

        let script = "tell application \"DaVinci Resolve\" to activate"
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }
    
    @ViewBuilder
    private func filteredDataRows() -> some View {
        let indices = filteredIndicesCache
        
        ForEach(indices, id: \.self) { index in
            // Direct binding via projectManager
            let clipBinding = $projectManager.currentMasterList[index]
            
            HStack(spacing: 0) {
                if isEditingMasterlist {
                    Toggle("", isOn: Binding(
                        get: { selectedForDelete.contains(clipBinding.wrappedValue.id) },
                        set: { _ in handleRowSelectionClick(clipId: clipBinding.wrappedValue.id) }
                    ))
                    .labelsHidden()
                    .frame(width: 30)
                    .overlay(Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1).offset(x: 10), alignment: .trailing)
                }
                
                if hasThumbnailsCache {
                    Group {
                        if let project = projectManager.currentProject,
                           let url = getThumbnailURL(project: project, clip: clipBinding.wrappedValue) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image): image.resizable().aspectRatio(contentMode: .fit)
                                case .failure(_): Image(systemName: "photo").foregroundColor(.secondary)
                                case .empty: ProgressView().controlSize(.small)
                                @unknown default: EmptyView()
                                }
                            }
                            .frame(width: 50, height: 30)
                            .id(thumbnailRefreshID)
                        } else {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary.opacity(0.3))
                                .frame(width: 50, height: 30)
                        }
                    }
                    .frame(width: 60)
                    .overlay(Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1).offset(x: 4), alignment: .trailing)
                }
                
                let cols = activeColumns.filter { customColumnVisibility[$0] ?? true }
                ForEach(cols.indices, id: \.self) { i in
                    let col = cols[i]
                    let cellId = CellID(clipId: clipBinding.wrappedValue.id, col: col)
                    Group {
                        if isEditingMasterlist && editingCell == cellId {
                            TextField("", text: Binding(
                                get: { clipBinding.wrappedValue.dict[col] ?? "" },
                                set: { clipBinding.wrappedValue.dict[col] = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: cellId)
                            .onSubmit { editingCell = nil }
                            .onChange(of: focusedField) { newValue in
                                if newValue != cellId && editingCell == cellId {
                                    editingCell = nil
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            if col == "VFX Name", !isEditingMasterlist {
                                HStack(spacing: 4) {
                                    if let tc = clipBinding.wrappedValue.dict["TC In"], !tc.isEmpty {
                                        Button {
                                            jumpToResolveTimecode(for: clipBinding.wrappedValue)
                                        } label: {
                                            Image(systemName: "arrow.right.circle.fill")
                                                .foregroundColor(.accentColor)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Jump to this clip in DaVinci Resolve")
                                    }
                                    
                                    Text(clipBinding.wrappedValue.dict[col] ?? "")
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                            } else {
                                Text(clipBinding.wrappedValue.dict[col] ?? "")
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 4)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if isEditingMasterlist {
                                            editingCell = cellId
                                            focusedField = cellId
                                        }
                                    }
                                    .background(isEditingMasterlist && editingCell == cellId ? Color.accentColor.opacity(0.1) : Color.clear)
                            }
                        }
                    }
                    .frame(width: columnWidth(for: col), alignment: .leading)
                    .padding(.horizontal, 4)
                    .overlay(
                        Group {
                            if i < cols.count - 1 {
                                Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1)
                            }
                        },
                        alignment: .trailing
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            Divider()
        }
    }

    // MARK: - Filter Logic

    private func getDerivedScenes(clips: [ClipData]) -> [String] {
        let prefixes = clips.compactMap { clip -> String? in
            let parts = clip.vfxName.split(separator: "_")
            return parts.isEmpty ? nil : String(parts[0])
        }
        return Array(Set(prefixes)).sorted()
    }

    private func countClipsForScenePrefix(prefix: String, clips: [ClipData]) -> Int {
        return clips.filter { $0.vfxName.hasPrefix(prefix + "_") || $0.vfxName == prefix }.count
    }
    
    private var duplicateVFXNames: [String] {
        let names = projectManager.currentMasterList.map { $0.vfxName }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0 != "—" }
        var nameCounts: [String: Int] = [:]
        for name in names {
            nameCounts[name, default: 0] += 1
        }
        return nameCounts.filter { $0.value > 1 }.map { $0.key }.sorted()
    }

    // MARK: - Row Selection (Edit Masterlist mode)

    // Plain click toggles a single row; shift-click extends the selection to
    // every visible row between the last-clicked row and this one (standard
    // Finder-style range select), leaving the anchor (lastToggledClipId)
    // where it was so repeated shift-clicks keep extending from the same spot.
    private func handleRowSelectionClick(clipId: UUID) {
        if NSEvent.modifierFlags.contains(.shift), let anchorId = lastToggledClipId {
            let visibleIds = getFilteredIndices(clips: projectManager.currentMasterList).map { projectManager.currentMasterList[$0].id }
            if let anchorIdx = visibleIds.firstIndex(of: anchorId), let clickedIdx = visibleIds.firstIndex(of: clipId) {
                let range = anchorIdx <= clickedIdx ? anchorIdx...clickedIdx : clickedIdx...anchorIdx
                for i in range { selectedForDelete.insert(visibleIds[i]) }
                return
            }
        }
        if selectedForDelete.contains(clipId) {
            selectedForDelete.remove(clipId)
        } else {
            selectedForDelete.insert(clipId)
        }
        lastToggledClipId = clipId
    }

    // Overwrites `column` with `value` on every currently selected clip —
    // the Batch Editor's only operation (e.g. assign the first 10 shots to
    // Episode "1" in one step).
    private func applyBatchEdit(column: String, value: String) {
        guard !column.isEmpty else { return }
        for i in projectManager.currentMasterList.indices {
            if selectedForDelete.contains(projectManager.currentMasterList[i].id) {
                projectManager.currentMasterList[i].dict[column] = value
            }
        }
        projectManager.saveMasterList()
    }

    // Columns offered by the Batch Editor: every active column, plus "Episode"
    // even if no clip has been tagged with it yet — the whole point of batch
    // editing is often to backfill Episode assignments by hand for the first
    // time (e.g. clips indexed before Episodes were registered at all).
    private var batchEditableColumns: [String] {
        var cols = activeColumns
        if !projectManager.currentEpisodes.isEmpty && !cols.contains("Episode") {
            cols.insert("Episode", at: 0)
        }
        return cols
    }

    private func getFilteredIndices(clips: [ClipData]) -> [Int] {
        var indices = Array(clips.indices)
        
        if showOnlyDuplicates {
            let dupeNames = duplicateVFXNames
            indices = indices.filter { i in
                let name = clips[i].vfxName
                return dupeNames.contains(name)
            }
        }
        
        if let prefix = selectedScenePrefix {
            indices = indices.filter { i in
                let name = clips[i].vfxName
                return name.hasPrefix(prefix + "_") || name == prefix
            }
        }
        
        if let sortCol = sortColumn {
            indices.sort { a, b in
                let valA = clips[a].dict[sortCol] ?? ""
                let valB = clips[b].dict[sortCol] ?? ""
                
                // Try numeric sort first
                if let numA = Double(valA), let numB = Double(valB) {
                    return sortAscending ? numA < numB : numA > numB
                }
                
                // Fallback to alphabetical
                if sortAscending {
                    return valA.localizedStandardCompare(valB) == .orderedAscending
                } else {
                    return valA.localizedStandardCompare(valB) == .orderedDescending
                }
            }
        }
        
        return indices
    }
    
    private func sortList(by column: String) {
        if sortColumn == column {
            if sortAscending {
                sortAscending = false
            } else {
                sortColumn = nil // Reset to original sort
            }
        } else {
            sortColumn = column
            sortAscending = true
        }
    }
    
    private func moveColumnRight(_ col: String, direction: Int) {
        var cols = activeColumns
        guard let idx = cols.firstIndex(of: col) else { return }
        let newIdx = idx + direction
        guard newIdx >= 0 && newIdx < cols.count else { return }
        cols.swapAt(idx, newIdx)
        columnOrder = cols
    }
    
    private func filteredClipsCount(clips: [ClipData]) -> Int? {
        guard selectedScenePrefix != nil else { return nil }
        return getFilteredIndices(clips: clips).count
    }
    
    // MARK: - Indexing & Merging

    // Takes the raw CSV straight from clip-indexing.py and:
    // - drops the "Episode" column entirely if no episodes are registered
    //   (otherwise it would show up as an always-empty column)
    // - computes and adds a "Scene" column, only if scenes are registered,
    //   by matching each clip's Record TC against the registered scene ranges
    // - pins Episode (if present) then Scene (if present) directly after
    //   "Clip Name" — both in the Data Import Preview and, once merged, in
    //   the Master VFX List (activeColumns pins them there too)
    private func augmentIndexingCSV(_ rawCSV: String) -> String {
        let lines = rawCSV.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let firstLine = lines.first else { return rawCSV }
        let delimiter = CSVManager.detectDelimiter(in: firstLine)
        let rawRows = lines.map { CSVManager.parseCSVRow($0, delimiter: delimiter) }
        guard let originalHeader = rawRows.first, originalHeader.contains("Clip Name") else { return rawCSV }

        let episodesEnabled = !projectManager.currentEpisodes.isEmpty
        let scenesEnabled = !projectManager.currentScenes.isEmpty
        let recTcInIdx = originalHeader.firstIndex(of: "Rec TC In")

        // Rebuild each row as a [columnName: value] dict against the original
        // header, adding "Scene" where applicable. Rebuilding from a dict avoids
        // fragile manual index bookkeeping when the column order changes below.
        var dataDicts: [[String: String]] = []
        for row in rawRows.dropFirst() {
            var dict: [String: String] = [:]
            for (i, colName) in originalHeader.enumerated() {
                dict[colName] = i < row.count ? row[i] : ""
            }
            let tc = recTcInIdx.map { $0 < row.count ? row[$0] : "" } ?? ""
            if scenesEnabled {
                dict["Scene"] = SceneData.matchedSceneName(for: tc, in: projectManager.currentScenes) ?? ""
            }
            // clip-indexing.py already tags "Episode" exactly when it indexed the matching
            // timeline directly. Fall back to Start-TC-range matching (same idea as Scene
            // matching above) only when that exact tag is missing/empty — e.g. a plain CSV
            // import that never went through a specific timeline.
            if episodesEnabled, (dict["Episode"] ?? "").isEmpty {
                if let number = EpisodeData.matchedEpisodeNumber(for: tc, in: projectManager.currentEpisodes) {
                    dict["Episode"] = String(number)
                }
            }
            dataDicts.append(dict)
        }

        var newHeader = originalHeader.filter { $0 != "Episode" && $0 != "Scene" }
        guard let clipNameIdx = newHeader.firstIndex(of: "Clip Name") else { return rawCSV }
        var insertAt = clipNameIdx + 1
        if episodesEnabled {
            newHeader.insert("Episode", at: insertAt)
            insertAt += 1
        }
        if scenesEnabled {
            newHeader.insert("Scene", at: insertAt)
        }

        var csv = newHeader.map { CSVManager.escape($0) }.joined(separator: ",") + "\n"
        for dict in dataDicts {
            let row = newHeader.map { CSVManager.escape(dict[$0] ?? "") }
            csv += row.joined(separator: ",") + "\n"
        }
        return csv
    }

    private func startMergeReview(importedClips: [ClipData], markers: [MarkerData]) {
        guard let project = projectManager.currentProject else { return }
        let preprocessed = projectManager.prepareImportedClips(importedClips, projectId: project.id)
        
        self.pendingImportedClips = preprocessed
        self.pendingMergeItems = MergeManager.compare(master: projectManager.currentMasterList, imported: preprocessed, mergeKey: currentMergeKey)
        self.pendingSceneMarkers = markers
        self.showMergeReview = true
    }
    
    private func runIndexing(project: Project, allEpisodes: Bool = false) {
        isIndexing = true
        loadingMessage = allEpisodes ? "Connecting to Resolve... (indexing all episodes)" : "Connecting to Resolve..."

        projectManager.updateVfxTrack(projectId: project.id, track: vfxTrack)
        let endMarkerArg = project.vfxEndMarkerEnabled == true ? "true" : "false"

        var renamingMapArg = ""
        if let map = project.vfxRenamingMap, !map.isEmpty {
            do {
                let data = try JSONEncoder().encode(map)
                let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("resolver_renaming_map.json")
                try data.write(to: tmpURL)
                renamingMapArg = tmpURL.path
            } catch { print("Failed to encode map") }
        }

        // Episode mapping: lets the indexing script tag every clip with the
        // Episode number of whichever registered timeline is currently being
        // indexed (single-timeline mode), or resolve every registered
        // timeline by uniqueId/name to auto-open + index them all in turn
        // ("Index All Episodes" mode, see clip-indexing.py's find_timeline).
        var episodesMapArg = ""
        if !projectManager.currentEpisodes.isEmpty {
            let mapping = projectManager.currentEpisodes.map { ["timelineName": $0.timelineName, "timelineUniqueId": $0.timelineUniqueId ?? "", "episodeNumber": $0.episodeNumber] as [String: Any] }
            do {
                let data = try JSONSerialization.data(withJSONObject: mapping)
                let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("resolver_episodes_map.json")
                try data.write(to: tmpURL)
                episodesMapArg = tmpURL.path
            } catch { print("Failed to encode episodes map") }
        }
        let allEpisodesArg = allEpisodes ? "true" : "false"

        // Always pass positionally (empty string when unused) so argument
        // indices in the Python script never shift depending on which
        // optional features are active.
        let args = [vfxTrack, endMarkerArg, renamingMapArg, episodesMapArg, allEpisodesArg]

        PyScriptRunner.run(scriptName: "Resolve/VFX/clip-indexing", args: args, showOutput: false, onProgress: { progressLine in
            if let range = progressLine.range(of: "PROGRESS: ") {
                let valueStr = String(progressLine[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = valueStr.components(separatedBy: "/")
                if parts.count == 2, let current = Int(parts[0]), let total = Int(parts[1]) {
                     DispatchQueue.main.async {
                         self.indexingCurrent = current
                         self.indexingTotal = total
                         if total > 0 { self.indexingProgress = Double(current) / Double(total) }
                     }
                }
            }
        }) { output in
            DispatchQueue.main.async {
                self.isIndexing = false
                self.loadingMessage = ""
                guard let output = output else { return }
                
                // Write CSV output to a temporary file
                do {
                    let augmented = self.augmentIndexingCSV(output)
                    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("davinci_import.csv")
                    try augmented.write(to: tmpURL, atomically: true, encoding: .utf8)
                    
                    // Launch CSV Import Window
                    CSVImportView.showStandalone(url: tmpURL) { importedClips in
                        self.startMergeReview(importedClips: importedClips, markers: [])
                    }
                } catch {
                    self.indexingErrorMessage = "Failed to process indexing data: \(error.localizedDescription)"
                    self.showIndexingError = true
                }
            }
        }
    }
    
    // MARK: - Extracted Tool Logic (Batch Ops, Thumbnails, Exports)
    private func performPreflightAndRunBatchOp(type: String, action: String, project: Project) {
        DaVinciChecker.performPreflightCheck { diag in
            if let diag = diag, diag.success {
                performBatchOp(type: type, action: action, project: project)
            } else {
                showIndexingError = true
                indexingErrorMessage = diag != nil ? DaVinciChecker.formatError(diagnostic: diag!) : "DaVinci Check Failed"
            }
        }
    }
    
    private func performBatchOp(type: String, action: String, project: Project) {
        var actionToRun = action
        // Omited for brevity/reusability. You will need to rewrite the body slightly to use `project.sceneMarkers` instead of `run.sceneMarkers` and `projectManager.currentMasterList` instead of `run.clips`.
        var markers: [MarkerData] = []
        let clips = projectManager.currentMasterList
        
        if type == "scene" {
            let scenes = projectManager.currentScenes
            if scenes.isEmpty { return }
            markers = scenes.map { scene in
                MarkerData(frameId: 0, color: "Cream", name: scene.name, note: "Resolver-Scene-Marker", duration: 1, tc: scene.startTC)
            }
        } else if type == "vfx" {
            if action == "delete" {
                // Deletion will now be handled inside the script by scanning all markers for "Resolver VFX-Marker"
                actionToRun = "delete_all_vfx"
            } else {
                for clip in clips {
                    let tc = clip.tcIn
                    if tc.isEmpty { continue }
                    markers.append(MarkerData(frameId: 0, color: "Green", name: clip.vfxName, note: "Resolver VFX-Marker", duration: 1, tc: tc))
                }
            }
        } else if type == "groups" {
            // For groups, we pass the vfxName, tcIn, and tcOut using MarkerData structure as a generic transport
            for clip in clips {
                if clip.tcIn.isEmpty || clip.tcOut.isEmpty { continue }
                markers.append(MarkerData(frameId: 0, color: "Group", name: clip.vfxName, note: clip.tcOut, duration: 1, tc: clip.tcIn))
            }
        }
        
        struct BatchPayload: Codable { let action: String; let markers: [MarkerData] }
        let payload = BatchPayload(action: actionToRun, markers: markers)
        
        do {
            let data = try JSONEncoder().encode(payload)
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("resolver_batch_ops.json")
            try data.write(to: tmpURL)
            
            if type == "groups" {
                PyScriptRunner.run(scriptName: "Resolve/VFX/clip-grouping", args: [tmpURL.path], showOutput: false, enableDownload: false, completion: { _ in })
            } else {
                PyScriptRunner.run(scriptName: "Resolve/Tools/batch_marker_op", args: [tmpURL.path], showOutput: false, enableDownload: false, completion: { _ in })
            }
        } catch { ConsoleLogger.shared.log("Batch Op Error: \(error)") }
    }
    
    private func generateThumbnails(project: Project) {
        isProcessing = true
        let clips = projectManager.currentMasterList
        
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let thumbnailsDir = appSupport.appendingPathComponent("com.skyks030.Resolver").appendingPathComponent("Thumbnails").appendingPathComponent(project.id.uuidString)
            
        try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
        
        let targetTrack = Int(self.vfxThumbnailTrack) ?? 1
        let clipsData = clips.map { ["name": $0.vfxName, "tc": $0.tcIn, "frameStart": String($0.frameStart ?? 0), "frameEnd": String($0.frameEnd ?? 0)] }
        
        let payload: [String: Any] = ["outputDir": thumbnailsDir.path, "targetTrack": targetTrack, "clips": clipsData, "format": thumbnailFormat, "resizeHeight": thumbnailHeight]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("resolver_thumbnails.json")
            try data.write(to: tmpURL)
            
            PyScriptRunner.run(scriptName: "Resolve/VFX/generate-thumbnails", args: [tmpURL.path], showOutput: false, onProgress: { _ in }) { _ in
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.thumbnailRefreshID = UUID()
                    self.hasThumbnailsCache = true
                }
            }
        } catch { isProcessing = false }
    }

    private func deleteThumbnails(project: Project) {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let projectThumbnailsDir = appSupport.appendingPathComponent("com.skyks030.Resolver").appendingPathComponent("Thumbnails").appendingPathComponent(project.id.uuidString)
        try? FileManager.default.removeItem(at: projectThumbnailsDir)
        DispatchQueue.main.async { 
            self.thumbnailRefreshID = UUID() 
            self.hasThumbnailsCache = false
        }
    }
    
    // MARK: - Scene Marker Import from DaVinci
    
    private func hasThumbnails() -> Bool {
        guard let project = projectManager.currentProject,
              let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return false }
        let dirURL = appSupport.appendingPathComponent("com.skyks030.Resolver").appendingPathComponent("Thumbnails").appendingPathComponent(project.id.uuidString)
        if let files = try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) {
            return !files.isEmpty
        }
        return false
    }

    private func getThumbnailURL(project: Project, clip: ClipData) -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dirURL = appSupport.appendingPathComponent("com.skyks030.Resolver").appendingPathComponent("Thumbnails").appendingPathComponent(project.id.uuidString)
            
        do {
            let files = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
            return files.first(where: { $0.lastPathComponent.contains(clip.vfxName) })
        } catch { return nil }
    }

    private func exportCSV(project: Project) {
        // Just use CSVManager
        let panel = NSSavePanel()
        panel.title = "Export Master List CSV"
        panel.allowedContentTypes = [.commaSeparatedText]
        let dateStr = Formatter.filename.string(from: Date())
        panel.nameFieldStringValue = "\(project.name)_Master_\(dateStr).csv"
        
        if panel.runModal() == .OK, let url = panel.url {
            try? CSVManager.write(clips: projectManager.currentMasterList, to: url)
        }
    }
    
    private func exportExcel(project: Project) {
        let panel = NSSavePanel()
        panel.title = "Export Master List Excel"
        if let excelType = UTType(filenameExtension: "xlsx") {
            panel.allowedContentTypes = [excelType]
        }
        let dateStr = Formatter.filename.string(from: Date())
        panel.nameFieldStringValue = "\(project.name)_Master_\(dateStr).xlsx"
        
        if panel.runModal() == .OK, let destinationURL = panel.url {
            isProcessing = true
            loadingMessage = "Generating Excel File..."
            
            var headers = ["Thumbnail"]
            headers.append(contentsOf: activeColumns)
            
            var clipsData = [[String: String]]()
            for clip in projectManager.currentMasterList {
                var clipDict = clip.dict
                if let thumbURL = getThumbnailURL(project: project, clip: clip) {
                    clipDict["Thumbnail"] = thumbURL.path
                } else {
                    clipDict["Thumbnail"] = ""
                }
                clipsData.append(clipDict)
            }
            
            let tmpExcelURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xlsx")
            let payload: [String: Any] = [
                "outputPath": tmpExcelURL.path,
                "headers": headers,
                "clips": clipsData
            ]
            
            do {
                let data = try JSONSerialization.data(withJSONObject: payload)
                let tmpPayloadURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
                try data.write(to: tmpPayloadURL)
                
                PyScriptRunner.run(scriptName: "Resolve/Tools/export_excel", args: [tmpPayloadURL.path], showOutput: false, completion: { _ in
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.loadingMessage = ""
                        
                        if FileManager.default.fileExists(atPath: tmpExcelURL.path) {
                            do {
                                if FileManager.default.fileExists(atPath: destinationURL.path) {
                                    try FileManager.default.removeItem(at: destinationURL)
                                }
                                try FileManager.default.moveItem(at: tmpExcelURL, to: destinationURL)
                            } catch {
                                self.showIndexingError = true
                                self.indexingErrorMessage = "Failed to save Excel file: \(error.localizedDescription)"
                            }
                        } else {
                            self.showIndexingError = true
                            self.indexingErrorMessage = "Python script failed to generate the Excel file. Is xlsxwriter installed?"
                        }
                        try? FileManager.default.removeItem(at: tmpPayloadURL)
                    }
                })
            } catch {
                isProcessing = false
                loadingMessage = ""
                showIndexingError = true
                indexingErrorMessage = "Failed to serialize Excel payload: \(error.localizedDescription)"
            }
        }
    }
    
    private func finishHeaderEditing() {
        guard let oldCol = editingHeader else { return }
        let trimmed = headerEditText.trimmingCharacters(in: .whitespaces)
        
        if !trimmed.isEmpty && trimmed != oldCol && !availableCustomColumns.contains(trimmed) {
            for i in 0..<projectManager.currentMasterList.count {
                if let val = projectManager.currentMasterList[i].dict[oldCol] {
                    projectManager.currentMasterList[i].dict[trimmed] = val
                    projectManager.currentMasterList[i].dict.removeValue(forKey: oldCol)
                } else {
                    projectManager.currentMasterList[i].dict[trimmed] = ""
                }
            }
            projectManager.saveMasterList()
            
            if let idx = columnOrder.firstIndex(of: oldCol) { columnOrder[idx] = trimmed }
            if customColumnVisibility[oldCol] == true { customColumnVisibility[trimmed] = true }
            customColumnVisibility.removeValue(forKey: oldCol)
            if sortColumn == oldCol { sortColumn = trimmed }
        }
        editingHeader = nil
        focusedHeader = nil
    }
}

// MARK: - Drag & Drop Logic for Columns
struct ColumnDropDelegate: DropDelegate {
    let item: String
    @Binding var items: [String]
    @Binding var draggedItem: String?
    let activeColumns: [String]
    let fixedColumns: [String]
    let onReorder: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedItem, draggedItem != item,
              let from = items.firstIndex(of: draggedItem) else { return }

        // Protect fixed columns
        if fixedColumns.contains(draggedItem) { return }
        if fixedColumns.contains(item) { return }

        // Since UI maps over activeColumns, 'item' is the target column name
        if let to = items.firstIndex(of: item), items[to] != draggedItem {
            withAnimation(.default) {
                items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
            onReorder()
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
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
