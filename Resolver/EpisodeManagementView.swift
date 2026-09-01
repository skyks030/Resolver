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
                            footer: Text("Episode numbers always match top-to-bottom position — 1, 2, 3, ... — use the arrows to reorder. Removing a timeline shifts everything below it up automatically; press \"Re-Index\" to pull the full timeline list from the project again.")
                        ) {
                            if projectManager.currentEpisodes.isEmpty {
                                Text("No timelines found in this project.").foregroundColor(.secondary)
                            } else {
                                ForEach(Array(projectManager.currentEpisodes.enumerated()), id: \.element.id) { index, episode in
                                    episodeRow(episode, index: index)
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
            // Once episodes have been configured, opening the manager should just show that
            // saved arrangement — not silently pull the live timeline list back in (which would
            // re-add every timeline the user had deliberately removed here). Only auto-index the
            // first time (nothing configured yet); after that, indexing only happens via the
            // explicit "Re-Index" button.
            if projectManager.currentEpisodes.isEmpty {
                indexTimelines()
            } else {
                isIndexing = false
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func episodeRow(_ episode: EpisodeData, index: Int) -> some View {
        HStack(spacing: 12) {
            Text("Episode \(episode.episodeNumber)")
                .font(.subheadline.bold())
                .frame(width: 90, alignment: .leading)

            VStack(spacing: 0) {
                Button {
                    moveEpisode(episode, direction: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                .help("Move up (becomes Episode \(episode.episodeNumber - 1))")

                Button {
                    moveEpisode(episode, direction: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(index == projectManager.currentEpisodes.count - 1)
                .help("Move down (becomes Episode \(episode.episodeNumber + 1))")
            }
            .foregroundColor(.accentColor)

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

    // Swaps this episode with its neighbor above/below (direction -1/+1) and renumbers
    // everything, animated so the reordering reads as a smooth reshuffle rather than a jump cut.
    private func moveEpisode(_ episode: EpisodeData, direction: Int) {
        guard let idx = projectManager.currentEpisodes.firstIndex(where: { $0.id == episode.id }) else { return }
        let newIdx = idx + direction
        guard newIdx >= 0, newIdx < projectManager.currentEpisodes.count else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            projectManager.currentEpisodes.swapAt(idx, newIdx)
            renumberEpisodes()
        }
        projectManager.saveEpisodes()
    }

    // Episode numbers are never edited directly — they always mirror top-to-bottom position,
    // so removing or reordering a row automatically renumbers everything else around it.
    private func renumberEpisodes() {
        for i in projectManager.currentEpisodes.indices {
            projectManager.currentEpisodes[i].episodeNumber = i + 1
        }
    }

    private func deleteEpisode(_ episode: EpisodeData) {
        withAnimation(.easeInOut(duration: 0.25)) {
            projectManager.currentEpisodes.removeAll { $0.id == episode.id }
            renumberEpisodes()
        }
        projectManager.saveEpisodes()
    }

    // MARK: - Indexing

    private func indexTimelines() {
        isIndexing = true
        indexingError = nil

        PyScriptRunner.run(scriptName: "Resolve/Tools/list_timelines", showOutput: false) { output in
            DispatchQueue.main.async {
                self.isIndexing = false

                // list_timelines.py now prints debug breadcrumbs (visible in Debug Mode) before
                // its actual result, so pull out the last JSON-looking line rather than trying
                // to decode the whole multi-line output as one document.
                guard let output = output,
                      let jsonLine = PyScriptRunner.lastJSONLine(in: output),
                      let data = jsonLine.data(using: .utf8) else {
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

    // Re-Index always reflects the full, live state of the project: every timeline currently in
    // DaVinci Resolve is shown, including ones previously removed here. The user's top-to-bottom
    // arrangement (which IS the episode numbering) is preserved for every timeline that's still
    // present; brand-new timelines are appended at the end, alphabetically, and everything is
    // renumbered 1, 2, 3, ... by final position.
    private func mergeTimelines(_ timelines: [TimelineInfo]) {
        var merged: [EpisodeData] = []
        var matchedTimelineIds = Set<String>()

        for var episode in projectManager.currentEpisodes {
            guard let tl = timelines.first(where: {
                ($0.uniqueId?.isEmpty == false && $0.uniqueId == episode.timelineUniqueId) || $0.name == episode.timelineName
            }) else {
                continue // This episode's timeline no longer exists in the project — drop it.
            }
            episode.timelineName = tl.name
            episode.timelineUniqueId = tl.uniqueId
            episode.startTC = tl.startTC
            merged.append(episode)
            matchedTimelineIds.insert(tl.id)
        }

        let newTimelines = timelines
            .filter { !matchedTimelineIds.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for tl in newTimelines {
            merged.append(EpisodeData(timelineName: tl.name, timelineUniqueId: tl.uniqueId, episodeNumber: 0, startTC: tl.startTC))
        }

        for i in merged.indices { merged[i].episodeNumber = i + 1 }

        projectManager.currentEpisodes = merged
        projectManager.saveEpisodes()
    }
}
