import Foundation
import Combine

// MARK: - Data Models

struct ClipData: Codable, Identifiable {
    var id: UUID = UUID()
    var vfxName: String
    var tcIn: String
    var tcOut: String
    var sourceTcIn: String
    var sourceTcOut: String
    var fileNames: String
    var reelName: String
}

struct IndexingRun: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date = Date()
    var clips: [ClipData]
}

struct Project: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var createdDate: Date = Date()
    var runs: [IndexingRun] = []
    var vfxTrackIndex: String? = nil
}

struct ProjectStore: Codable {
    var selectedProjectId: UUID?
    var projects: [Project]
}

// MARK: - Project Manager

class ProjectManager: ObservableObject {
    @Published var projects: [Project] = []
    @Published var currentProject: Project?
    
    // Helper to get formatted date
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
    
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
    
    func renameProject(id: UUID, newName: String) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].name = newName
        if currentProject?.id == id {
            currentProject = projects[index]
        }
        save()
    }
    
    func addIndexingRun(to projectId: UUID, clips: [ClipData]) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        
        let run = IndexingRun(clips: clips)
        projects[index].runs.append(run)
        
        // Update current project if active
        if currentProject?.id == projectId {
            currentProject = projects[index]
        }
        
        save()
    }
    
    func deleteIndexingRun(projectId: UUID, runId: UUID) {
        guard let pIndex = projects.firstIndex(where: { $0.id == projectId }) else { return }
        
        projects[pIndex].runs.removeAll { $0.id == runId }
        
        if currentProject?.id == projectId {
            currentProject = projects[pIndex]
        }
        save()
    }

    func updateVfxTrack(projectId: UUID, track: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[index].vfxTrackIndex = track
        
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
