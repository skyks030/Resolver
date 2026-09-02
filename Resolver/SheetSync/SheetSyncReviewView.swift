import SwiftUI

// One row of the master list that exists locally but wasn't matched to anything in the linked
// sheet — a candidate to push out, not something MergeManager.smartCompare produces on its own
// (that only classifies the *imported*/remote side).
struct PushCandidate: Identifiable {
    let id = UUID()
    let clip: ClipData
    var selected: Bool = true
}

enum SheetSyncError: LocalizedError {
    case noResponse
    case remote(String)
    case unexpected

    var errorDescription: String? {
        switch self {
        case .noResponse: return "No response from the sync script. Check Debug Mode for details."
        case .remote(let message): return message
        case .unexpected: return "Unexpected response from the sync script. Check Debug Mode for details."
        }
    }
}

// Sheet Sync is bidirectional — either side can be the one that's correct — so unlike
// MergeReviewView (always "accept incoming or skip", right for a one-way DaVinci/CSV import) this
// is a purpose-built three-section review: push local-only rows out, pull remote-only rows in,
// and for rows present on both sides but different, choose per row which value wins. Reuses
// MergeManager.smartCompare's classification/diffing untouched — only the review UI is new.
struct SheetSyncReviewView: View {
    @Binding var mergeItems: [MergeItem]
    @Binding var pushCandidates: [PushCandidate]
    let providerName: String
    let onApply: () -> Void
    let onCancel: () -> Void

    private var newRemoteItems: [MergeItem] { mergeItems.filter { $0.state == .new } }
    private var modifiedItems: [MergeItem] { mergeItems.filter { $0.state == .modified } }

    private var pushCount: Int { pushCandidates.filter { $0.selected }.count }
    private var pullCount: Int { mergeItems.filter { $0.state == .new && $0.selected }.count }
    private var useRemoteCount: Int { mergeItems.filter { $0.state == .modified && $0.selected }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sheet Sync Review")
                    .font(.title2)
                    .bold()
                Spacer()
                Text(providerName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .liquidGlassBar()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !pushCandidates.isEmpty {
                        section(title: "New in Resolver — push to \(providerName)", systemImage: "arrow.up.circle.fill", color: .green) {
                            ForEach($pushCandidates) { $candidate in
                                HStack {
                                    Toggle("", isOn: $candidate.selected).labelsHidden()
                                    Text(candidate.clip.vfxName).bold()
                                    Text(candidate.clip.tcIn).font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                }
                            }
                        }
                    }

                    if !newRemoteItems.isEmpty {
                        section(title: "New in \(providerName) — pull into Resolver", systemImage: "arrow.down.circle.fill", color: .blue) {
                            ForEach($mergeItems) { $item in
                                if item.state == .new {
                                    HStack {
                                        Toggle("", isOn: $item.selected).labelsHidden()
                                        Text(item.importedClip.vfxName).bold()
                                        Text(item.importedClip.tcIn).font(.caption).foregroundColor(.secondary)
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }

                    if !modifiedItems.isEmpty {
                        section(title: "Different on both sides — choose per row", systemImage: "arrow.left.arrow.right.circle.fill", color: .orange) {
                            ForEach($mergeItems) { $item in
                                if item.state == .modified {
                                    modifiedRow(item: $item)
                                    Divider()
                                }
                            }
                        }
                    }

                    if pushCandidates.isEmpty && newRemoteItems.isEmpty && modifiedItems.isEmpty {
                        Text("Everything already matches — nothing to sync.")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Text("Push \(pushCount) · Pull \(pullCount) · Use \(providerName) for \(useRemoteCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Apply Sync") { onApply() }
                    .liquidGlassButton(prominent: true)
                    .disabled(pushCount == 0 && pullCount == 0 && useRemoteCount == 0)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 550)
    }

    @ViewBuilder
    private func modifiedRow(item: Binding<MergeItem>) -> some View {
        if let master = item.wrappedValue.masterClip {
            let imported = item.wrappedValue.importedClip
            let diffKeys = Set(master.dict.keys).union(imported.dict.keys)
                .filter { (master.dict[$0] ?? "") != (imported.dict[$0] ?? "") }
                .sorted()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(imported.vfxName).bold()
                    Spacer()
                    Picker("", selection: item.selected) {
                        Text("Keep Local").tag(false)
                        Text("Use \(providerName)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    .labelsHidden()
                }
                ForEach(diffKeys, id: \.self) { key in
                    HStack {
                        Text("\(key):").font(.caption).bold().foregroundColor(.secondary)
                        Text(master.dict[key] ?? "").font(.caption).strikethrough(item.wrappedValue.selected).foregroundColor(.red)
                        Image(systemName: "arrow.right").font(.caption2).foregroundColor(.secondary)
                        Text(imported.dict[key] ?? "").font(.caption).foregroundColor(.green)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, systemImage: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundColor(color)
            content()
        }
        .padding()
        .liquidGlassPanel(cornerRadius: 8)
    }
}
