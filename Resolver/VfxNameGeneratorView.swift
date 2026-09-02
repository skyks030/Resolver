import SwiftUI

struct VfxNameGeneratorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var projectManager: ProjectManager
    let project: Project

    // Schema parts
    @State private var prefixText = ""
    @State private var includeEpisodeNum = false
    @State private var episodeNumDigits = 2
    @State private var episodeLabelText = "E"
    @State private var includeSceneNum = true
    @State private var sceneNumDigits = 3
    @State private var includeCounter = true
    @State private var counterDigits = 3
    @State private var counterStart = 10
    @State private var counterStep = 10
    @State private var suffixText = ""

    // Individually configurable separators between every pair of segments.
    // Defaults reproduce the generator's previous behavior (a single "_"
    // between Scene and Shot, nothing anywhere else).
    @State private var sepPrefixEpisode = ""
    @State private var sepEpisodeScene = ""
    @State private var sepSceneShot = "_"
    @State private var sepShotSuffix = ""

    // Status
    @State private var generatedCount = 0
    @State private var showSuccess = false

    // Episodes/Scenes are only usable as naming components once the user has
    // actually registered some via Episode Manager / Manage Scenes.
    private var effectiveIncludeEpisodeNum: Bool { includeEpisodeNum && !projectManager.currentEpisodes.isEmpty }
    private var effectiveIncludeSceneNum: Bool { includeSceneNum && !projectManager.currentScenes.isEmpty }

    private var sortedEpisodes: [EpisodeData] {
        projectManager.currentEpisodes.sorted { $0.episodeNumber < $1.episodeNumber }
    }

    // Episode numbers are pulled per-clip from the "Episode" column (populated
    // automatically during DaVinci indexing). This is only a stand-in value
    // for the static preview below, not what actually gets used on generate.
    private var previewEpisodeNumber: Int? {
        sortedEpisodes.first?.episodeNumber ?? 1
    }

    // Live preview
    var previewName: String {
        buildName(episodeNumber: previewEpisodeNumber, sceneName: "10", counter: counterStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header bar ──────────────────────────────────────────────────
            HStack {
                Text("VFX Name Generator")
                    .font(.title2).bold()
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // ── Live Preview ─────────────────────────────────────────────────
            VStack(spacing: 6) {
                Text("Preview")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(previewName)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlassPanel(cornerRadius: 8, tint: .accentColor)
                Text("Scene \"10\", shot \(counterStart) as example")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            // ── Schema Builder ───────────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Row: Prefix | sep | Episode | sep | Scene | sep | Shot | sep | Suffix
                    HStack(alignment: .top, spacing: 8) {
                        schemaBlock(
                            title: "Prefix",
                            subtitle: "e.g. \"VFX\"",
                            content: AnyView(
                                TextField("e.g. VFX", text: $prefixText)
                                    .textFieldStyle(.roundedBorder)
                            )
                        )

                        separatorConnector($sepPrefixEpisode)

                        schemaBlock(
                            title: "Episode No.",
                            subtitle: projectManager.currentEpisodes.isEmpty ? "No episodes registered" : "Read from each clip's \"Episode\" column",
                            content: AnyView(
                                VStack(spacing: 6) {
                                    Toggle("", isOn: $includeEpisodeNum)
                                        .labelsHidden()
                                        .disabled(projectManager.currentEpisodes.isEmpty)
                                    if effectiveIncludeEpisodeNum {
                                        TextField("E", text: $episodeLabelText)
                                            .textFieldStyle(.roundedBorder)
                                            .multilineTextAlignment(.center)
                                            .frame(width: 50)
                                            .help("Label prepended to the episode number, e.g. \"E\" for E03")

                                        Stepper("\(episodeNumDigits) digits", value: $episodeNumDigits, in: 0...5)
                                            .labelsHidden()
                                        Text("\(episodeNumDigits) digits")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            )
                        )

                        separatorConnector($sepEpisodeScene)

                        schemaBlock(
                            title: "Scene No.",
                            subtitle: projectManager.currentScenes.isEmpty ? "No scenes registered" : (sceneNumDigits == 0 ? "Raw  (e.g. 5)" : "\(sceneNumDigits) digits (e.g. \(String(format: "%0\(sceneNumDigits)d", 5)))"),
                            content: AnyView(
                                VStack(spacing: 6) {
                                    Toggle("", isOn: $includeSceneNum)
                                        .labelsHidden()
                                        .disabled(projectManager.currentScenes.isEmpty)
                                    if effectiveIncludeSceneNum {
                                        Stepper("\(sceneNumDigits) digits", value: $sceneNumDigits, in: 0...5)
                                            .labelsHidden()
                                        Text("\(sceneNumDigits) digits")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            )
                        )

                        separatorConnector($sepSceneShot)

                        schemaBlock(
                            title: "Shot No.",
                            subtitle: "Ascending per scene",
                            content: AnyView(
                                VStack(spacing: 6) {
                                    Toggle("", isOn: $includeCounter).labelsHidden()
                                    if includeCounter {
                                        Stepper("\(counterDigits) digits", value: $counterDigits, in: 1...5).labelsHidden()
                                        Text("\(counterDigits) digits")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            )
                        )

                        separatorConnector($sepShotSuffix)

                        schemaBlock(
                            title: "Suffix",
                            subtitle: "e.g. \"v01\"",
                            content: AnyView(
                                TextField("optional", text: $suffixText)
                                    .textFieldStyle(.roundedBorder)
                            )
                        )
                    }

                    // Counter detail row
                    if includeCounter {
                        GroupBox("Shot Counter Settings") {
                            HStack(spacing: 24) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Start value").font(.caption).foregroundColor(.secondary)
                                    HStack {
                                        Button { counterStart = max(0, counterStart - counterStep) } label: { Image(systemName: "minus.circle") }
                                            .buttonStyle(.plain)
                                        Text("\(counterStart)")
                                            .font(.system(.body, design: .monospaced))
                                            .frame(minWidth: 40, alignment: .center)
                                        Button { counterStart += counterStep } label: { Image(systemName: "plus.circle") }
                                            .buttonStyle(.plain)
                                    }
                                }
                                Divider().frame(height: 40)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Step size").font(.caption).foregroundColor(.secondary)
                                    HStack {
                                        Button { counterStep = max(1, counterStep - 1) } label: { Image(systemName: "minus.circle") }
                                            .buttonStyle(.plain)
                                        Text("\(counterStep)")
                                            .font(.system(.body, design: .monospaced))
                                            .frame(minWidth: 40, alignment: .center)
                                        Button { counterStep += 1 } label: { Image(systemName: "plus.circle") }
                                            .buttonStyle(.plain)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Example sequence").font(.caption).foregroundColor(.secondary)
                                    Text((0..<4).map { buildName(episodeNumber: previewEpisodeNumber, sceneName: "10", counter: counterStart + $0 * counterStep) }.joined(separator: ", "))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // Info: names can still be generated without Scenes/Episodes registered —
                    // those components are simply left out, clips are numbered sequentially.
                    if projectManager.currentScenes.isEmpty && projectManager.currentEpisodes.isEmpty {
                        Label("No scenes or episodes registered yet. Names will still be generated using a single sequential counter across all clips.", systemImage: "info.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.callout)
                    }

                    if showSuccess {
                        Label("Done! Renamed \(generatedCount) VFX shots.", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.callout)
                    }
                }
                .padding(24)
            }

            Divider()

            // ── Action Footer ────────────────────────────────────────────────
            HStack {
                Text("This will overwrite the \"VFX Name\" field for all clips with a Record TC. If Scene No. is active, clips are grouped and counted per registered scene; otherwise all clips share one sequential counter.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320, alignment: .leading)

                Spacer()

                Button("Cancel") { dismiss() }
                    .liquidGlassButton(prominent: false)

                Button("Generate Names for all VFX Shots") {
                    generateNames()
                }
                .liquidGlassButton(prominent: true)
                .disabled(projectManager.currentMasterList.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 700, height: 540)
        .background(.background)
        .onAppear {
            loadSavedSchema()
            // Don't show the toggle as "on" for a component with no data to draw from.
            if projectManager.currentScenes.isEmpty { includeSceneNum = false }
            if projectManager.currentEpisodes.isEmpty { includeEpisodeNum = false }
        }
        .onDisappear {
            saveSchema()
        }
    }

    // MARK: - Persisted Schema

    // Loads the previously saved naming pattern for this project (if any), so
    // the user doesn't have to retype it every time this window is opened.
    private func loadSavedSchema() {
        guard let schema = project.vfxNameSchema else { return }
        prefixText = schema.prefixText
        includeEpisodeNum = schema.includeEpisodeNum
        episodeNumDigits = schema.episodeNumDigits
        episodeLabelText = schema.episodeLabelText
        includeSceneNum = schema.includeSceneNum
        sceneNumDigits = schema.sceneNumDigits
        includeCounter = schema.includeCounter
        counterDigits = schema.counterDigits
        counterStart = schema.counterStart
        counterStep = schema.counterStep
        suffixText = schema.suffixText
        sepPrefixEpisode = schema.sepPrefixEpisode
        sepEpisodeScene = schema.sepEpisodeScene
        sepSceneShot = schema.sepSceneShot
        sepShotSuffix = schema.sepShotSuffix
    }

    // Persists the current naming pattern into the project's metadata file,
    // so it's restored next time this window opens.
    private func saveSchema() {
        let schema = VfxNameSchema(
            prefixText: prefixText,
            includeEpisodeNum: includeEpisodeNum,
            episodeNumDigits: episodeNumDigits,
            episodeLabelText: episodeLabelText,
            includeSceneNum: includeSceneNum,
            sceneNumDigits: sceneNumDigits,
            includeCounter: includeCounter,
            counterDigits: counterDigits,
            counterStart: counterStart,
            counterStep: counterStep,
            suffixText: suffixText,
            sepPrefixEpisode: sepPrefixEpisode,
            sepEpisodeScene: sepEpisodeScene,
            sepSceneShot: sepSceneShot,
            sepShotSuffix: sepShotSuffix
        )
        projectManager.updateVfxNameSchema(projectId: project.id, schema: schema)
    }

    @ViewBuilder
    private func separatorConnector(_ text: Binding<String>) -> some View {
        VStack(spacing: 4) {
            Text("Sep")
                .font(.caption2)
                .foregroundColor(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 36)
        }
        .padding(.top, 22)
    }

    @ViewBuilder
    private func schemaBlock(title: String, subtitle: String, content: AnyView) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption).bold()
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            content
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(Color.secondary.opacity(0.7))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .liquidGlassPanel(cornerRadius: 8)
    }

    private func buildName(episodeNumber: Int?, sceneName: String, counter: Int) -> String {
        var str = ""
        if !prefixText.isEmpty { str += prefixText }

        str += sepPrefixEpisode
        if effectiveIncludeEpisodeNum, let epNum = episodeNumber {
            let token = episodeNumDigits > 0 ? String(format: "%0\(episodeNumDigits)d", epNum) : "\(epNum)"
            str += episodeLabelText + token
        }

        str += sepEpisodeScene
        if effectiveIncludeSceneNum {
            if sceneNumDigits > 0, let scnInt = Int(sceneName) {
                str += String(format: "%0\(sceneNumDigits)d", scnInt)
            } else {
                str += sceneName
            }
        }

        str += sepSceneShot
        if includeCounter {
            str += String(format: "%0\(counterDigits)d", counter)
        }

        str += sepShotSuffix
        if !suffixText.isEmpty { str += suffixText }

        return str.isEmpty ? "—" : str
    }

    private func getScene(for tc: String) -> String? {
        SceneData.matchedSceneName(for: tc, in: projectManager.currentScenes)
    }

    private func generateNames() {
        ConsoleLogger.shared.log("Starting VFX Name Generation...")

        let oldMasterList = projectManager.currentMasterList
        // One counter per distinct grouping actually active in the schema — resets to
        // `counterStart` whenever the episode and/or scene changes, for whichever of the two
        // are enabled. With neither enabled, every clip shares the same ("") key, i.e. the old
        // flat/global counter. Previously only the "both enabled" and "scene only" cases reset
        // correctly — "episode only" (no Scene component in the schema) fell through to a single
        // counter shared across every episode instead of restarting at each one.
        var counters: [String: Int] = [:]
        var generated = 0

        // Ensure clips are sorted chronologically by their Record TC In
        let sortedIndices = projectManager.currentMasterList.indices.sorted { idx1, idx2 in
            let tc1 = projectManager.currentMasterList[idx1].tcIn
            let tc2 = projectManager.currentMasterList[idx2].tcIn
            return tc1 < tc2
        }

        for i in sortedIndices {
            let tc = projectManager.currentMasterList[i].tcIn
            if tc.isEmpty { continue }

            // Per-clip Episode number, extracted from the "Episode" column that
            // DaVinci indexing fills in automatically (matched via Episode Manager).
            var episodeNumber: Int? = nil
            if effectiveIncludeEpisodeNum {
                episodeNumber = Int(projectManager.currentMasterList[i].dict["Episode"] ?? "")
                if episodeNumber == nil {
                    ConsoleLogger.shared.log("NOTE: Clip [\(tc)] has no matched Episode metadata — omitting episode token.")
                }
            }

            var sceneName: String? = nil
            if effectiveIncludeSceneNum {
                guard let matched = getScene(for: tc) else {
                    ConsoleLogger.shared.log("WARNING: Clip [\(tc)] did not match any registered Scene. Skipping.")
                    continue
                }
                sceneName = matched
            }

            var counterKey = ""
            if effectiveIncludeEpisodeNum { counterKey += "E:\(episodeNumber.map(String.init) ?? "none")" }
            if effectiveIncludeSceneNum { counterKey += "|S:\(sceneName ?? "")" }

            let currentCount = counters[counterKey] ?? counterStart
            let newName = buildName(episodeNumber: episodeNumber, sceneName: sceneName ?? "", counter: currentCount)

            let sceneLog = sceneName.map { " in Scene \($0)" } ?? ""
            ConsoleLogger.shared.log("Clip [\(tc)]\(sceneLog) -> Assigning VFX Name: \(newName)")
            projectManager.currentMasterList[i].vfxName = newName
            counters[counterKey] = currentCount + counterStep
            generated += 1
        }

        if generated > 0 {
            ConsoleLogger.shared.log("Successfully generated \(generated) VFX Names!")
            projectManager.saveMasterList()
            projectManager.registerUndo(\.currentMasterList, actionName: "Generate VFX Names", from: oldMasterList) {
                self.projectManager.saveMasterList()
            }
            generatedCount = generated
            showSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { dismiss() }
        } else {
            ConsoleLogger.shared.log("No VFX Names were generated. Please check your tracking data.")
        }
    }
}
