import SwiftUI

// One row of the master list that exists locally but wasn't matched to anything on the other
// side — a candidate to push out. For Sheet Sync this is the whole story for a local-only row;
// for the DaVinci/CSV import flow local-only rows are handled as `.missing` MergeItems instead
// (see `MergeManager.missingItems`), so `pushCandidates` stays empty there.
struct PushCandidate: Identifiable {
    let id = UUID()
    let clip: ClipData
    var selected: Bool = true
}

// Shared review window for both the DaVinci Resolve/CSV import merge and Sheet Sync's "Compare
// Now" — same layout, same matching model (MergeManager.compareColumnAware), so switching
// between the two feels like the same tool: every shot found is listed, matches are green and
// collapsible, anything the matcher couldn't confidently pair floats in an "Unlinked" pool for
// manual relinking or explicit "declare as new", and every remaining per-column discrepancy is
// resolved one direction or the other before Resync unlocks.
struct SyncReviewView: View {
    @Binding var mergeItems: [MergeItem]
    let allMasterClips: [ClipData]
    let sourceLabel: String
    /// true = Sheet Sync (bidirectional — local-only rows can be pushed out); false = DaVinci/CSV
    /// import (one-way — local-only rows instead surface as `.missing` items in `mergeItems`).
    let supportsPush: Bool
    @Binding var pushCandidates: [PushCandidate]
    let onApply: () -> Void
    let onCancel: () -> Void

    @State private var hideMatching = false
    @State private var relinkTarget: UUID? = nil
    private let columnWidth: CGFloat = 150

    private var unlinkedItems: [MergeItem] { mergeItems.filter { $0.state == .new } }
    private var conflictItems: [MergeItem] { mergeItems.filter { $0.state == .modified || $0.state == .missing } }
    private var matchedItems: [MergeItem] { mergeItems.filter { $0.state == .identical } }

    private var allColumns: [String] {
        MergeManager.orderedColumns(for: mergeItems.flatMap { [$0.masterClip, $0.importedClip].compactMap { $0 } })
    }

    private var allResolved: Bool { mergeItems.allSatisfy(\.isResolved) }

    private var changeCount: Int {
        mergeItems.filter { item in
            switch item.state {
            case .identical: return false
            case .modified: return item.fieldWinners.values.contains(.incoming)
            case .new: return item.confirmedNew
            case .missing: return item.missingResolution == .markRemoved
            }
        }.count + pushCandidates.filter(\.selected).count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    unlinkedSection
                    conflictsSection
                    if supportsPush { pushSection }
                    matchedSection

                    if unlinkedItems.isEmpty && conflictItems.isEmpty && matchedItems.isEmpty
                        && (!supportsPush || pushCandidates.isEmpty) {
                        Text("Nothing found to sync.")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .padding()
            }

            Divider()
            footer
        }
        .frame(minWidth: 880, minHeight: 620)
        .onAppear { reconcilePushCandidates() }
        .onChange(of: mergeItems) { _ in reconcilePushCandidates() }
        .sheet(item: relinkBinding) { item in
            RelinkPickerSheet(
                candidates: MergeManager.unclaimedMasterClips(master: allMasterClips, mergeItems: mergeItems),
                suggested: item.candidateMasterClips,
                onPick: { master in link(itemId: item.id, to: master) },
                onCancel: { relinkTarget = nil }
            )
        }
    }

    // A small Identifiable wrapper so `.sheet(item:)` can present the picker for whichever
    // unlinked item's Link button was pressed.
    private var relinkBinding: Binding<IdentifiedMergeItem?> {
        Binding(
            get: { relinkTarget.flatMap { id in mergeItems.first { $0.id == id } }.map(IdentifiedMergeItem.init) },
            set: { relinkTarget = $0?.id }
        )
    }

    // MARK: - Header / Footer

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sync Review").font(.title2).bold()
                Text(sourceLabel).font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 16) {
                Label("\(unlinkedItems.count) Unlinked", systemImage: "questionmark.circle.fill")
                    .foregroundColor(unlinkedItems.isEmpty ? .secondary : .orange)
                Label("\(conflictItems.count) Conflicts", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(conflictItems.isEmpty ? .secondary : .red)
                Label("\(matchedItems.count) Matched", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            .font(.subheadline)
        }
        .padding()
        .liquidGlassBar()
    }

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel) { onCancel() }
                .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            if !allResolved {
                Text("Resolve every unlinked shot and conflict to continue")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button("Resync \(changeCount) Change\(changeCount == 1 ? "" : "s")") { onApply() }
                .liquidGlassButton(prominent: true)
                .disabled(!allResolved)
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Unlinked pool

    @ViewBuilder
    private var unlinkedSection: some View {
        if !unlinkedItems.isEmpty {
            section(title: "Unlinked — needs a match", systemImage: "questionmark.circle.fill", color: .orange) {
                VStack(spacing: 0) {
                    ForEach(unlinkedItems) { item in
                        unlinkedRow(item: item)
                        Divider()
                    }
                }
            }
        }
    }

    private func unlinkedRow(item: MergeItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.importedClip?.vfxName ?? "").bold()
                if !item.candidateMasterClips.isEmpty {
                    Text("\(item.candidateMasterClips.count) similar shot(s) found — review before linking")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if item.confirmedNew {
                Label("New Shot", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Button("Undo") { setConfirmedNew(itemId: item.id, false) }
                    .buttonStyle(.plain)
                    .font(.caption)
            } else {
                Button { relinkTarget = item.id } label: {
                    Label("Link…", systemImage: "link")
                }
                .liquidGlassButton(prominent: false)
                .controlSize(.small)

                Button("Declare as New Shot") { setConfirmedNew(itemId: item.id, true) }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Conflicts

    @ViewBuilder
    private var conflictsSection: some View {
        if !conflictItems.isEmpty {
            section(title: "Conflicts — resolve each difference", systemImage: "exclamationmark.triangle.fill", color: .red) {
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 18) {
                        columnHeaderRow
                        ForEach(conflictItems) { item in
                            if item.state == .modified {
                                conflictPair(itemId: item.id)
                            } else {
                                missingPair(itemId: item.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private var columnHeaderRow: some View {
        HStack(spacing: 0) {
            Text("").frame(width: 90, alignment: .leading) // gutter for row labels/actions
            ForEach(allColumns, id: \.self) { col in
                Text(col).font(.caption).bold().foregroundColor(.secondary)
                    .frame(width: columnWidth, alignment: .leading)
            }
        }
    }

    private func itemBinding(_ id: UUID) -> Binding<MergeItem> {
        guard let idx = mergeItems.firstIndex(where: { $0.id == id }) else {
            return .constant(MergeItem(state: .new))
        }
        return $mergeItems[idx]
    }

    private func conflictPair(itemId: UUID) -> some View {
        let item = itemBinding(itemId)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(item.wrappedValue.importedClip?.vfxName ?? "").bold()
                if let confidence = item.wrappedValue.matchConfidence {
                    Text("via \(confidence.label)").font(.caption2).foregroundColor(.secondary)
                } else if let score = item.wrappedValue.matchColumnScore {
                    Text("via \(score) shared column\(score == 1 ? "" : "s")").font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Button("Accept All Incoming") { resolveAll(itemId: itemId, winner: .incoming) }
                    .font(.caption).buttonStyle(.plain).foregroundColor(.accentColor)
                Button("Keep All Local") { resolveAll(itemId: itemId, winner: .master) }
                    .font(.caption).buttonStyle(.plain).foregroundColor(.accentColor)
                Button { breakLink(itemId: itemId) } label: {
                    Label("Break Link", systemImage: "link.badge.plus")
                }
                .buttonStyle(.plain).font(.caption).foregroundColor(.red)
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Incoming").font(.caption2).foregroundColor(.secondary)
                    Text("Local").font(.caption2).foregroundColor(.secondary)
                }
                .frame(width: 90, alignment: .leading)

                ForEach(allColumns, id: \.self) { col in
                    conflictCell(item: item, key: col)
                }
            }
        }
        .padding(8)
        .liquidGlassPanel(cornerRadius: 8)
    }

    @ViewBuilder
    private func conflictCell(item: Binding<MergeItem>, key: String) -> some View {
        let differs = item.wrappedValue.diffKeys.contains(key)
        let incoming = item.wrappedValue.importedClip?.dict[key] ?? ""
        let local = item.wrappedValue.masterClip?.dict[key] ?? ""
        let winner = item.wrappedValue.fieldWinners[key]

        VStack(alignment: .leading, spacing: 2) {
            Text(incoming.isEmpty ? "–" : incoming)
                .font(.caption)
                .strikethrough(differs && winner == .master)
                .foregroundColor(differs && winner == .master ? .secondary : .primary)

            if differs {
                HStack(spacing: 6) {
                    Button { setWinner(itemId: item.wrappedValue.id, key: key, winner: .incoming) } label: {
                        Image(systemName: winner == .incoming ? "arrow.down.circle.fill" : "arrow.down.circle")
                    }
                    .help("Overwrite local with incoming value")
                    Button { setWinner(itemId: item.wrappedValue.id, key: key, winner: .master) } label: {
                        Image(systemName: winner == .master ? "arrow.up.circle.fill" : "arrow.up.circle")
                    }
                    .help("Keep local value, reject incoming")
                }
                .buttonStyle(.plain)
                .foregroundColor(winner == nil ? .red : .accentColor)
            } else {
                Color.clear.frame(height: 14)
            }

            Text(local.isEmpty ? "–" : local)
                .font(.caption)
                .strikethrough(differs && winner == .incoming)
                .foregroundColor(differs && winner == .incoming ? .secondary : .primary)
        }
        .padding(4)
        .frame(width: columnWidth, alignment: .leading)
        .background(differs ? Color.red.opacity(winner == nil ? 0.15 : 0.05) : Color.clear)
        .cornerRadius(4)
    }

    private func missingPair(itemId: UUID) -> some View {
        let item = itemBinding(itemId)
        let resolution = item.wrappedValue.missingResolution
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.wrappedValue.masterClip?.vfxName ?? "").bold()
                Text("not found in \(sourceLabel)").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Button("Keep") { setMissingResolution(itemId: itemId, .keep) }
                    .controlSize(.small)
                    .liquidGlassButton(prominent: resolution == .keep)
                Button("Mark Removed") { setMissingResolution(itemId: itemId, .markRemoved) }
                    .controlSize(.small)
                    .liquidGlassButton(prominent: resolution == .markRemoved)
                    .tint(.red)
            }
            HStack(spacing: 0) {
                Text("Local").font(.caption2).foregroundColor(.secondary).frame(width: 90, alignment: .leading)
                ForEach(allColumns, id: \.self) { col in
                    Text(item.wrappedValue.masterClip?.dict[col].flatMap { $0.isEmpty ? nil : $0 } ?? "–")
                        .font(.caption)
                        .strikethrough(resolution == .markRemoved)
                        .foregroundColor(resolution == .markRemoved ? .secondary : .primary)
                        .frame(width: columnWidth, alignment: .leading)
                }
            }
        }
        .padding(8)
        .background(Color.red.opacity(resolution == nil ? 0.12 : 0.04))
        .cornerRadius(8)
    }

    // MARK: - Matched

    @ViewBuilder
    private var matchedSection: some View {
        if !matchedItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("\(matchedItems.count) Matched", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundColor(.green)
                    Spacer()
                    Button(hideMatching ? "Show Matching" : "Hide Matching") { hideMatching.toggle() }
                        .controlSize(.small)
                }
                if !hideMatching {
                    VStack(spacing: 0) {
                        ForEach(matchedItems) { item in
                            HStack {
                                Text(item.importedClip?.vfxName ?? "")
                                Spacer()
                                Text("Identical").font(.caption)
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Push (Sheet Sync only)

    @ViewBuilder
    private var pushSection: some View {
        if !pushCandidates.isEmpty {
            section(title: "New in Resolver — push to \(sourceLabel)", systemImage: "arrow.up.circle.fill", color: .blue) {
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
    }

    // MARK: - Actions

    private func mutate(itemId: UUID, _ body: (inout MergeItem) -> Void) {
        guard let idx = mergeItems.firstIndex(where: { $0.id == itemId }) else { return }
        body(&mergeItems[idx])
    }

    private func setWinner(itemId: UUID, key: String, winner: FieldSide) {
        mutate(itemId: itemId) { item in
            if item.fieldWinners[key] == winner {
                item.fieldWinners.removeValue(forKey: key) // toggle back to unresolved
            } else {
                item.fieldWinners[key] = winner
            }
        }
    }

    private func resolveAll(itemId: UUID, winner: FieldSide) {
        mutate(itemId: itemId) { item in
            for key in item.diffKeys { item.fieldWinners[key] = winner }
        }
    }

    private func setConfirmedNew(itemId: UUID, _ value: Bool) {
        mutate(itemId: itemId) { $0.confirmedNew = value }
    }

    private func setMissingResolution(itemId: UUID, _ value: MissingResolution) {
        mutate(itemId: itemId) { item in
            item.missingResolution = item.missingResolution == value ? nil : value
        }
    }

    private func breakLink(itemId: UUID) {
        mutate(itemId: itemId) { item in
            item.masterClip = nil
            item.state = .new
            item.fieldWinners = [:]
            item.matchConfidence = nil
            item.matchColumnScore = nil
            item.confirmedNew = false
        }
    }

    private func link(itemId: UUID, to masterClip: ClipData) {
        mutate(itemId: itemId) { item in
            item.masterClip = masterClip
            item.fieldWinners = [:]
            item.confirmedNew = false
            if let imp = item.importedClip {
                item.state = MergeManager.diffKeys(master: masterClip, imported: imp).isEmpty ? .identical : .modified
            }
        }
        relinkTarget = nil
    }

    private func reconcilePushCandidates() {
        guard supportsPush else { return }
        let unclaimed = MergeManager.unclaimedMasterClips(master: allMasterClips, mergeItems: mergeItems)
        let existing = Dictionary(uniqueKeysWithValues: pushCandidates.map { ($0.clip.id, $0) })
        let reconciled = unclaimed.map { existing[$0.id] ?? PushCandidate(clip: $0) }
        if reconciled.map(\.clip.id) != pushCandidates.map(\.clip.id) || reconciled.count != pushCandidates.count {
            pushCandidates = reconciled
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

private struct IdentifiedMergeItem: Identifiable {
    let item: MergeItem
    var id: UUID { item.id }
    var candidateMasterClips: [ClipData] { item.candidateMasterClips }
    init(_ item: MergeItem) { self.item = item }
}

private struct RelinkPickerSheet: View {
    let candidates: [ClipData]
    let suggested: [ClipData]
    let onPick: (ClipData) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [ClipData] {
        guard !searchText.isEmpty else { return candidates }
        return candidates.filter { $0.vfxName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Link to Existing Shot").font(.title2).bold()
                Spacer()
            }

            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search VFX Name...", text: $searchText).textFieldStyle(.plain)
            }
            .padding(8)
            .liquidGlassPanel(cornerRadius: 8)

            List {
                if !suggested.isEmpty && searchText.isEmpty {
                    Section("Suggested") {
                        ForEach(suggested) { clip in
                            Button { onPick(clip); dismiss() } label: {
                                Text(clip.vfxName)
                            }
                        }
                    }
                }
                Section(suggested.isEmpty ? "All Unlinked Master Shots" : "All") {
                    ForEach(filtered) { clip in
                        Button { onPick(clip); dismiss() } label: {
                            Text(clip.vfxName)
                        }
                    }
                }
            }
            .frame(minHeight: 300)

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { onCancel(); dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
            }
        }
        .padding()
        .frame(width: 420, height: 480)
    }
}
