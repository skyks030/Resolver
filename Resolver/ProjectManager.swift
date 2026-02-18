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
    var frameStart: Int?
    var frameEnd: Int?
    var duration: Int?
    var originalVfxName: String?
}

struct MarkerData: Codable, Identifiable {
    var id = UUID()
    let frameId: Int
    let color: String
    let name: String
    let note: String
    let duration: Int
    
    // Check CodingKeys to exclude ID from JSON requirement
    private enum CodingKeys: String, CodingKey {
        case frameId, color, name, note, duration
    }
}

struct IndexingRun: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date = Date()
    var clips: [ClipData]
    var sceneMarkers: [MarkerData]? = []
}

struct Project: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var createdDate: Date = Date()
    var runs: [IndexingRun] = []
    var vfxTrackIndex: String? = nil
    var vfxThumbnailTrackIndex: String? = nil
    var vfxEndMarkerEnabled: Bool? = false // Default OFF
    var vfxRenamingMap: [String: String]? = [:] // Map Original Name -> New Name
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
    
    func addIndexingRun(to projectId: UUID, clips: [ClipData], sceneMarkers: [MarkerData] = []) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        
        // Process Clips: Apply Renaming Map
        var processedClips = clips
        let renamingMap = projects[index].vfxRenamingMap ?? [:]
        
        for i in 0..<processedClips.count {
            // Ensure original name is set
            if processedClips[i].originalVfxName == nil {
                processedClips[i].originalVfxName = processedClips[i].vfxName
            }
            
            // Check if we have a rename rule for this original name
            if let original = processedClips[i].originalVfxName, let newName = renamingMap[original] {
                processedClips[i].vfxName = newName
            }
        }
        
        var run = IndexingRun(clips: processedClips)
        run.sceneMarkers = sceneMarkers
        
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
    
    func updateVfxRenamingMap(projectId: UUID, updates: [String: String]) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        
        // Initialize if nil
        if projects[index].vfxRenamingMap == nil {
            projects[index].vfxRenamingMap = [:]
        }
        
        // Update Map
        for (originalName, newName) in updates {
            projects[index].vfxRenamingMap?[originalName] = newName
        }
        
        // Apply to ALL runs in the project to ensure consistency
        for rIndex in 0..<projects[index].runs.count {
            for cIndex in 0..<projects[index].runs[rIndex].clips.count {
                var clip = projects[index].runs[rIndex].clips[cIndex]
                
                // Backfill original name if missing (assume current is original if not set, 
                // but if we are renaming, we likely want to be careful. 
                // For existing clips, if original is nil, we assume vfxName IS the original 
                // UNLESS we just matched it. But to be safe, we only rename if we have an original name.)
                if clip.originalVfxName == nil {
                     // If we are applying a rename, we must assume the CURRENT name is the original 
                     // if it matches the key, OR we assume it was never renamed.
                     // A safer bet for legacy data: set original = current
                     clip.originalVfxName = clip.vfxName
                }
                
                if let original = clip.originalVfxName, let newName = projects[index].vfxRenamingMap?[original] {
                    clip.vfxName = newName
                }
                
                projects[index].runs[rIndex].clips[cIndex] = clip
            }
        }
        
        if currentProject?.id == projectId {
            currentProject = projects[index]
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

    func updateVfxThumbnailTrack(projectId: UUID, track: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[index].vfxThumbnailTrackIndex = track
        
        if currentProject?.id == projectId {
            currentProject = projects[index]
        }
        save()
    }
    
    func updateVfxEndMarkerEnabled(projectId: UUID, enabled: Bool) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[index].vfxEndMarkerEnabled = enabled
        
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
