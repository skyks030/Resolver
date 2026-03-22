import SwiftUI

struct VfxNameGeneratorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var projectManager: ProjectManager
    let project: Project

    // Schema parts
    @State private var prefixText = ""
    @State private var includeSceneNum = true
    @State private var sceneNumDigits = 3
    @State private var separatorText = "_"
    @State private var includeCounter = true
    @State private var counterDigits = 3
    @State private var counterStart = 10
    @State private var counterStep = 10
    @State private var suffixText = ""

    // Status
    @State private var generatedCount = 0
    @State private var showSuccess = false
    @State private var noScenesWarning = false

    // Live preview
    var previewName: String {
        buildName(sceneName: "10", counter: counterStart)
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
                    .background(Color.accentColor.opacity(0.08))
                    .cornerRadius(8)
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

                    // Row: Prefix | Scene | Separator | Counter | Suffix
                    HStack(alignment: .top, spacing: 12) {
                        schemaBlock(
                            title: "Prefix",
                            subtitle: "e.g. \"VFX_\"",
                            content: AnyView(
                                TextField("e.g. VFX_", text: $prefixText)
                                    .textFieldStyle(.roundedBorder)
                            )
                        )

                        Image(systemName: "plus").foregroundColor(.secondary).padding(.top, 32)

                        schemaBlock(
                            title: "Scene No.",
                            subtitle: sceneNumDigits == 0 ? "Raw  (e.g. 5)" : "\(sceneNumDigits) digits (e.g. \(String(format: "%0\(sceneNumDigits)d", 5)))",
                            content: AnyView(
                                VStack(spacing: 6) {
                                    Toggle("", isOn: $includeSceneNum).labelsHidden()
                                    if includeSceneNum {
                                        Stepper("\(sceneNumDigits) digits", value: $sceneNumDigits, in: 0...5)
                                            .labelsHidden()
                                        Text("\(sceneNumDigits) digits")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            )
                        )

                        Image(systemName: "plus").foregroundColor(.secondary).padding(.top, 32)

                        schemaBlock(
                            title: "Separator",
                            subtitle: "e.g. \"_\" or \"-\"",
                            content: AnyView(
                                TextField("_", text: $separatorText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 60)
                            )
                        )

                        Image(systemName: "plus").foregroundColor(.secondary).padding(.top, 32)

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

                        Image(systemName: "plus").foregroundColor(.secondary).padding(.top, 32)

                        schemaBlock(
                            title: "Suffix",
                            subtitle: "e.g. \"_v01\"",
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
                                    Text((0..<4).map { buildName(sceneName: "10", counter: counterStart + $0 * counterStep) }.joined(separator: ", "))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // Scenes warning
                    if noScenesWarning {
                        Label("No scenes registered. Add scenes via \"Manage Scenes\" to use this generator.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
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
                Text("This will overwrite the \"VFX Name\" field for all clips that can be mapped to a registered scene via their Record TC.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320, alignment: .leading)

                Spacer()

                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)

                Button("Generate Names for all VFX Shots") {
                    generateNames()
                }
                .buttonStyle(.borderedProminent)
                .disabled(projectManager.currentScenes.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 700, height: 540)
        .background(.background)
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
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
    }

    private func buildName(sceneName: String, counter: Int) -> String {
        var str = ""
        if !prefixText.isEmpty { str += prefixText }
        if includeSceneNum {
            if sceneNumDigits > 0, let scnInt = Int(sceneName) {
                str += String(format: "%0\(sceneNumDigits)d", scnInt)
            } else {
                str += sceneName
            }
        }
        if !separatorText.isEmpty { str += separatorText }
        if includeCounter {
            str += String(format: "%0\(counterDigits)d", counter)
        }
        if !suffixText.isEmpty { str += suffixText }
        return str.isEmpty ? "—" : str
    }

    private func getScene(for tc: String) -> String? {
        var matchedName: String? = nil
        let cleanTC = tc.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTC.isEmpty { return nil }
        for scene in projectManager.currentScenes {
            if cleanTC >= scene.startTC { matchedName = scene.name } else { break }
        }
        return matchedName
    }

    private func generateNames() {
        noScenesWarning = projectManager.currentScenes.isEmpty
        if noScenesWarning { return }

        var sceneCounters: [String: Int] = [:]
        var generated = 0

        for i in 0..<projectManager.currentMasterList.count {
            let tc = projectManager.currentMasterList[i].dict["Record TC"] ?? ""
            if let sceneName = getScene(for: tc) {
                let currentCount = sceneCounters[sceneName] ?? counterStart
                let newName = buildName(sceneName: sceneName, counter: currentCount)
                projectManager.currentMasterList[i].vfxName = newName
                sceneCounters[sceneName] = currentCount + counterStep
                generated += 1
            }
        }

        if generated > 0 {
            projectManager.saveMasterList()
            generatedCount = generated
            showSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { dismiss() }
        }
    }
}
