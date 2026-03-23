import SwiftUI

struct SceneManagementView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var projectManager: ProjectManager
    let project: Project
    
    @State private var newSceneName = ""
    @State private var newSceneTC = "01:00:00:00"
    
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
                                let newScene = SceneData(name: trimmedName, startTC: trimmedTC)
                                projectManager.currentScenes.append(newScene)
                                projectManager.currentScenes.sort { $0.startTC < $1.startTC }
                                projectManager.saveScenes()
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
                                Divider()
                                TextField("Start TC", text: $scene.startTC)
                                Spacer()
                                Button(action: {
                                    if let idx = projectManager.currentScenes.firstIndex(where: { $0.id == scene.id }) {
                                        projectManager.currentScenes.remove(at: idx)
                                        projectManager.saveScenes()
                                    }
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 8)
                            }
                            // Whenever a textfield ends editing, save implicitly!
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
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }
    
    private func deleteScenes(at offsets: IndexSet) {
        projectManager.currentScenes.remove(atOffsets: offsets)
        projectManager.saveScenes()
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
                
                // Merge: keep existing scenes, add new ones that don't overlap by name
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
                
                self.sceneImportResultMessage = "✅ Imported \(added) new scene(s) from DaVinci Resolve. \(parsed.count - added) already existed and were skipped."
                self.showSceneImportResult = true
            }
        }
    }
}
