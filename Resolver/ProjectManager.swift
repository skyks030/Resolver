import Foundation
import Combine

// MARK: - Data Models

struct ClipData: Codable, Identifiable {
    var id: UUID = UUID()
    let vfxName: String
    let tcIn: String
    let tcOut: String
    let fileNames: String
    // Future metadata fields can be added here
}

struct Project: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var createdDate: Date = Date()
    var clips: [ClipData] = []
}

struct ProjectStore: Codable {
    var selectedProjectId: UUID?
    var projects: [Project]
}

// MARK: - Project Manager

class ProjectManager: ObservableObject {
    @Published var projects: [Project] = []
    @Published var currentProject: Project?
    
    private let saveUrl: URL
    
    init() {
        // Find documents directory
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportDir = paths[0].appendingPathComponent("com.skyks030.Resolver")
        
        // Create directory if not exists
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        
        self.saveUrl = appSupportDir.appendingPathComponent("projects.json")
        
        load()
    }
    
    // MARK: - Actions
    
    func addProject(name: String) {
        let newProject = Project(name: name)
        projects.append(newProject)
        selectProject(newProject.id)
        save()
    }
    
    func selectProject(_ id: UUID?) {
        if let id = id {
            currentProject = projects.first(where: { $0.id == id })
        } else {
            currentProject = nil
        }
        save()
    }
    
    func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        if currentProject?.id == id {
            currentProject = nil
        }
        save()
    }
    
    func addClips(to projectId: UUID, clips: [ClipData]) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        
        // Append new clips
        projects[index].clips.append(contentsOf: clips)
        
        // Update current project if it's the one modified
        if currentProject?.id == projectId {
            currentProject = projects[index]
        }
        
        save()
    }
    
    // MARK: - Persistence
    
    func save() {
        let store = ProjectStore(selectedProjectId: currentProject?.id, projects: projects)
        do {
            let data = try JSONEncoder().encode(store)
            try data.write(to: saveUrl)
        } catch {
            print("❌ Fehler beim Speichern der Projekte: \(error.localizedDescription)")
        }
    }
    
    func load() {
        do {
            let data = try Data(contentsOf: saveUrl)
            let store = try JSONDecoder().decode(ProjectStore.self, from: data)
            self.projects = store.projects
            self.selectProject(store.selectedProjectId)
        } catch {
            print("⚠️ Keine Projekte geladen (oder Fehler): \(error.localizedDescription)")
            self.projects = []
            self.currentProject = nil
        }
    }
}
