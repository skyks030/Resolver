import SwiftUI

// MARK: - Python Bridge Models

struct TimelineInfo: Identifiable {
    var id: String { uniqueId?.isEmpty == false ? uniqueId! : name }
    let name: String
    let uniqueId: String?
    let startTC: String?
    let frameCount: Int?
    let fps: String?
}

extension TimelineInfo: Decodable {
    enum CodingKeys: String, CodingKey {
        case name, uniqueId, startTC, frameCount, fps
    }

    // Custom decoding: the DaVinci Resolve API can hand back numeric fields
    // (e.g. fps, frameCount) as either strings or numbers depending on
    // platform/version. Decode defensively so a type surprise never blanks
    // out the whole timeline list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Untitled Timeline"
        uniqueId = try? c.decodeIfPresent(String.self, forKey: .uniqueId)
        startTC = try? c.decodeIfPresent(String.self, forKey: .startTC)

        if let intVal = try? c.decodeIfPresent(Int.self, forKey: .frameCount) {
            frameCount = intVal
        } else if let dblVal = try? c.decodeIfPresent(Double.self, forKey: .frameCount) {
            frameCount = Int(dblVal)
        } else {
            frameCount = nil
        }

        if let strVal = try? c.decodeIfPresent(String.self, forKey: .fps) {
            fps = strVal
        } else if let dblVal = try? c.decodeIfPresent(Double.self, forKey: .fps) {
            fps = String(dblVal)
        } else {
            fps = nil
        }
    }
}

struct TimelineListResult: Decodable {
    let timelines: [TimelineInfo]?
    let error: String?
}

struct EpisodeManagementView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var projectManager: ProjectManager
    let project: Project

    @State private var isIndexing = true
    @State private var indexingError: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if isIndexing {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Indexing Timelines from DaVinci Resolve...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = indexingError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text(error)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        Button("Retry") { indexTimelines() }
                            .liquidGlassButton(prominent: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section(
                            header: Text("Timelines in \"\(project.name)\""),
                            footer: Text("Edit a number to reassign it — whichever timeline currently has that number swaps to the old one. Deleting a timeline removes it from this list; press \"Re-Index\" to pull the full timeline list from the project again.")
                        ) {
                            if projectManager.currentEpisodes.isEmpty {
                                Text("No timelines found in this project.").foregroundColor(.secondary)
                            } else {
                                ForEach(projectManager.currentEpisodes.sorted(by: { $0.episodeNumber < $1.episodeNumber })) { episode in
                                    episodeRow(episode)
                                }
                                .animation(.default, value: projectManager.currentEpisodes)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Episode Manager")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        indexTimelines()
                    } label: {
                        Label("Re-Index", systemImage: "arrow.clockwise")
                    }
                    .disabled(isIndexing)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 450)
        .onAppear {
            indexTimelines()
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func episodeRow(_ episode: EpisodeData) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("Episode")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("", value: Binding(
                    get: { episode.episodeNumber },
                    set: { setEpisodeNumber($0, for: episode.id) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 44)

                Stepper("", value: Binding(
                    get: { episode.episodeNumber },
                    set: { setEpisodeNumber($0, for: episode.id) }
                ), in: 1...9999)
                .labelsHidden()
            }

            Divider()

            Text(episode.timelineName)
                .lineLimit(1)

            Spacer()

            Button {
                deleteEpisode(episode)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Remove this timeline from the Episode Manager")
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func setEpisodeNumber(_ newNumberRaw: Int, for id: UUID) {
        let newNumber = max(1, newNumberRaw)
        guard let idx = projectManager.currentEpisodes.firstIndex(where: { $0.id == id }) else { return }
        let oldNumber = projectManager.currentEpisodes[idx].episodeNumber
        if oldNumber == newNumber { return }

        // Enforce uniqueness: whoever currently holds the target number
        // takes over the edited row's old number instead (swap).
        if let conflictIdx = projectManager.currentEpisodes.firstIndex(where: { $0.episodeNumber == newNumber && $0.id != id }) {
            projectManager.currentEpisodes[conflictIdx].episodeNumber = oldNumber
        }
        projectManager.currentEpisodes[idx].episodeNumber = newNumber
        projectManager.saveEpisodes()
    }

    private func deleteEpisode(_ episode: EpisodeData) {
        projectManager.currentEpisodes.removeAll { $0.id == episode.id }
        projectManager.saveEpisodes()
    }

    // MARK: - Indexing

    private func indexTimelines() {
        isIndexing = true
        indexingError = nil

        PyScriptRunner.run(scriptName: "Resolve/Tools/list_timelines", showOutput: false) { output in
            DispatchQueue.main.async {
                self.isIndexing = false

                guard let output = output, let data = output.data(using: .utf8) else {
                    self.indexingError = "No response from DaVinci Resolve."
                    return
                }

                do {
                    let result = try JSONDecoder().decode(TimelineListResult.self, from: data)
                    if let err = result.error {
                        self.indexingError = err
                        return
                    }
                    let timelines = result.timelines ?? []
                    if timelines.isEmpty {
                        self.indexingError = "No timelines found in the currently open project."
                        return
                    }
                    self.mergeTimelines(timelines)
                } catch {
                    self.indexingError = "Failed to parse timeline data from DaVinci Resolve."
                    ConsoleLogger.shared.log("Episode Manager JSON decode error: \(error). Raw: \(output)")
                }
            }
        }
    }

    // Re-Index always reflects the full, live state of the project: every
    // timeline currently in DaVinci Resolve is shown, including ones
    // previously removed here. Existing episode numbers are preserved for
    // timelines that are still present; brand-new timelines are appended,
    // sorted alphabetically, and auto-numbered continuing from the highest
    // number in use.
    private func mergeTimelines(_ timelines: [TimelineInfo]) {
        let incoming = timelines
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        var existing = projectManager.currentEpisodes
        var usedNumbers = Set(existing.map { $0.episodeNumber })
        var merged: [EpisodeData] = []

        for tl in incoming {
            if let idx = existing.firstIndex(where: {
                (tl.uniqueId?.isEmpty == false && $0.timelineUniqueId == tl.uniqueId) || $0.timelineName == tl.name
            }) {
                var episode = existing[idx]
                episode.timelineName = tl.name
                episode.timelineUniqueId = tl.uniqueId
                episode.startTC = tl.startTC
                merged.append(episode)
                existing.remove(at: idx)
            } else {
                let nextNumber = (usedNumbers.max() ?? 0) + 1
                usedNumbers.insert(nextNumber)
                merged.append(EpisodeData(timelineName: tl.name, timelineUniqueId: tl.uniqueId, episodeNumber: nextNumber, startTC: tl.startTC))
            }
        }

        projectManager.currentEpisodes = merged
        projectManager.saveEpisodes()
    }
}
