import SwiftUI
import UniformTypeIdentifiers

struct ProjectExportView: View {
    @EnvironmentObject var projectManager: ProjectManager
    // Undo/Redo: this window's UndoManager, handed off to projectManager so every mutating
    // method/view (including the sheets presented from this window) can register undo actions
    // through it — see ProjectManager.registerUndo.
    @Environment(\.undoManager) private var undoManager
    // Filter Manager: a per-column "contains" search, AND-combined across every column that has
    // a value set. `isFilterActive` is the Filter button's own on/off state — filters stay
    // configured in `columnFilters` even while switched off, so turning the button back on
    // re-applies them without retyping anything.
    @State private var isFilterActive: Bool = false
    @State private var columnFilters: [String: String] = [:]
    @State private var showFilterManager: Bool = false
    
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
    // Snapshot of the master list taken the moment a cell starts editing, so the undo action
    // registered when editing ends restores the value from before this edit — not one keystroke
    // at a time (the TextField mutates the model live on every keystroke).
    @State private var cellEditSnapshot: [ClipData]? = nil
    @State private var showDeleteShotsAlert = false
    @State private var editingHeader: String? = nil
    @FocusState private var focusedHeader: String?
    @State private var headerEditText: String = ""
    @State private var showDeleteColumnAlert = false
    @State private var columnToDelete = ""
    
    @State private var showMergeReview = false
    @State private var pendingMergeItems: [MergeItem] = []
    @State private var pendingSceneMarkers: [MarkerData] = []
    @State private var pendingIgnoredDiffKeys: Set<String> = []
    @State private var pendingReviewWindowSize: CGSize = CGSize(width: 1200, height: 800)
    @State private var mergeReviewApplyProgress: SyncApplyProgress? = nil
    // Only a real DaVinci Resolve index run's TC values are guaranteed to still correspond to
    // Resolve's current project state — a hand-picked CSV might be old, edited, or from a
    // different project entirely, so "jump to this shot in Resolve" only ever offers itself for
    // that one review context (see SyncReviewView.onJumpToClip).
    @State private var pendingReviewFromDaVinciIndex = false
    
    // Scene Manager & Generator States
    @State private var showSceneManager = false
    @State private var showEpisodeManager = false
    @State private var showVfxNameGenerator = false
    
    // Import State
    @State private var showCSVImport = false
    @State private var showDaVinciImport = false
    @State private var showThumbnailImport = false
    @State private var showThumbnailShotPicker = false
    @State private var thumbnailsAllShots = true
    @State private var selectedThumbnailClipIds: Set<UUID> = []
    @State private var showImportDataSheet = false
    @State private var showExportDataSheet = false
    @State private var showSheetSync = false
    
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
        // "Episode"/"Scene" show up as soon as at least one is registered, even before any clip
        // has actually been tagged with one — e.g. right after setting up Episodes/Scenes, before
        // ever indexing, so they're immediately available to fill in by hand (including via Batch
        // Edit) rather than only appearing after the fact.
        if !projectManager.currentEpisodes.isEmpty { keys.insert("Episode") }
        if !projectManager.currentScenes.isEmpty { keys.insert("Scene") }
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
    @State private var isRunningBatchOp = false
    @State private var loadingMessage = ""
    @State private var indexingProgress: Double = 0.0
    @State private var indexingTotal: Int = 0
    @State private var indexingCurrent: Int = 0
    
    // VFX Indexing State
    @State private var vfxTrack: String = "1"
    @State private var indexAllEpisodes: Bool = false

    // Thumbnails: which frame within each shot to grab, and the resize height — both remembered
    // per-project (see Project.vfxThumbnailFramePosition/vfxThumbnailScaleHeight), loaded on
    // appear/project switch below. No more source-track selection — thumbnails are grabbed from
    // the timeline exactly as it currently looks (see ThumbnailImportSheet).
    @State private var thumbnailFramePosition: ThumbnailFramePosition = .start
    @State private var thumbnailScaleHeight: Int = 512

    // Settings
    @AppStorage("thumbnailFormat") private var thumbnailFormat: String = "jpg"
    @AppStorage("thumbnailHeight") private var thumbnailHeight: Int = standardThumbnailHeight

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
                        // Filter button — the main area toggles whether the configured filters
                        // are applied at all; the "…" opens the Filter Manager to configure them.
                        HStack(spacing: 0) {
                            Button {
                                isFilterActive.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "line.3.horizontal.decrease.circle\(isFilterActive ? ".fill" : "")")
                                    Text("Filter")
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .help(isFilterActive ? "Filters are applied — click to show the full list" : "Click to apply the filters configured in the Filter Manager")

                            Divider().frame(height: 14)

                            Button {
                                showFilterManager = true
                            } label: {
                                Image(systemName: "ellipsis")
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .help("Configure filters")
                        }
                        .background(isFilterActive ? Color.accentColor.opacity(0.18) : Color.clear)
                        .liquidGlassPanel(cornerRadius: 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(isFilterActive ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                        .fixedSize()

                        // Columns visibility — a separate concern from row filtering above.
                        Menu {
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
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "slider.horizontal.3")
                                Text("Columns")
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
                            commitEditingCell()
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
            if isIndexing || isProcessing || isRunningBatchOp {
                LoadingOverlay(
                    message: loadingMessage.isEmpty ? (isIndexing ? "Indexing VFX Clips..." : "Processing...") : loadingMessage,
                    progress: indexingProgress,
                    current: indexingCurrent,
                    total: indexingTotal
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
                let oldList = projectManager.currentMasterList
                let deletedCount = selectedForDelete.count
                projectManager.currentMasterList.removeAll { selectedForDelete.contains($0.id) }
                projectManager.saveMasterList()
                projectManager.registerUndo(\.currentMasterList, actionName: "Delete \(deletedCount) Shot\(deletedCount == 1 ? "" : "s")", from: oldList) {
                    self.projectManager.saveMasterList()
                }
                selectedForDelete.removeAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete the selected \(selectedForDelete.count) VFX shots? You can undo this with ⌘Z.")
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
            mergeReviewSheet
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
                framePosition: $thumbnailFramePosition,
                scaleHeight: $thumbnailScaleHeight,
                allShots: $thumbnailsAllShots,
                selectedShotCount: selectedThumbnailClipIds.count,
                hasExistingThumbnails: hasThumbnailsCache,
                onPickShots: {
                    showThumbnailShotPicker = true
                },
                onStart: {
                    showThumbnailImport = false
                    DaVinciChecker.performPreflightCheck { diag in
                        if let diag = diag, diag.success {
                            if let project = projectManager.currentProject {
                                projectManager.updateVfxThumbnailFramePosition(projectId: project.id, position: thumbnailFramePosition.rawValue)
                                projectManager.updateVfxThumbnailScale(projectId: project.id, height: thumbnailScaleHeight)
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
            .sheet(isPresented: $showThumbnailShotPicker) {
                ThumbnailShotPickerSheet(
                    clips: projectManager.currentMasterList,
                    selectedIds: $selectedThumbnailClipIds,
                    onCancel: {
                        // Backing out of picking specific shots with none chosen goes back to "all".
                        if selectedThumbnailClipIds.isEmpty { thumbnailsAllShots = true }
                        showThumbnailShotPicker = false
                    }
                )
            }
        }
        
        // Scene Management Sheet
        .sheet(isPresented: $showSceneManager) {
            SceneManagementView(project: projectManager.currentProject!)
        }

        // Episode Management Sheet
        .sheet(isPresented: $showEpisodeManager) {
            EpisodeManagementView(project: projectManager.currentProject!)
        }

        // Sheet Sync (Excel Online / Google Sheets)
        .sheet(isPresented: $showSheetSync) {
            SheetSyncView(project: projectManager.currentProject!)
        }

        // VFX Name Generator Sheet
        .sheet(isPresented: $showVfxNameGenerator) {
            VfxNameGeneratorView(project: projectManager.currentProject!)
        }

        // Filter Manager
        .sheet(isPresented: $showFilterManager) {
            FilterManagerSheet(columns: activeColumns, filters: $columnFilters, isActive: $isFilterActive)
        }
        
        .onAppear {
            if let project = projectManager.currentProject {
                vfxTrack = project.vfxTrackIndex ?? "1"
                thumbnailFramePosition = ThumbnailFramePosition(rawValue: project.vfxThumbnailFramePosition ?? "") ?? .start
                thumbnailScaleHeight = project.vfxThumbnailScaleHeight ?? thumbnailHeight
                hasThumbnailsCache = hasThumbnails()
            }
            projectManager.undoManager = undoManager
        }
        .onChange(of: projectManager.currentProject?.id) { _ in
            if let project = projectManager.currentProject {
                vfxTrack = project.vfxTrackIndex ?? "1"
                thumbnailFramePosition = ThumbnailFramePosition(rawValue: project.vfxThumbnailFramePosition ?? "") ?? .start
                thumbnailScaleHeight = project.vfxThumbnailScaleHeight ?? thumbnailHeight
                // Column filters reference this project's own column names — clear them rather
                // than risk silently hiding everything in a different project that doesn't have
                // the same custom columns.
                isFilterActive = false
                columnFilters = [:]
                hasThumbnailsCache = hasThumbnails()
            }
        }
        .onChange(of: undoManager) { newValue in
            projectManager.undoManager = newValue
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

                Button { showSheetSync = true } label: { Label("Sheet Sync", systemImage: "arrow.triangle.2.circlepath").fixedSize() }
                .liquidGlassButton(prominent: false)
                .controlSize(.large)
                .fixedSize()
            }
            .layoutPriority(2) // Ensure these don't get squished
            
            Spacer(minLength: 16)
            
            // RIGHT: Batch Actions (Naming & Deletion handled by Edit Mode)
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 8) {
                    batchToggleButton(title: "Scene Markers", icon: "mappin.and.ellipse", isActive: project.sceneMarkersActive == true, type: "scene", project: project)
                    batchToggleButton(title: "VFX Markers", icon: "mappin.and.ellipse", isActive: project.vfxMarkersActive == true, type: "vfx", project: project)
                    batchToggleButton(title: "Groups", icon: "paintpalette", isActive: project.colorGroupsActive == true, type: "groups", project: project)
                }
            }

        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // A single on/off button: gray when the corresponding *Active flag on Project is off, accent
    // (prominent) when on. Off → on runs "create"; on → off runs "delete". Disabled while any
    // batch op is already running so double-clicks can't race two Resolve calls at once.
    @ViewBuilder
    private func batchToggleButton(title: String, icon: String, isActive: Bool, type: String, project: Project) -> some View {
        Button {
            performPreflightAndRunBatchOp(type: type, action: isActive ? "delete" : "create", project: project)
        } label: {
            Label(title, systemImage: icon)
        }
        .liquidGlassButton(prominent: isActive)
        .controlSize(.small)
        .fixedSize()
        .disabled(isRunningBatchOp)
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

                    let oldList = projectManager.currentMasterList
                    if !projectManager.currentMasterList.isEmpty {
                        for i in 0..<projectManager.currentMasterList.count {
                            projectManager.currentMasterList[i].dict[newName] = ""
                        }
                    }
                    projectManager.saveMasterList()
                    projectManager.registerUndo(\.currentMasterList, actionName: "Add Column", from: oldList) {
                        self.projectManager.saveMasterList()
                    }
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
                    let oldList = projectManager.currentMasterList
                    projectManager.currentMasterList.append(newClip)
                    projectManager.saveMasterList() // so it persists instantly
                    projectManager.registerUndo(\.currentMasterList, actionName: "Add Clip", from: oldList) {
                        self.projectManager.saveMasterList()
                    }
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
                    batchEditColumn = activeColumns.first ?? ""
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
                        if let key = clip.originalVfxName {
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
                    columns: activeColumns,
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
    
    // MARK: - Undo/Redo: cell editing

    // Begins editing a cell, remembering the master list as it was right before — this is what
    // the undo action registered in commitEditingCell() restores to, so a whole edit (however
    // many keystrokes) undoes in one step rather than one character at a time.
    private func beginEditingCell(_ id: CellID) {
        cellEditSnapshot = projectManager.currentMasterList
        editingCell = id
        focusedField = id
    }

    // Ends editing (submit, losing focus, or tapping outside) and registers the undo step, but
    // only if the value actually changed — clicking into a cell and back out without typing
    // anything shouldn't leave a no-op entry on the undo stack.
    private func commitEditingCell() {
        if let snapshot = cellEditSnapshot, snapshot != projectManager.currentMasterList {
            // Editing "TC In" (including on a freshly-added, previously TC-less clip) keeps that
            // one clip's Episode/Scene assignment in sync with its Record TC — the same
            // range-matching the Episode/Scene Managers' "OK" button recomputes in bulk, and that
            // indexing/import already applies as a fallback. Folded into this same undo step, so
            // undoing the TC edit reverts the resulting Episode/Scene change with it.
            if let cellId = editingCell, cellId.col == "TC In",
               let idx = projectManager.currentMasterList.firstIndex(where: { $0.id == cellId.clipId }) {
                let tc = projectManager.currentMasterList[idx].tcIn
                if !projectManager.currentEpisodes.isEmpty, let number = EpisodeData.matchedEpisodeNumber(for: tc, in: projectManager.currentEpisodes) {
                    projectManager.currentMasterList[idx].dict["Episode"] = String(number)
                }
                if !projectManager.currentScenes.isEmpty, let name = SceneData.matchedSceneName(for: tc, in: projectManager.currentScenes) {
                    projectManager.currentMasterList[idx].dict["Scene"] = name
                }
            }
            projectManager.saveMasterList()
            projectManager.registerUndo(\.currentMasterList, actionName: "Edit Cell", from: snapshot) {
                self.projectManager.saveMasterList()
            }
        }
        cellEditSnapshot = nil
        editingCell = nil
    }

    // Resolves which registered episode a given Record TC (optionally with an explicit "Episode"
    // tag, e.g. from a clip's dict) belongs to, so callers can open the right timeline before
    // acting on it — a Resolve position jump, a marker, a color group, a thumbnail grab. An
    // explicit tag wins; otherwise falls back to Start-TC-range matching (same logic used for CSV
    // augmentation). Returns nil when no episodes are registered, or none match.
    private func resolveTargetEpisode(for tc: String, explicitEpisodeTag: String? = nil) -> EpisodeData? {
        guard !projectManager.currentEpisodes.isEmpty else { return nil }
        let taggedNumber = explicitEpisodeTag.flatMap { Int($0) } ?? EpisodeData.matchedEpisodeNumber(for: tc, in: projectManager.currentEpisodes)
        guard let number = taggedNumber else { return nil }
        return projectManager.currentEpisodes.first { $0.episodeNumber == number }
    }

    private func jumpToResolveTimecode(for clip: ClipData) {
        guard !clip.tcIn.isEmpty else { return }

        let targetEpisode = resolveTargetEpisode(for: clip.tcIn, explicitEpisodeTag: clip.dict["Episode"])

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
                            .onSubmit { commitEditingCell() }
                            .onChange(of: focusedField) { newValue in
                                if newValue != cellId && editingCell == cellId {
                                    commitEditingCell()
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
                                            beginEditingCell(cellId)
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

                if clipBinding.wrappedValue.isRemoved {
                    Button("Restore") { restoreRemovedClip(id: clipBinding.wrappedValue.id) }
                        .controlSize(.small)
                        .font(.caption)
                        .padding(.leading, 8)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .strikethrough(clipBinding.wrappedValue.isRemoved)
            .opacity(clipBinding.wrappedValue.isRemoved ? 0.5 : 1.0)
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
        let oldList = projectManager.currentMasterList
        for i in projectManager.currentMasterList.indices {
            if selectedForDelete.contains(projectManager.currentMasterList[i].id) {
                projectManager.currentMasterList[i].dict[column] = value
            }
        }
        projectManager.saveMasterList()
        projectManager.registerUndo(\.currentMasterList, actionName: "Batch Edit \(column)", from: oldList) {
            self.projectManager.saveMasterList()
        }
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
        
        if isFilterActive {
            for (col, needle) in columnFilters {
                let trimmed = needle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                indices = indices.filter { i in
                    (clips[i].dict[col] ?? "").localizedCaseInsensitiveContains(trimmed)
                }
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
        guard isFilterActive else { return nil }
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

        // clip-indexing.py's raw column names don't all match ClipData's well-known dict keys —
        // this used to get fixed up by CSVImportView's own header auto-map on the way through the
        // (now-skipped, see startMergeReview) CSV Import Manager window. Doing it here instead
        // keeps every DaVinci-indexed clip's TC In/Out and File Names actually populated.
        let headerRenames: [String: String] = [
            "Rec TC In": "TC In",
            "Rec TC Out": "TC Out",
            "File Name": "File Names",
        ]

        // Rebuild each row as a [columnName: value] dict against the original
        // header, adding "Scene" where applicable. Rebuilding from a dict avoids
        // fragile manual index bookkeeping when the column order changes below.
        var dataDicts: [[String: String]] = []
        for row in rawRows.dropFirst() {
            var dict: [String: String] = [:]
            for (i, colName) in originalHeader.enumerated() {
                dict[headerRenames[colName] ?? colName] = i < row.count ? row[i] : ""
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

        var newHeader = originalHeader.map { headerRenames[$0] ?? $0 }.filter { $0 != "Episode" && $0 != "Scene" }
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

    /// Reverses a "Mark Removed" decision made in the sync review window — the row was only ever
    /// flagged, never deleted, so this just clears the flag again.
    private func restoreRemovedClip(id: UUID) {
        guard let idx = projectManager.currentMasterList.firstIndex(where: { $0.id == id }) else { return }
        let oldList = projectManager.currentMasterList
        projectManager.currentMasterList[idx].isRemoved = false
        projectManager.saveMasterList()
        projectManager.registerUndo(\.currentMasterList, actionName: "Restore Shot", from: oldList) {
            self.projectManager.saveMasterList()
        }
    }

    // Pulled out of `body` — inlined, one more argument here was enough to push the main view's
    // modifier chain past the type checker's inference budget ("unable to type-check this
    // expression in reasonable time").
    @ViewBuilder
    private var mergeReviewSheet: some View {
        SyncReviewView(
            mergeItems: $pendingMergeItems,
            allMasterClips: projectManager.currentMasterList,
            sourceLabel: "DaVinci Resolve / CSV Import",
            supportsPush: false,
            ignoredDiffKeys: pendingIgnoredDiffKeys,
            preferredSize: pendingReviewWindowSize,
            applyProgress: $mergeReviewApplyProgress,
            onJumpToClip: pendingReviewFromDaVinciIndex ? { clip in jumpToClipInResolve(clip) } : nil,
            onApply: {
                Task {
                    let oldList = projectManager.currentMasterList
                    var newMaster = projectManager.currentMasterList
                    mergeReviewApplyProgress = SyncApplyProgress(current: 0, total: pendingMergeItems.count, label: "Applying to VFX Master List…")
                    await MergeManager.applyMergeWithProgress(master: &newMaster, mergeItems: pendingMergeItems) { current, total in
                        mergeReviewApplyProgress = SyncApplyProgress(current: current, total: total, label: "Applying to VFX Master List…")
                    }

                    // Only pass markers if it was a Resolve Index (not a CSV import)
                    if !pendingSceneMarkers.isEmpty {
                        projectManager.updateMasterList(with: newMaster, sceneMarkers: pendingSceneMarkers)
                    } else {
                        projectManager.updateMasterList(with: newMaster)
                    }
                    projectManager.registerUndo(\.currentMasterList, actionName: "Import Merge", from: oldList) {
                        self.projectManager.saveMasterList()
                    }

                    mergeReviewApplyProgress = nil
                    showMergeReview = false
                }
            },
            onCancel: {
                showMergeReview = false
            }
        )
    }

    private func startMergeReview(importedClips: [ClipData], markers: [MarkerData], isFromDaVinciIndex: Bool = false) {
        guard let project = projectManager.currentProject else { return }
        let preprocessed = projectManager.prepareImportedClips(importedClips, projectId: project.id)

        let master = projectManager.currentMasterList

        // DaVinci Resolve has no concept of a VFX Name — it's assigned entirely inside Resolver
        // (VFX Name Generator / manual rename), never something an index can read back. Without
        // this, every single indexed shot would show a bogus "VFX Name" conflict against its real
        // master-list name. The same logic generalizes to *any* master-list column an index run
        // simply never carries at all — e.g. a custom "Description" column from a prior CSV
        // import — those would otherwise show a permanent, never-resolvable-feeling discrepancy
        // on every single shot forever, since nothing about a DaVinci index could ever supply a
        // value for them. Computed as "every master column not present on any freshly-imported
        // clip" rather than a fixed list, so this covers whatever arbitrary custom columns this
        // particular master list happens to have, not just the well-known ones. A hand-picked CSV
        // import keeps full diffing — it may genuinely carry any of these columns (e.g. a
        // previously-exported master list). Sheet Sync deliberately doesn't ignore any of this
        // either — comparing a synced sheet's real values is the whole point there.
        var ignoredKeys: Set<String> = []
        if isFromDaVinciIndex {
            let importedColumns = Set(preprocessed.flatMap { $0.dict.keys })
            let masterColumns = Set(master.flatMap { $0.dict.keys })
            // "Original VFX Name" is a special case: prepareImportedClips (above) always sets it
            // to (empty) vfxName, so it's technically *present* as a key on every imported clip —
            // just always blank — and wouldn't be caught by the "absent column" rule above.
            ignoredKeys = Set(["VFX Name", "Original VFX Name", "Thumbnail Updated"])
                .union(masterColumns.subtracting(importedColumns))
        }

        var items = MergeManager.compareColumnAware(master: master, imported: preprocessed, ignoredDiffKeys: ignoredKeys)
        // DaVinci/CSV import is a one-way read of "what currently exists" — a master shot this
        // import doesn't see at all is a discrepancy too (it may have been deleted in Resolve),
        // not something to silently leave untouched.
        items += MergeManager.missingItems(master: master, mergeItems: items)

        self.pendingMergeItems = items
        self.pendingSceneMarkers = markers
        self.pendingIgnoredDiffKeys = ignoredKeys
        self.pendingReviewWindowSize = SyncReviewView.currentReferenceWindowSize()
        self.pendingReviewFromDaVinciIndex = isFromDaVinciIndex
        self.showMergeReview = true
    }

    /// SyncReviewView's onJumpToClip — moves DaVinci Resolve's playhead to this shot's saved
    /// Record TC In, switching to its registered Episode timeline first if the project uses one.
    /// Only ever wired up for a real DaVinci Resolve index review (see pendingReviewFromDaVinciIndex).
    private func jumpToClipInResolve(_ clip: ClipData) {
        let timecode = clip.tcIn
        guard !timecode.isEmpty else {
            ConsoleLogger.shared.log("⚠️ Jump to Resolve: this shot has no saved TC In to jump to.")
            return
        }
        let episode = clip.dict["Episode"] ?? ""
        let episodesMap: [[String: Any]] = projectManager.currentEpisodes.map {
            ["timelineName": $0.timelineName, "timelineUniqueId": $0.timelineUniqueId ?? "", "episodeNumber": $0.episodeNumber]
        }
        let label = clip.vfxName.isEmpty ? timecode : clip.vfxName
        ConsoleLogger.shared.log("▶️ Jumping to '\(label)' in Resolve (episode \(episode.isEmpty ? "—" : episode), TC \(timecode))")

        Task {
            do {
                try await JumpToClipRunner.jump(timecode: timecode, episode: episode, episodesMap: episodesMap)
                ConsoleLogger.shared.log("✅ Jumped to \(timecode) in Resolve")
            } catch {
                ConsoleLogger.shared.log("❌ Jump to Resolve failed: \(error)")
                self.showIndexingError = true
                self.indexingErrorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Progress reporting (shared by indexing, batch ops, thumbnails)

    // Parses a "PROGRESS: x/y" line (as printed by clip-indexing.py, clip-grouping.py,
    // batch_marker_op.py and generate-thumbnails.py) and updates the shared progress state that
    // drives the LoadingOverlay's counter. On a project with 100+ VFX shots these operations can
    // take a while, so this is what actually lets the user see how far along a run is — and,
    // since it only advances after each shot/marker is fully processed, where exactly a run got
    // stuck if it never finishes.
    private func handleProgressLine(_ progressLine: String) {
        guard let range = progressLine.range(of: "PROGRESS: ") else { return }
        let valueStr = String(progressLine[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = valueStr.components(separatedBy: "/")
        guard parts.count == 2, let current = Int(parts[0]), let total = Int(parts[1]) else { return }
        DispatchQueue.main.async {
            self.indexingCurrent = current
            self.indexingTotal = total
            if total > 0 { self.indexingProgress = Double(current) / Double(total) }
        }
    }

    private func resetProgressState() {
        indexingCurrent = 0
        indexingTotal = 0
        indexingProgress = 0
    }

    private func runIndexing(project: Project, allEpisodes: Bool = false) {
        isIndexing = true
        resetProgressState()
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

        ConsoleLogger.shared.log("▶️ Indexing starting: track=\(vfxTrack) allEpisodes=\(allEpisodes) episodes=\(projectManager.currentEpisodes.count)")
        PyScriptRunner.run(scriptName: "Resolve/VFX/clip-indexing", args: args, showOutput: false, onProgress: handleProgressLine) { output in
            DispatchQueue.main.async {
                self.isIndexing = false
                self.loadingMessage = ""
                guard let output = output, !output.isEmpty else {
                    ConsoleLogger.shared.log("❌ Indexing produced no output.")
                    self.showIndexingError = true
                    self.indexingErrorMessage = "No response from DaVinci Resolve. Check Debug Mode for details."
                    return
                }

                // clip-indexing.py's real payload always starts with this exact CSV header; any
                // other content means the run failed (validation error or crash) and must be
                // surfaced as an error rather than silently opened as if it were real import data.
                guard output.hasPrefix("Clip Name,") else {
                    ConsoleLogger.shared.log("❌ Indexing failed. Raw output:\n\(output)")
                    self.showIndexingError = true
                    if let range = output.range(of: "Fehler im Indexing-Script: ") {
                        self.indexingErrorMessage = String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        self.indexingErrorMessage = "Indexing failed. Check Debug Mode for details."
                    }
                    return
                }

                ConsoleLogger.shared.log("✅ Indexing finished, \(max(output.components(separatedBy: "\n").count - 1, 0)) row(s) received.")
                // Write CSV output to a temporary file, then feed it straight into the Sync
                // Review — this is Resolver's own generated CSV with a known, fixed column set,
                // not an arbitrary user file, so the CSV Import Manager's column-mapping step
                // (needed for a hand-picked CSV, where headers can be anything) would just be an
                // extra click for no benefit here.
                do {
                    let augmented = self.augmentIndexingCSV(output)
                    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("davinci_import.csv")
                    try augmented.write(to: tmpURL, atomically: true, encoding: .utf8)

                    let importedClips = try CSVManager.read(from: tmpURL)
                    self.startMergeReview(importedClips: importedClips, markers: [], isFromDaVinciIndex: true)
                } catch {
                    ConsoleLogger.shared.log("❌ Failed to process indexing data: \(error)")
                    self.indexingErrorMessage = "Failed to process indexing data: \(error.localizedDescription)"
                    self.showIndexingError = true
                }
            }
        }
    }
    
    // MARK: - Extracted Tool Logic (Batch Ops, Thumbnails, Exports)
    private func batchOpLoadingMessage(type: String, action: String) -> String {
        let subject: String
        switch type {
        case "scene": subject = "Scene Markers"
        case "vfx": subject = "VFX Markers"
        case "groups": subject = "Color Groups"
        default: subject = "Shots"
        }
        return (action == "delete" ? "Deleting " : "Creating ") + subject + "..."
    }

    private func performPreflightAndRunBatchOp(type: String, action: String, project: Project) {
        isRunningBatchOp = true
        resetProgressState()
        loadingMessage = batchOpLoadingMessage(type: type, action: action)
        ConsoleLogger.shared.log("▶️ Batch op starting: type=\(type) action=\(action)")
        DaVinciChecker.performPreflightCheck { diag in
            if let diag = diag, diag.success {
                performBatchOp(type: type, action: action, project: project)
            } else {
                isRunningBatchOp = false
                loadingMessage = ""
                ConsoleLogger.shared.log("❌ Batch op preflight failed: type=\(type) action=\(action)")
                showIndexingError = true
                indexingErrorMessage = diag != nil ? DaVinciChecker.formatError(diagnostic: diag!) : "DaVinci Check Failed"
            }
        }
    }

    private func performBatchOp(type: String, action: String, project: Project) {
        var actionToRun = action
        var markers: [MarkerData] = []
        let clips = projectManager.currentMasterList

        if type == "scene" {
            let scenes = projectManager.currentScenes
            if scenes.isEmpty {
                ConsoleLogger.shared.log("⚠️ Batch op (type=scene action=\(action)) aborted: no scenes registered.")
                isRunningBatchOp = false
                loadingMessage = ""
                return
            }
            markers = scenes.map { scene in
                // Which episode's timeline this scene marker belongs to, so the script can open
                // it before adding/removing the marker there (no episodes registered → nil, and
                // the script falls back to whatever timeline is currently open, as before).
                let episode = resolveTargetEpisode(for: scene.startTC)
                return MarkerData(frameId: 0, color: "Cream", name: scene.name, note: "Resolver-Scene-Marker", duration: 1, tc: scene.startTC, timelineUniqueId: episode?.timelineUniqueId, timelineName: episode?.timelineName)
            }
        } else if type == "vfx" {
            if action == "delete" {
                // Deletion is handled server-side by scanning for "Resolver VFX-Marker" notes;
                // when episodes are registered the script scans every registered timeline (see
                // the "episodes" field on the payload below), otherwise just the current one.
                actionToRun = "delete_all_vfx"
            } else {
                for clip in clips {
                    let tc = clip.tcIn
                    if tc.isEmpty { continue }
                    let episode = resolveTargetEpisode(for: tc, explicitEpisodeTag: clip.dict["Episode"])
                    markers.append(MarkerData(frameId: 0, color: "Green", name: clip.vfxName, note: "Resolver VFX-Marker", duration: 1, tc: tc, timelineUniqueId: episode?.timelineUniqueId, timelineName: episode?.timelineName))
                }
            }
        } else if type == "groups" {
            if action == "delete" {
                // Color Groups are project-level (not timeline-scoped), so deletion just needs
                // the VFX names to match against — no per-timeline info required.
                markers = clips.map { MarkerData(frameId: 0, color: "Group", name: $0.vfxName, note: "", duration: 1, tc: nil) }
            } else {
                // For groups, we pass the vfxName, tcIn, and tcOut using MarkerData structure as a generic transport
                for clip in clips {
                    if clip.tcIn.isEmpty || clip.tcOut.isEmpty { continue }
                    let episode = resolveTargetEpisode(for: clip.tcIn, explicitEpisodeTag: clip.dict["Episode"])
                    markers.append(MarkerData(frameId: 0, color: "Group", name: clip.vfxName, note: clip.tcOut, duration: 1, tc: clip.tcIn, timelineUniqueId: episode?.timelineUniqueId, timelineName: episode?.timelineName))
                }
            }
        }

        struct BatchEpisodeRef: Codable { let timelineUniqueId: String; let timelineName: String }
        struct BatchPayload: Codable { let action: String; let markers: [MarkerData]; let episodes: [BatchEpisodeRef]? }
        // Every registered episode's timeline, so "delete_all_vfx" (which has no per-marker list
        // to carry timeline hints on) knows every timeline it needs to scan.
        let episodesRef: [BatchEpisodeRef]? = projectManager.currentEpisodes.isEmpty ? nil : projectManager.currentEpisodes.map {
            BatchEpisodeRef(timelineUniqueId: $0.timelineUniqueId ?? "", timelineName: $0.timelineName)
        }
        let payload = BatchPayload(action: actionToRun, markers: markers, episodes: episodesRef)

        do {
            let data = try JSONEncoder().encode(payload)
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("resolver_batch_ops.json")
            try data.write(to: tmpURL)

            let scriptName = type == "groups" ? "Resolve/VFX/clip-grouping" : "Resolve/Tools/batch_marker_op"
            ConsoleLogger.shared.log("▶️ Running \(scriptName) for \(markers.count) shot(s)/marker(s) (action=\(actionToRun))")
            PyScriptRunner.run(scriptName: scriptName, args: [tmpURL.path], showOutput: false, enableDownload: false, onProgress: handleProgressLine, completion: { output in
                DispatchQueue.main.async {
                    self.isRunningBatchOp = false
                    self.loadingMessage = ""
                    self.handleBatchOpResult(output, type: type, action: action, project: project)
                }
            })
        } catch {
            isRunningBatchOp = false
            loadingMessage = ""
            ConsoleLogger.shared.log("❌ Batch Op Error while preparing payload: \(error)")
        }
    }

    // Only flips the toggle-button's persisted *Active flag once the script actually reports
    // success — never optimistically. On any failure, surfaces it the same way other Resolve
    // errors in this view do, and leaves the flag exactly where it was.
    private func handleBatchOpResult(_ output: String?, type: String, action: String, project: Project) {
        struct BatchOpResponse: Decodable { let status: String?; let error: String? }

        let lastJSONLine = output.flatMap { PyScriptRunner.lastJSONLine(in: $0) }

        guard let line = lastJSONLine, let data = line.data(using: .utf8),
              let response = try? JSONDecoder().decode(BatchOpResponse.self, from: data) else {
            ConsoleLogger.shared.log("❌ Batch op (type=\(type) action=\(action)) produced no parseable response. Raw output:\n\(output ?? "<nil>")")
            showIndexingError = true
            indexingErrorMessage = "No response from DaVinci Resolve."
            return
        }
        if let err = response.error {
            ConsoleLogger.shared.log("❌ Batch op (type=\(type) action=\(action)) failed: \(err)")
            showIndexingError = true
            indexingErrorMessage = err
            return
        }
        guard response.status == "success" else {
            ConsoleLogger.shared.log("❌ Batch op (type=\(type) action=\(action)) returned unexpected status: \(line)")
            showIndexingError = true
            indexingErrorMessage = "Unexpected response from DaVinci Resolve."
            return
        }

        ConsoleLogger.shared.log("✅ Batch op (type=\(type) action=\(action)) succeeded: \(line)")
        let active = (action != "delete")
        switch type {
        case "scene": projectManager.updateSceneMarkersActive(projectId: project.id, active: active)
        case "vfx": projectManager.updateVfxMarkersActive(projectId: project.id, active: active)
        case "groups": projectManager.updateColorGroupsActive(projectId: project.id, active: active)
        default: break
        }
    }
    
    private func generateThumbnails(project: Project) {
        isProcessing = true
        resetProgressState()
        // "All episodes / all shots" processes the whole master list (across every registered
        // episode's timeline); otherwise only the shots hand-picked in ThumbnailShotPickerSheet.
        let clips = thumbnailsAllShots
            ? projectManager.currentMasterList
            : projectManager.currentMasterList.filter { selectedThumbnailClipIds.contains($0.id) }
        loadingMessage = "Generating \(clips.count) Thumbnail\(clips.count == 1 ? "" : "s")..."
        indexingTotal = clips.count

        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            isProcessing = false
            loadingMessage = ""
            return
        }
        let thumbnailsDir = appSupport.appendingPathComponent("com.skyks030.Resolver").appendingPathComponent("Thumbnails").appendingPathComponent(project.id.uuidString)

        try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)

        let clipsData = clips.map { clip -> [String: String] in
            let episode = resolveTargetEpisode(for: clip.tcIn, explicitEpisodeTag: clip.dict["Episode"])
            return [
                "name": clip.vfxName,
                "tcIn": clip.tcIn,
                "tcOut": clip.tcOut,
                "timelineUniqueId": episode?.timelineUniqueId ?? "",
                "timelineName": episode?.timelineName ?? ""
            ]
        }

        let payload: [String: Any] = [
            "outputDir": thumbnailsDir.path,
            "framePosition": thumbnailFramePosition.rawValue,
            "clips": clipsData,
            "format": thumbnailFormat,
            "resizeHeight": thumbnailScaleHeight,
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("resolver_thumbnails.json")
            try data.write(to: tmpURL)

            ConsoleLogger.shared.log("▶️ Generating thumbnails for \(clips.count) shot(s) into \(thumbnailsDir.path)")
            PyScriptRunner.run(scriptName: "Resolve/VFX/generate-thumbnails", args: [tmpURL.path], showOutput: false, onProgress: handleProgressLine) { output in
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.loadingMessage = ""

                    struct ThumbnailsResponse: Decodable { let status: String?; let error: String? }
                    let lastJSONLine = output.flatMap { PyScriptRunner.lastJSONLine(in: $0) }

                    guard let line = lastJSONLine, let lineData = line.data(using: .utf8),
                          let response = try? JSONDecoder().decode(ThumbnailsResponse.self, from: lineData),
                          response.error == nil, response.status == "success" else {
                        let errMsg = lastJSONLine.flatMap { l -> String? in
                            guard let d = l.data(using: .utf8) else { return nil }
                            return (try? JSONDecoder().decode(ThumbnailsResponse.self, from: d))?.error
                        }
                        ConsoleLogger.shared.log("❌ Thumbnail generation failed: \(errMsg ?? output ?? "no response")")
                        self.showIndexingError = true
                        self.indexingErrorMessage = errMsg ?? "Thumbnail generation failed. Check Debug Mode for details."
                        return
                    }

                    ConsoleLogger.shared.log("✅ Thumbnail generation finished: \(line)")
                    self.thumbnailRefreshID = UUID()
                    self.hasThumbnailsCache = true
                    self.stampThumbnailTimestamps(for: clips, project: project)
                }
            }
        } catch {
            isProcessing = false
            loadingMessage = ""
            ConsoleLogger.shared.log("❌ Thumbnail generation error while preparing payload: \(error)")
        }
    }

    private func deleteThumbnails(project: Project) {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let projectThumbnailsDir = appSupport.appendingPathComponent("com.skyks030.Resolver").appendingPathComponent("Thumbnails").appendingPathComponent(project.id.uuidString)
        try? FileManager.default.removeItem(at: projectThumbnailsDir)

        // The files are gone — clear the now-stale "when was this last updated" stamps too,
        // rather than leave a claim on record for a thumbnail that no longer exists.
        var changed = false
        for idx in projectManager.currentMasterList.indices where !projectManager.currentMasterList[idx].thumbnailUpdatedAt.isEmpty {
            projectManager.currentMasterList[idx].thumbnailUpdatedAt = ""
            changed = true
        }
        if changed { projectManager.saveMasterList() }

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
            let files = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: [.contentModificationDateKey])
            // Exact match against the old `name.ext` scheme, or a `name_` prefix against the
            // current timestamped one — never a bare substring match, so a shot whose name is a
            // prefix of another's (e.g. "SH010" vs "SH010A") can't pick up its neighbor's file.
            let name = clip.vfxName
            let matches = files.filter { url in
                let base = url.deletingPathExtension().lastPathComponent
                return base == name || base.hasPrefix(name + "_")
            }
            // generate-thumbnails.py cleans up a clip's older files on regenerate, so this is
            // normally just one file — picking the newest is a defensive fallback, not the
            // common case.
            return matches.max { thumbnailModificationDate($0) < thumbnailModificationDate($1) }
        } catch { return nil }
    }

    private func thumbnailModificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? nil) ?? .distantPast
    }

    /// After a (re)generation run, records when each requested clip's thumbnail file was
    /// actually written — read back from the file itself (not just "we asked for it"), so a shot
    /// whose grab silently failed doesn't get a false "just updated" stamp. This is a plain text
    /// column like any other (`ClipData.thumbnailUpdatedAt`), so it flows straight into the
    /// existing Sheet Sync / Sync Review diff machinery with no special-casing needed there.
    private func stampThumbnailTimestamps(for clips: [ClipData], project: Project) {
        let formatter = ISO8601DateFormatter()
        var changed = false
        for clip in clips {
            guard let idx = projectManager.currentMasterList.firstIndex(where: { $0.id == clip.id }),
                  let url = getThumbnailURL(project: project, clip: clip) else { continue }
            let stamp = formatter.string(from: thumbnailModificationDate(url))
            if projectManager.currentMasterList[idx].thumbnailUpdatedAt != stamp {
                projectManager.currentMasterList[idx].thumbnailUpdatedAt = stamp
                changed = true
            }
        }
        if changed { projectManager.saveMasterList() }
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
            
            // Exactly the columns currently shown in the master list table, in that same order —
            // activeColumns alone ignores per-column show/hide (customColumnVisibility).
            var headers = ["Thumbnail"]
            headers.append(contentsOf: activeColumns.filter { customColumnVisibility[$0] ?? true })
            
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
            let oldList = projectManager.currentMasterList
            for i in 0..<projectManager.currentMasterList.count {
                if let val = projectManager.currentMasterList[i].dict[oldCol] {
                    projectManager.currentMasterList[i].dict[trimmed] = val
                    projectManager.currentMasterList[i].dict.removeValue(forKey: oldCol)
                } else {
                    projectManager.currentMasterList[i].dict[trimmed] = ""
                }
            }
            projectManager.saveMasterList()
            projectManager.registerUndo(\.currentMasterList, actionName: "Rename Column", from: oldList) {
                self.projectManager.saveMasterList()
            }

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
