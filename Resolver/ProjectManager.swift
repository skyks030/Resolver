import Foundation
import Combine

// MARK: - Data Models

struct ClipData: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var dict: [String: String] = [:]
    
    // Convenience Accessors
    var vfxName: String {
        get { dict["VFX Name"] ?? "" }
        set { dict["VFX Name"] = newValue }
    }
    var originalVfxName: String? {
        get { dict["Original VFX Name"] }
        set { dict["Original VFX Name"] = newValue }
    }
    var uniqueId: String? {
        get { dict["Resolve Unique ID"] }
        set { dict["Resolve Unique ID"] = newValue }
    }
    var tcIn: String { get { dict["TC In"] ?? "" } set { dict["TC In"] = newValue } }
    var tcOut: String { get { dict["TC Out"] ?? "" } set { dict["TC Out"] = newValue } }
    var sourceTcIn: String { get { dict["Source TC In"] ?? "" } set { dict["Source TC In"] = newValue } }
    var sourceTcOut: String { get { dict["Source TC Out"] ?? "" } set { dict["Source TC Out"] = newValue } }
    var fileNames: String { get { dict["File Names"] ?? "" } set { dict["File Names"] = newValue } }
    var reelName: String { get { dict["Reel Name"] ?? "" } set { dict["Reel Name"] = newValue } }
    
    var frameStart: Int? {
        get { if let val = dict["Frame Start"] { return Int(val) }; return nil }
        set { dict["Frame Start"] = newValue.map { String($0) } }
    }
    var frameEnd: Int? {
        get { if let val = dict["Frame End"] { return Int(val) }; return nil }
        set { dict["Frame End"] = newValue.map { String($0) } }
    }
    var duration: Int? {
        get { if let val = dict["Duration"] { return Int(val) }; return nil }
        set { dict["Duration"] = newValue.map { String($0) } }
    }
    var customMetadata: [String: String]? {
        get { return dict }
        set { if let v = newValue { for (k,val) in v { dict[k] = val } } }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, dict, vfxName, tcIn, tcOut, sourceTcIn, sourceTcOut, fileNames, reelName, frameStart, frameEnd, duration, originalVfxName, uniqueId, customMetadata
    }
    
    init() {}
    
    init(id: UUID = UUID(), dict: [String: String]) {
        self.id = id
        self.dict = dict
    }
    
    init(id: UUID, vfxName: String, tcIn: String, tcOut: String, sourceTcIn: String, sourceTcOut: String, fileNames: String, reelName: String, frameStart: Int?, frameEnd: Int?, duration: Int?, originalVfxName: String?, uniqueId: String?, customMetadata: [String:String]? = nil) {
        self.id = id
        self.vfxName = vfxName
        self.tcIn = tcIn
        self.tcOut = tcOut
        self.sourceTcIn = sourceTcIn
        self.sourceTcOut = sourceTcOut
        self.fileNames = fileNames
        self.reelName = reelName
        self.frameStart = frameStart
        self.frameEnd = frameEnd
        self.duration = duration
        if let o = originalVfxName { self.originalVfxName = o }
        if let u = uniqueId { self.uniqueId = u }
        if let custom = customMetadata {
            for (k, v) in custom { self.dict[k] = v }
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        
        if let d = try container.decodeIfPresent([String: String].self, forKey: .dict) {
            self.dict = d
        } else {
            if let v = try? container.decodeIfPresent(String.self, forKey: .vfxName) { self.vfxName = v }
            if let v = try? container.decodeIfPresent(String.self, forKey: .tcIn) { self.tcIn = v }
            if let v = try? container.decodeIfPresent(String.self, forKey: .tcOut) { self.tcOut = v }
            if let v = try? container.decodeIfPresent(String.self, forKey: .sourceTcIn) { self.sourceTcIn = v }
            if let v = try? container.decodeIfPresent(String.self, forKey: .sourceTcOut) { self.sourceTcOut = v }
            if let v = try? container.decodeIfPresent(String.self, forKey: .fileNames) { self.fileNames = v }
            if let v = try? container.decodeIfPresent(String.self, forKey: .reelName) { self.reelName = v }
            if let v = try? container.decodeIfPresent(Int.self, forKey: .frameStart) { self.frameStart = v }
            if let v = try? container.decodeIfPresent(Int.self, forKey: .frameEnd) { self.frameEnd = v }
            if let v = try? container.decodeIfPresent(Int.self, forKey: .duration) { self.duration = v }
            if let v = try? container.decodeIfPresent(String.self, forKey: .originalVfxName) { self.originalVfxName = v }
            if let v = try? container.decodeIfPresent(String.self, forKey: .uniqueId) { self.uniqueId = v }
            if let c = try? container.decodeIfPresent([String:String].self, forKey: .customMetadata) {
                for (k, val) in c { self.dict[k] = val }
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(dict, forKey: .dict)
    }
}

struct MarkerData: Codable, Identifiable {
    var id = UUID()
    let frameId: Int
    let color: String
    let name: String
    let note: String
    let duration: Int
    var tc: String?
    // Which episode's timeline this marker/clip belongs to, so the Resolve-side script can open
    // the right timeline before acting on it. Populated client-side (see
    // ProjectExportView.resolveTargetEpisode) when episodes are registered; nil otherwise, in
    // which case the script falls back to whatever timeline is currently open in Resolve.
    var timelineUniqueId: String?
    var timelineName: String?

    // Check CodingKeys to exclude ID from JSON requirement
    private enum CodingKeys: String, CodingKey {
        case frameId, color, name, note, duration, tc, timelineUniqueId, timelineName
    }
}

struct SceneData: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var startTC: String

    // Shared scene-matching logic: which registered scene a given Record TC
    // falls into (scenes are ranges from their startTC up to the next scene's
    // startTC). Used both by the VFX Name Generator and by DaVinci import to
    // pre-populate a per-clip "Scene" column.
    static func matchedSceneName(for tc: String, in scenes: [SceneData]) -> String? {
        let cleanTC = tc.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTC.isEmpty { return nil }
        var matchedName: String? = nil
        for scene in scenes.sorted(by: { $0.startTC < $1.startTC }) {
            if cleanTC >= scene.startTC { matchedName = scene.name } else { break }
        }
        return matchedName
    }
}

struct EpisodeData: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var timelineName: String
    var timelineUniqueId: String? = nil
    var episodeNumber: Int = 1
    var startTC: String? = nil

    // Shared episode-matching logic, mirroring SceneData.matchedSceneName:
    // which registered episode a given Record TC falls into (episodes are
    // ranges from their startTC up to the next episode's startTC). Used as a
    // fallback when a clip's "Episode" column wasn't tagged directly during
    // per-timeline indexing (e.g. a plain CSV import).
    static func matchedEpisodeNumber(for tc: String, in episodes: [EpisodeData]) -> Int? {
        let cleanTC = tc.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTC.isEmpty { return nil }
        var matchedNumber: Int? = nil
        let dated = episodes.compactMap { ep -> (String, Int)? in
            guard let start = ep.startTC, !start.isEmpty else { return nil }
            return (start, ep.episodeNumber)
        }
        for (start, number) in dated.sorted(by: { $0.0 < $1.0 }) {
            if cleanTC >= start { matchedNumber = number } else { break }
        }
        return matchedNumber
    }
}

// Persisted VFX Name Generator schema, so a project remembers its naming
// pattern (prefix, episode/scene/shot settings, separators) across reopens.
struct VfxNameSchema: Codable, Equatable {
    var prefixText: String = ""
    var includeEpisodeNum: Bool = false
    var episodeNumDigits: Int = 2
    var episodeLabelText: String = "E"
    var includeSceneNum: Bool = true
    var sceneNumDigits: Int = 3
    var includeCounter: Bool = true
    var counterDigits: Int = 3
    var counterStart: Int = 10
    var counterStep: Int = 10
    var suffixText: String = ""
    var sepPrefixEpisode: String = ""
    var sepEpisodeScene: String = ""
    var sepSceneShot: String = "_"
    var sepShotSuffix: String = ""
}

// Legacy Run structure for migration
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
    var runs: [IndexingRun]? = [] // Legacy, kept for decoding old JSON
    var sceneMarkers: [MarkerData]? = [] // Moved to project level
    var vfxTrackIndex: String? = nil
    var vfxThumbnailTrackIndex: String? = nil
    var vfxEndMarkerEnabled: Bool? = false // Default OFF
    var vfxRenamingMap: [String: String]? = [:] // Map Original Name -> New Name
    var vfxNameSchema: VfxNameSchema? = nil // Remembered VFX Name Generator settings

    // Toggle-button state for the Color Groups / VFX Markers / Scene Markers buttons in
    // ProjectExportView. Set only when the corresponding create/delete Resolve call actually
    // reports success — this is a locally-remembered "last known state", not a live query of
    // Resolve, so it can drift if someone deletes markers/groups directly in Resolve.
    var colorGroupsActive: Bool? = false
    var vfxMarkersActive: Bool? = false
    var sceneMarkersActive: Bool? = false

    // Sheet Sync: a linked Excel Online (OneDrive for Business/SharePoint) or Google Sheets
    // document this project's master list is periodically compared against. See SheetSyncView.
    var sheetSyncProvider: String? = nil // "microsoft" or "google"
    var sheetSyncLink: String? = nil // the pasted share/document URL
    var sheetSyncSheetName: String? = nil // nil = first sheet/worksheet
}

struct ProjectStore: Codable {
    var selectedProjectId: UUID?
    var projects: [Project]
}

// MARK: - Project Manager

class ProjectManager: ObservableObject {
    @Published var projects: [Project] = []
    @Published var currentProject: Project? {
        didSet {
            // Load master list whenever project changes
            loadMasterList()
            loadScenes()
            loadEpisodes()
        }
    }

    @Published var currentMasterList: [ClipData] = []
    @Published var currentScenes: [SceneData] = []
    @Published var currentEpisodes: [EpisodeData] = []

    // MARK: - Undo/Redo

    // Set once by the root view (ProjectExportView) from its `@Environment(\.undoManager)`. Every
    // local data-mutating action in the app registers its undo/redo through this — see
    // `registerUndo` below. Nil before that wiring happens (or if run headless), in which case
    // registration is simply a no-op — nothing crashes, edits just aren't undoable yet.
    weak var undoManager: UndoManager?

    // Snapshot-based undo+redo for a whole `ProjectManager` property. Call this AFTER performing
    // and persisting a mutation: `oldValue` is what this undo step restores; the value already in
    // place (captured here, before it's overwritten) becomes what the auto-registered redo
    // re-applies. Registering the inverse action *from inside* the undo handler is the standard
    // Cocoa "toggle" pattern — it's what makes redo work via the same UndoManager stack without
    // any separate redo bookkeeping. `persist` is whichever save function already exists for this
    // property (e.g. `saveMasterList`), so undo/redo always ends up written to disk exactly like
    // a normal edit would.
    func registerUndo<Value>(
        _ keyPath: ReferenceWritableKeyPath<ProjectManager, Value>,
        actionName: String,
        from oldValue: Value,
        persist: @escaping () -> Void
    ) {
        guard let undoManager else { return }
        let redoValue = self[keyPath: keyPath]
        undoManager.registerUndo(withTarget: self) { target in
            target[keyPath: keyPath] = oldValue
            persist()
            target.registerUndo(keyPath, actionName: actionName, from: redoValue, persist: persist)
        }
        undoManager.setActionName(actionName)
    }

    // Helper to get formatted date
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
    
    private let appSupportDir: URL
    private let saveUrl: URL
    
    init() {
        // Find documents directory
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        self.appSupportDir = paths[0].appendingPathComponent("com.skyks030.Resolver")
        
        // Create directory if not exists
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        
        self.saveUrl = appSupportDir.appendingPathComponent("projects.json")
        
        load()
        migrateLegacyProjects()
    }
    
    // MARK: - Directories
    func projectDirectory(for projectId: UUID) -> URL {
        let dir = appSupportDir.appendingPathComponent(projectId.uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    func masterListUrl(for projectId: UUID) -> URL {
        let dir = projectDirectory(for: projectId)
        let newUrl = dir.appendingPathComponent("Master_VFX_List_\(projectId.uuidString).csv")
        let oldUrl = dir.appendingPathComponent("Master_VFX_List.csv")
        
        if FileManager.default.fileExists(atPath: oldUrl.path) && !FileManager.default.fileExists(atPath: newUrl.path) {
            try? FileManager.default.moveItem(at: oldUrl, to: newUrl)
        }
        
        return newUrl
    }
    
    func scenesUrl(for projectId: UUID) -> URL {
        let dir = projectDirectory(for: projectId)
        return dir.appendingPathComponent("Scenes.csv")
    }

    func episodesUrl(for projectId: UUID) -> URL {
        let dir = projectDirectory(for: projectId)
        return dir.appendingPathComponent("Episodes.csv")
    }
    
    // MARK: - Actions
    
    func addProject(name: String) {
        let newProject = Project(name: name)
        projects.append(newProject)
        selectProject(newProject.id)
        save()
        
        // Auto-populate default columns
        let defaultDict = [
            "VFX Name": "New Shot",
            "Clip Name": "",
            "TC In": "",
            "TC Out": "",
            "Source TC In": "",
            "Source TC Out": "",
            "Duration": ""
        ]
        currentMasterList = [ClipData(dict: defaultDict)]
        saveMasterList() // so it persists
    }
    
    func selectProject(_ id: UUID?) {
        if let id = id {
            currentProject = projects.first(where: { $0.id == id })
        } else {
            currentProject = nil
        }
        save() // saves selected state
    }
    
    func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        if currentProject?.id == id {
            self.selectProject(projects.last?.id)
        }
        
        // Delete the subdirectory for this project
        let dir = appSupportDir.appendingPathComponent(id.uuidString)
        try? FileManager.default.removeItem(at: dir)
        
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
    
    // MARK: - Scene Management
    
    func loadScenes() {
        guard let proj = currentProject else {
            currentScenes = []
            return
        }
        let url = scenesUrl(for: proj.id)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                var loaded: [SceneData] = []
                let rows = text.components(separatedBy: .newlines)
                for row in rows.dropFirst() {
                    let cols = row.components(separatedBy: ",")
                    if cols.count >= 3 {
                        if let uuid = UUID(uuidString: cols[0]) {
                            loaded.append(SceneData(id: uuid, name: cols[1], startTC: cols[2]))
                        }
                    }
                }
                currentScenes = loaded
                print("🔄 Loaded \(currentScenes.count) scenes from Scenes.csv")
            } catch {
                print("❌ Error loading Scenes CSV: \(error)")
                currentScenes = []
            }
        } else {
            currentScenes = []
        }
    }
    
    func saveScenes() {
        guard let proj = currentProject else { return }
        let url = scenesUrl(for: proj.id)
        var csv = "id,name,startTC\n"
        for scene in currentScenes {
            let safeName = scene.name.replacingOccurrences(of: ",", with: ";")
            let safeTC = scene.startTC.replacingOccurrences(of: ",", with: "")
            csv += "\(scene.id.uuidString),\(safeName),\(safeTC)\n"
        }
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("❌ Error saving Scenes CSV: \(error)")
        }
    }

    // MARK: - Episode Management

    func loadEpisodes() {
        guard let proj = currentProject else {
            currentEpisodes = []
            return
        }
        let url = episodesUrl(for: proj.id)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                var loaded: [EpisodeData] = []
                let rows = text.components(separatedBy: .newlines)
                for row in rows.dropFirst() {
                    if row.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                    let cols = row.components(separatedBy: ",")
                    if cols.count >= 4, let uuid = UUID(uuidString: cols[0]) {
                        let uniqueId = cols[2].isEmpty ? nil : cols[2]
                        let number = Int(cols[3]) ?? 1
                        // startTC is a 5th column added later; older Episodes.csv files won't
                        // have it, so only read it when present.
                        let startTC = (cols.count >= 5 && !cols[4].isEmpty) ? cols[4] : nil
                        loaded.append(EpisodeData(id: uuid, timelineName: cols[1], timelineUniqueId: uniqueId, episodeNumber: number, startTC: startTC))
                    }
                }
                // Episode numbers always mirror top-to-bottom position now (no more free-form
                // editing) — sort by whatever number was last saved (preserves intent from
                // before this was enforced, and any legacy data with gaps from deletions), then
                // close those gaps by renumbering 1, 2, 3, ... by final position.
                loaded.sort { $0.episodeNumber < $1.episodeNumber }
                for i in loaded.indices { loaded[i].episodeNumber = i + 1 }
                currentEpisodes = loaded
                print("🔄 Loaded \(currentEpisodes.count) episodes from Episodes.csv")
            } catch {
                print("❌ Error loading Episodes CSV: \(error)")
                currentEpisodes = []
            }
        } else {
            currentEpisodes = []
        }
    }

    func saveEpisodes() {
        guard let proj = currentProject else { return }
        let url = episodesUrl(for: proj.id)
        var csv = "id,timelineName,timelineUniqueId,episodeNumber,startTC\n"
        for episode in currentEpisodes {
            let safeTimelineName = episode.timelineName.replacingOccurrences(of: ",", with: ";")
            let safeUniqueId = (episode.timelineUniqueId ?? "").replacingOccurrences(of: ",", with: "")
            let safeStartTC = (episode.startTC ?? "").replacingOccurrences(of: ",", with: "")
            csv += "\(episode.id.uuidString),\(safeTimelineName),\(safeUniqueId),\(episode.episodeNumber),\(safeStartTC)\n"
        }
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("❌ Error saving Episodes CSV: \(error)")
        }
    }

    // MARK: - Master List Management
    
    func loadMasterList() {
        guard let proj = currentProject else {
            currentMasterList = []
            return
        }
        let url = masterListUrl(for: proj.id)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                currentMasterList = try CSVManager.read(from: url)
                print("🔄 Loaded \(currentMasterList.count) clips from Master_VFX_List.csv for \(proj.name)")
            } catch {
                print("❌ Error loading Master List CSV: \(error)")
                currentMasterList = []
            }
        } else {
            currentMasterList = []
        }
    }
    
    func saveMasterList() {
        guard let proj = currentProject else { return }
        let url = masterListUrl(for: proj.id)
        do {
            try CSVManager.write(clips: currentMasterList, to: url)
        } catch {
            print("❌ Error saving Master List CSV: \(error)")
        }
    }
    
    // Recomputes the "Episode" column for every clip in the master list from its Record TC In
    // against the registered episodes' Start TC ranges (EpisodeData.matchedEpisodeNumber — same
    // range-matching used to fill in Episode during indexing/import). A no-op when no episodes
    // are registered. This is an explicit, user-triggered recompute (Episode Manager's "OK"
    // button) — it overwrites any existing "Episode" value, since episode boundaries may have
    // just changed (reordered, Start TC edited, etc.), unlike the fill-only-if-empty fallback
    // used during CSV/DaVinci import augmentation.
    func recomputeEpisodeColumn() {
        guard !currentEpisodes.isEmpty else { return }
        for i in currentMasterList.indices {
            if let number = EpisodeData.matchedEpisodeNumber(for: currentMasterList[i].tcIn, in: currentEpisodes) {
                currentMasterList[i].dict["Episode"] = String(number)
            }
        }
        saveMasterList()
    }

    // Same idea as recomputeEpisodeColumn, for the "Scene" column via SceneData.matchedSceneName —
    // Scene Manager's "OK" button.
    func recomputeSceneColumn() {
        guard !currentScenes.isEmpty else { return }
        for i in currentMasterList.indices {
            if let name = SceneData.matchedSceneName(for: currentMasterList[i].tcIn, in: currentScenes) {
                currentMasterList[i].dict["Scene"] = name
            }
        }
        saveMasterList()
    }

    func updateMasterList(with clips: [ClipData], sceneMarkers: [MarkerData] = []) {
        currentMasterList = clips
        saveMasterList() // Save CSV immediately
        
        // Update markers in metadata project.json if provided
        if let proj = currentProject, let index = projects.firstIndex(where: { $0.id == proj.id }) {
            if !sceneMarkers.isEmpty {
                projects[index].sceneMarkers = sceneMarkers
                currentProject = projects[index]
                save() // Save metadata to project.json
            }
        }
    }
    
    // Helper to get imported clips and apply renaming map
    func prepareImportedClips(_ clips: [ClipData], projectId: UUID) -> [ClipData] {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return clips }
        let renamingMap = projects[index].vfxRenamingMap ?? [:]
        
        var processedClips = clips
        for i in 0..<processedClips.count {
            if processedClips[i].originalVfxName == nil {
                processedClips[i].originalVfxName = processedClips[i].vfxName
            }
            if let uid = processedClips[i].uniqueId, let newName = renamingMap[uid] {
                 processedClips[i].vfxName = newName
            } else if let original = processedClips[i].originalVfxName, let newName = renamingMap[original] {
                 processedClips[i].vfxName = newName
            }
        }
        return processedClips
    }
    
    func updateVfxRenamingMap(projectId: UUID, updates: [String: String]) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        
        if projects[index].vfxRenamingMap == nil {
            projects[index].vfxRenamingMap = [:]
        }
        
        print("🔄 Applying \(updates.count) Rename Updates to Project \(projectId)")
        for (originalName, newName) in updates {
            projects[index].vfxRenamingMap?[originalName] = newName
        }
        
        // Apply to current master list if this is the active project
        if currentProject?.id == projectId {
            for i in 0..<currentMasterList.count {
                var clip = currentMasterList[i]
                if clip.originalVfxName == nil {
                     clip.originalVfxName = clip.vfxName
                }
                
                if let uid = clip.uniqueId, let newName = projects[index].vfxRenamingMap?[uid] {
                     clip.vfxName = newName
                } else if let original = clip.originalVfxName, let newName = projects[index].vfxRenamingMap?[original] {
                     clip.vfxName = newName
                }
                currentMasterList[i] = clip
            }
            saveMasterList() // Automatically updates the CSV!
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

    func updateColorGroupsActive(projectId: UUID, active: Bool) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[index].colorGroupsActive = active

        if currentProject?.id == projectId {
            currentProject = projects[index]
        }
        save()
    }

    func updateSheetSyncLink(projectId: UUID, provider: String?, link: String?, sheetName: String?) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[index].sheetSyncProvider = provider
        projects[index].sheetSyncLink = link
        projects[index].sheetSyncSheetName = sheetName

        if currentProject?.id == projectId {
            currentProject = projects[index]
        }
        save()
    }

    func updateVfxMarkersActive(projectId: UUID, active: Bool) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[index].vfxMarkersActive = active

        if currentProject?.id == projectId {
            currentProject = projects[index]
        }
        save()
    }

    func updateSceneMarkersActive(projectId: UUID, active: Bool) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[index].sceneMarkersActive = active

        if currentProject?.id == projectId {
            currentProject = projects[index]
        }
        save()
    }

    func updateVfxNameSchema(projectId: UUID, schema: VfxNameSchema) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[index].vfxNameSchema = schema

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
            
            if store.selectedProjectId == nil, let lastProj = store.projects.last {
                self.selectProject(lastProj.id)
            } else {
                self.selectProject(store.selectedProjectId)
            }
        } catch {
            print("⚠️ Keine Projekte geladen (oder Fehler): \(error.localizedDescription)")
            self.projects = []
            self.currentProject = nil
        }
    }
    
    // MARK: - Migration
    
    private func migrateLegacyProjects() {
        var needsSave = false
        
        for i in 0..<projects.count {
            if let runs = projects[i].runs, !runs.isEmpty {
                // Determine the "Master" list from the last run (highest date)
                if let lastRun = runs.sorted(by: { $0.date > $1.date }).first {
                    print("🔄 Migrating legacy runs for project \(projects[i].name) to Master List CSV...")
                    
                    let csvUrl = masterListUrl(for: projects[i].id)
                    do {
                        try CSVManager.write(clips: lastRun.clips, to: csvUrl)
                        projects[i].sceneMarkers = lastRun.sceneMarkers // Migrate markers to project level
                        projects[i].runs = nil // Nullify to save JSON space
                        needsSave = true
                    } catch {
                        print("❌ Migration failed for project \(projects[i].name): \(error)")
                    }
                }
            }
        }
        
        if needsSave {
            save()
            // reload master list if currently selected one was migrated
            if let current = currentProject, projects.first(where: { $0.id == current.id })?.runs == nil {
                loadMasterList()
            }
        }
    }
}
