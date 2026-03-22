import SwiftUI

struct SceneManagementView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var projectManager: ProjectManager
    let project: Project
    
    @State private var newSceneName = ""
    @State private var newSceneTC = "01:00:00:00"
    
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
}
