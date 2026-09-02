import SwiftUI

struct SceneManagementView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var projectManager: ProjectManager
    let project: Project

    @State private var newSceneName = ""
    @State private var newSceneTC = "01:00:00:00"

    // Undo/Redo for inline name/TC editing: the two TextFields per row mutate the model on every
    // keystroke (they're bound directly into the array via ForEach($projectManager.currentScenes)),
    // so — same as the master list's cell editing — a snapshot is taken when a field gains focus
    // and the undo step registered only once, when it loses focus, if the value actually changed.
    private enum SceneFieldFocus: Hashable { case name(UUID), tc(UUID) }
    @FocusState private var focusedSceneField: SceneFieldFocus?
    @State private var sceneEditSnapshot: [SceneData]? = nil
    @State private var lastFocusedSceneField: SceneFieldFocus? = nil

    // DaVinci Import State
    @State private var isProcessing = false
    @State private var showIndexingWarning = false
    @State private var indexingWarningMessage = ""
    @State private var showIndexingError = false
    @State private var indexingErrorMessage = ""
    @State private var showSceneImportResult = false
    @State private var sceneImportResultMessage = ""

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Add New Scene")) {
                    HStack {
                        TextField("Scene Name (e.g., 10)", text: $newSceneName)
                        TextField("Start TC (e.g., 01:00:00:00)", text: $newSceneTC)
                        Button("Add") {
                            let trimmedName = newSceneName.trimmingCharacters(in: .whitespaces)
                            let trimmedTC = newSceneTC.trimmingCharacters(in: .whitespaces)
                            if !trimmedName.isEmpty && !trimmedTC.isEmpty {
                                let oldScenes = projectManager.currentScenes
                                let newScene = SceneData(name: trimmedName, startTC: trimmedTC)
                                projectManager.currentScenes.append(newScene)
                                projectManager.currentScenes.sort { $0.startTC < $1.startTC }
                                projectManager.saveScenes()
                                projectManager.registerUndo(\.currentScenes, actionName: "Add Scene", from: oldScenes) {
                                    self.projectManager.saveScenes()
                                }
                                newSceneName = ""
                                newSceneTC = "01:00:00:00"
                            }
                        }
                        .disabled(newSceneName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section(header: Text("Import from DaVinci Resolve")) {
                    Button(action: {
                        DaVinciChecker.performPreflightCheck { diag in
                            if let diag = diag, diag.success {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    importScenesFromDaVinci()
                                }
                            } else {
                                showIndexingError = true
                                indexingErrorMessage = diag != nil ? DaVinciChecker.formatError(diagnostic: diag!) : "DaVinci Check Failed"
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "film.stack")
                            if isProcessing {
                                Text("Importing...")
                            } else {
                                Text("Import Scene-Markers")
                            }
                        }
                    }
                    .disabled(isProcessing)
                }

                Section(header: Text("Registered Scenes"), footer: Text("Scenes must have a strictly formatted Timecode (HH:MM:SS:FF) or similarly ascending numerical value to be mapped correctly during VFX Name generation.")) {
                    if projectManager.currentScenes.isEmpty {
                        Text("No scenes registered.").foregroundColor(.secondary)
                    } else {
                        ForEach($projectManager.currentScenes) { $scene in
                            HStack {
                                TextField("Scene Name", text: $scene.name)
                                    .fontWeight(.bold)
                                    .focused($focusedSceneField, equals: .name(scene.id))
                                Divider()
                                TextField("Start TC", text: $scene.startTC)
                                    .focused($focusedSceneField, equals: .tc(scene.id))
                                Spacer()
                                Button(action: {
                                    if let idx = projectManager.currentScenes.firstIndex(where: { $0.id == scene.id }) {
                                        let oldScenes = projectManager.currentScenes
                                        projectManager.currentScenes.remove(at: idx)
                                        projectManager.saveScenes()
                                        projectManager.registerUndo(\.currentScenes, actionName: "Delete Scene", from: oldScenes) {
                                            self.projectManager.saveScenes()
                                        }
                                    }
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 8)
                            }
                            // Whenever a textfield ends editing, save implicitly! (Undo itself is
                            // registered once per edit session via the focus tracking below, not
                            // on every keystroke.)
                            .onChange(of: scene.name) { _ in projectManager.saveScenes() }
                            .onChange(of: scene.startTC) { _ in
                                // Defer re-sort to avoid reentrancy with ForEach binding
                                DispatchQueue.main.async {
                                    projectManager.currentScenes.sort { $0.startTC < $1.startTC }
                                    projectManager.saveScenes()
                                }
                            }
                        }
                        .onDelete(perform: deleteScenes)
                    }
                }
            }
            .navigationTitle("Scene Management")
            .onChange(of: focusedSceneField) { newValue in
                // Commit the undo step for whatever field was just focused, if its value changed.
                if lastFocusedSceneField != nil, let snapshot = sceneEditSnapshot, snapshot != projectManager.currentScenes {
                    projectManager.saveScenes()
                    projectManager.registerUndo(\.currentScenes, actionName: "Edit Scene", from: snapshot) {
                        self.projectManager.saveScenes()
                    }
                }
                // Start tracking the newly focused field, if any.
                sceneEditSnapshot = newValue != nil ? projectManager.currentScenes : nil
                lastFocusedSceneField = newValue
            }
            .alert("DaVinci Resolve Error", isPresented: $showIndexingError) {
                Button("OK", role: .cancel) { }
            } message: { Text(indexingErrorMessage) }
            .alert("DaVinci Resolve Info", isPresented: $showIndexingWarning) {
                Button("OK", role: .cancel) { }
            } message: { Text(indexingWarningMessage) }
            .alert("Scene Markers Import", isPresented: $showSceneImportResult) {
                Button("OK", role: .cancel) { }
            } message: { Text(sceneImportResultMessage) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { confirmAndClose() }
                        .liquidGlassButton(prominent: true)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }

    // "OK": confirms the current scene arrangement and — unlike just "Close" — propagates it into
    // the master list by recomputing every clip's "Scene" column from its Record TC against the
    // (possibly just-edited) scene Start TC ranges. A no-op on the master list if no scenes are
    // registered (recomputeSceneColumn already guards that).
    private func confirmAndClose() {
        let oldList = projectManager.currentMasterList
        projectManager.recomputeSceneColumn()
        if projectManager.currentMasterList != oldList {
            projectManager.registerUndo(\.currentMasterList, actionName: "Recompute Scenes", from: oldList) {
                self.projectManager.saveMasterList()
            }
        }
        dismiss()
    }

    private func deleteScenes(at offsets: IndexSet) {
        let oldScenes = projectManager.currentScenes
        projectManager.currentScenes.remove(atOffsets: offsets)
        projectManager.saveScenes()
        projectManager.registerUndo(\.currentScenes, actionName: "Delete Scene", from: oldScenes) {
            self.projectManager.saveScenes()
        }
    }

    private func importScenesFromDaVinci() {
        isProcessing = true
        indexingWarningMessage = "Importing Scene Markers from DaVinci Resolve..."
        showIndexingWarning = true

        PyScriptRunner.run(
            scriptName: "Resolve/VFX/export-scene-markers",
            showOutput: false,
            onProgress: { _ in }
        ) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                self.showIndexingWarning = false

                // Parse sentinel-wrapped CSV block
                let output = result ?? ""
                let lines = output.components(separatedBy: .newlines)
                var inBlock = false
                var parsed: [SceneData] = []
                var isHeader = true

                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed == "SCENES_CSV_START" { inBlock = true; continue }
                    if trimmed == "SCENES_CSV_END" { inBlock = false; continue }
                    if inBlock {
                        if isHeader { isHeader = false; continue } // skip "name,startTC" header
                        let parts = trimmed.components(separatedBy: ",")
                        if parts.count >= 2 {
                            let name = parts[0].trimmingCharacters(in: .whitespaces)
                            let tc = parts[1].trimmingCharacters(in: .whitespaces)
                            if !name.isEmpty && !tc.isEmpty {
                                parsed.append(SceneData(name: name, startTC: tc))
                            }
                        }
                    }
                }

                if parsed.isEmpty {
                    if output.contains("ERROR:") {
                        let msg = lines.first(where: { $0.hasPrefix("ERROR:") }) ?? "Unknown error"
                        self.indexingErrorMessage = msg
                        self.showIndexingError = true
                    } else {
                        self.sceneImportResultMessage = "No Cream scene markers found on the current timeline."
                        self.showSceneImportResult = true
                    }
                    return
                }

                // Merge: keep existing scenes, add new ones that don't overlap by name. The script
                // call above only reads markers from Resolve (not undoable, nothing to reverse
                // there), but applying its result into currentScenes is a local data change.
                let oldScenes = self.projectManager.currentScenes
                var existing = self.projectManager.currentScenes
                var added = 0
                for newScene in parsed {
                    if !existing.contains(where: { $0.name == newScene.name }) {
                        existing.append(newScene)
                        added += 1
                    }
                }
                existing.sort { $0.startTC < $1.startTC }
                self.projectManager.currentScenes = existing
                self.projectManager.saveScenes()
                self.projectManager.registerUndo(\.currentScenes, actionName: "Import Scenes", from: oldScenes) {
                    self.projectManager.saveScenes()
                }

                self.sceneImportResultMessage = "✅ Imported \(added) new scene(s) from DaVinci Resolve. \(parsed.count - added) already existed and were skipped."
                self.showSceneImportResult = true
            }
        }
    }
}
