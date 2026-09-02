import SwiftUI

// Shared review window for both the DaVinci Resolve/CSV import merge and Sheet Sync's "Compare
// Now" — same layout, same matching model (MergeManager.compareColumnAware), so switching
// between the two feels like the same tool: every shot found is listed together (whether it
// matched perfectly, still has a discrepancy, or couldn't be paired at all), anything the matcher
// couldn't confidently pair floats in a "Needs a Match" pool — split by which side it came
// from — for manual relinking or an explicit new/removed declaration, and every remaining
// per-column discrepancy is resolved one direction or the other before Resync unlocks.
struct SyncReviewView: View {
    @Binding var mergeItems: [MergeItem]
    let allMasterClips: [ClipData]
    let sourceLabel: String
    /// true = Sheet Sync (bidirectional — a local-only shot can be pushed out to the remote
    /// sheet); false = DaVinci/CSV import (one-way — a local-only shot can only be kept or
    /// flagged removed, there's nowhere to push it to).
    let supportsPush: Bool
    /// Columns never treated as a discrepancy in this review — e.g. "VFX Name" for a DaVinci
    /// Resolve import, which never carries one at all. Defaults to none (Sheet Sync's call site
    /// doesn't pass this — a spreadsheet can legitimately carry a real VFX Name).
    var ignoredDiffKeys: Set<String> = []
    let onApply: () -> Void
    let onCancel: () -> Void

    // Hides every item with no remaining discrepancy — not just `.identical` matches, but any
    // `.modified`/`.new`/`.missing` item the user has fully resolved too — so cleaning up the
    // last field on a conflict makes it disappear immediately, same as a plain match, letting
    // the list progressively narrow down to only what still needs attention.
    @State private var hideResolved = false
    @State private var relinkTarget: UUID? = nil
    // Which "Needs a Match — VFX Master List" row's Link… button was pressed, to link it to an
    // unmatched *remote* item instead (the mirror of `relinkTarget`, which links an unmatched
    // remote item to a master clip).
    @State private var relinkMasterTarget: UUID? = nil
    // Multi-select for the Conflicts grid — resolving one field for a shot that's part of the
    // current selection applies that same direction to the same column on every other selected
    // shot with a conflict there too (e.g. a batch VFX-Name rename affecting many shots at once).
    // Anchor-based shift-click range select, same pattern used for the master list's own rows.
    @State private var selectedConflictIds: Set<UUID> = []
    @State private var lastSelectedConflictId: UUID? = nil
    private let columnWidth: CGFloat = 150
    private let gutterWidth: CGFloat = 112
    // Consistent color coding wherever the two sides are stacked, so which physical row is which
    // is obvious at a glance without reading the label every time.
    private let remoteColor = Color.blue
    private let masterColor = Color.purple

    // "Needs a Match" groups both sides of what the matcher couldn't pair up at all — an
    // unmatched remote/imported shot and an unmatched master shot are the same *kind* of problem
    // (nothing to compare against yet), just from opposite sides, so they're shown together up
    // top instead of the master-side half being buried among genuine field-level conflicts.
    private var unmatchedRemoteItems: [MergeItem] { mergeItems.filter { $0.state == .new } }
    // Includes Sheet Sync's local-only shots too now (see MergeManager.missingItems and
    // SheetSyncView.compareNow) — a shot the matcher can't currently pair up is the same kind of
    // problem regardless of *why* nothing on the other side matches it.
    private var unmatchedMasterItems: [MergeItem] { mergeItems.filter { $0.state == .missing } }
    // Every shot the matcher *did* successfully pair — shown together, in the same row-pair
    // layout, whether it's a still-open conflict or a clean match, so resolving the last field on
    // a conflict just turns it green in place rather than relocating it to a separate section.
    private var comparedItems: [MergeItem] { mergeItems.filter { $0.state == .modified || $0.state == .identical } }
    // Header-badge counts: "still needs a decision" vs. "currently clean" — both live-updating as
    // fields get resolved, unlike `comparedItems` itself which never reorders/splits.
    private var unresolvedConflictItems: [MergeItem] { mergeItems.filter { $0.state == .modified && !$0.isResolved } }
    private var resolvedCompareItems: [MergeItem] { comparedItems.filter(\.isResolved) }

    /// `hideResolved`-filtered versions of the groups above — what actually gets rendered.
    /// A fully-resolved compared item (identical, or a conflict with every field decided) is what
    /// subsumed the old "Hide Matching" behavior: turning this on empties it out of the list
    /// along with everything else that's clean.
    private func visible(_ items: [MergeItem]) -> [MergeItem] { hideResolved ? items.filter { !$0.isResolved } : items }
    private var visibleUnmatchedRemote: [MergeItem] { visible(unmatchedRemoteItems) }
    private var visibleUnmatchedMaster: [MergeItem] { visible(unmatchedMasterItems) }
    private var visibleComparedItems: [MergeItem] { visible(comparedItems) }

    private var allColumns: [String] {
        MergeManager.orderedColumns(for: mergeItems.flatMap { [$0.masterClip, $0.importedClip].compactMap { $0 } })
    }

    /// `allColumns`, but with every column that still has an unresolved conflict pulled forward
    /// (right after VFX Name, which always leads) — so scanning left-to-right always surfaces
    /// what still needs a decision before scrolling through untouched/already-resolved columns.
    private var displayColumns: [String] {
        let cols = allColumns
        let conflictCols = Set(unresolvedConflictItems.flatMap(\.diffKeys))
        var result: [String] = []
        if cols.contains("VFX Name") { result.append("VFX Name") }
        let rest = cols.filter { $0 != "VFX Name" }
        result += rest.filter { conflictCols.contains($0) }
        result += rest.filter { !conflictCols.contains($0) }
        return result
    }

    /// A clip's VFX Name if it has one; otherwise a fallback built from its source file and
    /// Record TC In, so a shot is never shown with a blank title — e.g. every shot on the import
    /// side of a DaVinci Resolve index, which never carries a VFX Name at all.
    private func displayName(for clip: ClipData?) -> String {
        guard let clip else { return "" }
        if !clip.vfxName.isEmpty { return clip.vfxName }
        let file = clip.fileNames, tc = clip.tcIn
        if file.isEmpty { return tc }
        if tc.isEmpty { return file }
        return "\(file) @ \(tc)"
    }

    private var allResolved: Bool { mergeItems.allSatisfy(\.isResolved) }

    /// How many resolved items will actually change the local VFX Master List on Resync.
    private var localChangeCount: Int {
        mergeItems.filter { item in
            switch item.state {
            case .identical: return false
            case .modified: return item.fieldWinners.values.contains(.incoming)
            case .new: return item.confirmedNew
            case .missing: return item.missingResolution == .markRemoved
            }
        }.count
    }

    /// How many resolved items will push a change out to the remote sheet — Sheet Sync only
    /// (DaVinci/CSV import has no remote to write back to). A `.modified` pair counts if at least
    /// one field was resolved toward "keep local" (`.master`); a `.missing` (local-only) shot
    /// counts if resolved as "Push" (the Sheet Sync framing of `.keep` — see `missingRow`).
    private var remoteChangeCount: Int {
        guard supportsPush else { return 0 }
        let modifiedPushes = mergeItems.filter { $0.state == .modified && $0.fieldWinners.values.contains(.master) }.count
        let missingPushes = mergeItems.filter { $0.state == .missing && $0.missingResolution == .keep }.count
        return modifiedPushes + missingPushes
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    needsMatchSection
                    comparedSection

                    if visibleUnmatchedRemote.isEmpty && visibleUnmatchedMaster.isEmpty && visibleComparedItems.isEmpty {
                        Group {
                            if hideResolved && !mergeItems.isEmpty {
                                Text("Everything is resolved. Turn off \"Hide Resolved\" to review it again, or Resync below.")
                            } else {
                                Text("Nothing found to sync.")
                            }
                        }
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
        .sheet(item: relinkBinding) { item in
            RelinkPickerSheet(
                candidates: MergeManager.unclaimedMasterClips(master: allMasterClips, mergeItems: mergeItems),
                suggested: item.candidateMasterClips,
                onPick: { master in link(itemId: item.id, to: master) },
                onCancel: { relinkTarget = nil }
            )
        }
        .sheet(item: relinkMasterBinding) { item in
            RelinkToRemoteSheet(
                candidates: unmatchedRemoteItems,
                displayName: { displayName(for: $0.importedClip) },
                onPick: { remoteItem in
                    link(itemId: remoteItem.id, to: item.masterClipForLink)
                    relinkMasterTarget = nil
                },
                onCancel: { relinkMasterTarget = nil }
            )
        }
    }

    // Small Identifiable wrappers so `.sheet(item:)` can present the picker for whichever row's
    // Link button was pressed.
    private var relinkBinding: Binding<IdentifiedMergeItem?> {
        Binding(
            get: { relinkTarget.flatMap { id in mergeItems.first { $0.id == id } }.map(IdentifiedMergeItem.init) },
            set: { relinkTarget = $0?.id }
        )
    }

    private var relinkMasterBinding: Binding<IdentifiedMergeItem?> {
        Binding(
            get: { relinkMasterTarget.flatMap { id in mergeItems.first { $0.id == id } }.map(IdentifiedMergeItem.init) },
            set: { relinkMasterTarget = $0?.id }
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
                let needsMatchCount = unmatchedRemoteItems.count + unmatchedMasterItems.count
                Label("\(needsMatchCount) Needs Match", systemImage: "questionmark.circle.fill")
                    .foregroundColor(needsMatchCount == 0 ? .secondary : .orange)
                Label("\(unresolvedConflictItems.count) Conflicts", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(unresolvedConflictItems.isEmpty ? .secondary : .red)
                Label("\(resolvedCompareItems.count) Matched", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            .font(.subheadline)

            Divider().frame(height: 20)

            Button(hideResolved ? "Show Resolved" : "Hide Resolved") { hideResolved.toggle() }
                .controlSize(.small)
                .help("Hide every shot with no remaining discrepancy, matches included, so only what still needs attention stays visible.")
        }
        .padding()
        .liquidGlassBar()
    }

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel) { onCancel() }
                .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if !allResolved {
                    Text("Resolve every unlinked shot and conflict to continue")
                }
                Text(supportsPush
                    ? "\(localChangeCount) change\(localChangeCount == 1 ? "" : "s") to VFX Master List · \(remoteChangeCount) to \(sourceLabel)"
                    : "\(localChangeCount) change\(localChangeCount == 1 ? "" : "s") to VFX Master List")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Button("Resync") { onApply() }
                .liquidGlassButton(prominent: true)
                .disabled(!allResolved)
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Needs a Match

    // Both unmatched sides shown together but clearly split into their own sub-lists — an
    // unmatched remote shot and an unmatched master shot are the same underlying problem (nothing
    // to compare against yet) from opposite directions.
    @ViewBuilder
    private var needsMatchSection: some View {
        if !visibleUnmatchedRemote.isEmpty || !visibleUnmatchedMaster.isEmpty {
            section(title: "Needs a Match", systemImage: "questionmark.circle.fill", color: .orange) {
                VStack(alignment: .leading, spacing: 14) {
                    if !visibleUnmatchedRemote.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remote List (\(sourceLabel)) — not in VFX Master List")
                                .font(.caption).bold().foregroundColor(remoteColor)
                            VStack(spacing: 0) {
                                ForEach(visibleUnmatchedRemote) { item in
                                    unlinkedRow(item: item)
                                    Divider()
                                }
                            }
                        }
                    }
                    if !visibleUnmatchedMaster.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("VFX Master List — not in \(sourceLabel)")
                                .font(.caption).bold().foregroundColor(masterColor)
                            VStack(spacing: 0) {
                                ForEach(visibleUnmatchedMaster) { item in
                                    missingRow(item: item)
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func unlinkedRow(item: MergeItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: item.importedClip)).bold()
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

    // MARK: - Compared Shots (matched + conflicts, together)

    @ViewBuilder
    private var comparedSection: some View {
        if !visibleComparedItems.isEmpty {
            section(title: "Compared Shots", systemImage: "arrow.left.arrow.right.circle.fill", color: .secondary) {
                let selectedVisibleCount = selectedConflictIds.intersection(Set(visibleComparedItems.map(\.id))).count
                if selectedVisibleCount > 0 {
                    HStack {
                        Text("\(selectedVisibleCount) selected — resolving a field applies it to all of them")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        Button("Clear") { selectedConflictIds.removeAll() }
                            .buttonStyle(.plain)
                            .font(.caption)
                    }
                }
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 18) {
                        columnHeaderRow
                        ForEach(visibleComparedItems) { item in
                            conflictPair(itemId: item.id)
                        }
                    }
                }
            }
        }
    }

    private func toggleConflictSelection(_ id: UUID) {
        if NSEvent.modifierFlags.contains(.shift), let anchor = lastSelectedConflictId {
            let ids = visibleComparedItems.map(\.id)
            if let anchorIdx = ids.firstIndex(of: anchor), let clickedIdx = ids.firstIndex(of: id) {
                let range = anchorIdx <= clickedIdx ? anchorIdx...clickedIdx : clickedIdx...anchorIdx
                for i in range { selectedConflictIds.insert(ids[i]) }
                return
            }
        }
        if selectedConflictIds.contains(id) {
            selectedConflictIds.remove(id)
        } else {
            selectedConflictIds.insert(id)
        }
        lastSelectedConflictId = id
    }

    private var columnHeaderRow: some View {
        HStack(spacing: 0) {
            Text("").frame(width: gutterWidth, alignment: .leading) // gutter for row labels
            ForEach(displayColumns, id: \.self) { col in
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
        let cols = displayColumns
        let isSelected = selectedConflictIds.contains(itemId)
        let isClean = item.wrappedValue.isResolved // .identical, or every field on a .modified pair decided
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleConflictSelection(itemId) }
                    .help("Select — shift-click to select a range. Resolving one field then applies it to every selected shot with a conflict there.")
                Text(displayName(for: item.wrappedValue.importedClip)).bold()
                if isClean {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                }
                if let confidence = item.wrappedValue.matchConfidence {
                    Text("via \(confidence.label)").font(.caption2).foregroundColor(.secondary)
                } else if let score = item.wrappedValue.matchColumnScore {
                    Text("via \(score) shared column\(score == 1 ? "" : "s")").font(.caption2).foregroundColor(.secondary)
                }
                if !item.wrappedValue.diffKeys.isEmpty {
                    Button("Accept All Incoming") { resolveAll(itemId: itemId, winner: .incoming) }
                        .font(.caption).buttonStyle(.plain).foregroundColor(.accentColor)
                    Button("Keep All Local") { resolveAll(itemId: itemId, winner: .master) }
                        .font(.caption).buttonStyle(.plain).foregroundColor(.accentColor)
                }
                Button { breakLink(itemId: itemId) } label: {
                    Label("Break Link", systemImage: "link.badge.plus")
                }
                .buttonStyle(.plain).font(.caption).foregroundColor(.red)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 0) {
                rowLine(label: "Remote List", color: remoteColor) {
                    ForEach(cols, id: \.self) { col in valueCell(item: item, key: col, side: .incoming) }
                }
                arrowsLine(item: item, cols: cols)
                rowLine(label: "VFX Master List", color: masterColor) {
                    ForEach(cols, id: \.self) { col in valueCell(item: item, key: col, side: .master) }
                }
            }
        }
        .padding(8)
        .liquidGlassPanel(cornerRadius: 8)
        .background(isClean ? Color.green.opacity(0.06) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : (isClean ? Color.green.opacity(0.4) : Color.clear), lineWidth: 2)
        )
    }

    private enum RowSide { case incoming, master }

    @ViewBuilder
    private func rowLine<Content: View>(label: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.caption2).bold()
                .foregroundColor(color)
                .frame(width: gutterWidth, alignment: .leading)
            content()
        }
        .padding(.vertical, 3)
        .background(color.opacity(0.07))
    }

    @ViewBuilder
    private func valueCell(item: Binding<MergeItem>, key: String, side: RowSide) -> some View {
        let differs = item.wrappedValue.diffKeys.contains(key)
        let winner = item.wrappedValue.fieldWinners[key]
        let value = side == .incoming
            ? (item.wrappedValue.importedClip?.dict[key] ?? "")
            : (item.wrappedValue.masterClip?.dict[key] ?? "")
        let isLosing = differs && (
            (side == .incoming && winner == .master) || (side == .master && winner == .incoming)
        )

        Text(value.isEmpty ? "–" : value)
            .font(.caption)
            .strikethrough(isLosing)
            .foregroundColor(isLosing ? .secondary : .primary)
            .padding(4)
            .frame(width: columnWidth, alignment: .leading)
            .background(differs && winner == nil ? Color.red.opacity(0.12) : Color.clear)
    }

    private func arrowsLine(item: Binding<MergeItem>, cols: [String]) -> some View {
        HStack(spacing: 0) {
            Text("").frame(width: gutterWidth, alignment: .leading)
            ForEach(cols, id: \.self) { col in
                let differs = item.wrappedValue.diffKeys.contains(col)
                let winner = item.wrappedValue.fieldWinners[col]
                Group {
                    if differs {
                        HStack(spacing: 6) {
                            Button { setWinner(itemId: item.wrappedValue.id, key: col, winner: .incoming) } label: {
                                Image(systemName: winner == .incoming ? "arrow.down.circle.fill" : "arrow.down.circle")
                            }
                            .help("Take Remote List value, overwrite VFX Master List")
                            Button { setWinner(itemId: item.wrappedValue.id, key: col, winner: .master) } label: {
                                Image(systemName: winner == .master ? "arrow.up.circle.fill" : "arrow.up.circle")
                            }
                            .help("Keep VFX Master List value, reject Remote List")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(winner == nil ? .red : .accentColor)
                    } else {
                        Color.clear.frame(height: 14)
                    }
                }
                .padding(4)
                .frame(width: columnWidth, alignment: .leading)
            }
        }
    }

    private func missingRow(item: MergeItem) -> some View {
        let resolution = item.missingResolution
        return HStack {
            Text(displayName(for: item.masterClip))
                .bold()
                .strikethrough(resolution == .markRemoved)
                .foregroundColor(resolution == .markRemoved ? .secondary : .primary)
            Spacer()
            // Link across to an unmatched remote item, for when the matcher just couldn't tell
            // this is the same shot as one of the "Remote List" rows above (e.g. a heavy rename)
            // — the mirror of that row's own Link… button.
            Button { relinkMasterTarget = item.id } label: {
                Label("Link…", systemImage: "link")
            }
            .liquidGlassButton(prominent: false)
            .controlSize(.small)
            .disabled(unmatchedRemoteItems.isEmpty)

            // "Keep" for a one-way DaVinci/CSV import just dismisses the discrepancy; for Sheet
            // Sync the equivalent resolution is "Push" — this local-only shot gets sent to the
            // remote sheet on Resync (see remoteChangeCount / SheetSyncView.applySync).
            Button(supportsPush ? "Push" : "Keep") { setMissingResolution(itemId: item.id, .keep) }
                .controlSize(.small)
                .liquidGlassButton(prominent: resolution == .keep)
            Button("Mark Removed") { setMissingResolution(itemId: item.id, .markRemoved) }
                .controlSize(.small)
                .liquidGlassButton(prominent: resolution == .markRemoved)
                .tint(.red)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func mutate(itemId: UUID, _ body: (inout MergeItem) -> Void) {
        guard let idx = mergeItems.firstIndex(where: { $0.id == itemId }) else { return }
        body(&mergeItems[idx])
    }

    private func setWinner(itemId: UUID, key: String, winner: FieldSide) {
        // Acting on a shot that's part of a multi-selection applies this column's resolution to
        // every selected shot at once (skipping any that don't actually conflict on this
        // column) — an unambiguous "set to this direction" rather than single-item's toggle,
        // since toggling would be confusing across a batch that may already be in mixed states.
        if selectedConflictIds.contains(itemId), selectedConflictIds.count > 1 {
            for id in selectedConflictIds {
                mutate(itemId: id) { item in
                    guard item.diffKeys.contains(key) else { return }
                    item.fieldWinners[key] = winner
                }
            }
            return
        }
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
        // Capture the master clip being freed *before* mutating, then append its `.missing`
        // entry as a separate step — appending to `mergeItems` from inside `mutate`'s inout
        // closure (which already holds an exclusive access into the same array) would violate
        // Swift's exclusivity rules.
        let freedMaster = mergeItems.first(where: { $0.id == itemId })?.masterClip
        mutate(itemId: itemId) { item in
            item.masterClip = nil
            item.state = .new
            item.fieldWinners = [:]
            item.matchConfidence = nil
            item.matchColumnScore = nil
            item.confirmedNew = false
        }
        if let freedMaster {
            // Without this, the freed master clip would silently vanish from the review instead
            // of reappearing under "Needs a Match" — `.missing` items are a frozen snapshot taken
            // at comparison time, not live-recomputed, so nothing else would surface it again.
            mergeItems.append(MergeItem(masterClip: freedMaster, importedClip: nil, state: .missing))
        }
    }

    private func link(itemId: UUID, to masterClip: ClipData) {
        mutate(itemId: itemId) { item in
            item.masterClip = masterClip
            item.fieldWinners = [:]
            item.confirmedNew = false
            item.ignoredKeys = ignoredDiffKeys
            if item.importedClip != nil {
                item.state = item.diffKeys.isEmpty ? .identical : .modified
            }
        }
        // This master clip may have had its own `.missing` ("needs a match") entry — now that
        // it's properly claimed by `itemId`, that entry is stale and would otherwise duplicate
        // the shot (once as a real pair, once as still-unmatched).
        mergeItems.removeAll { $0.state == .missing && $0.masterClip?.id == masterClip.id }
        relinkTarget = nil
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
    // Only meaningful when this wraps a `.missing` item (a "Needs a Match — VFX Master List" row)
    // — its own master clip, to hand to `link(itemId:to:)` once the user picks which unmatched
    // remote item it actually corresponds to.
    var masterClipForLink: ClipData { item.masterClip ?? ClipData() }
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

// The mirror of RelinkPickerSheet — opened from a "Needs a Match — VFX Master List" row's Link…
// button, listing unmatched *remote* items instead of master clips, so a shot the matcher
// couldn't pair from either direction can be linked from whichever side the user happens to be
// looking at.
private struct RelinkToRemoteSheet: View {
    let candidates: [MergeItem]
    let displayName: (MergeItem) -> String
    let onPick: (MergeItem) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [MergeItem] {
        guard !searchText.isEmpty else { return candidates }
        return candidates.filter { displayName($0).localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Link to Remote Shot").font(.title2).bold()
                Spacer()
            }

            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search...", text: $searchText).textFieldStyle(.plain)
            }
            .padding(8)
            .liquidGlassPanel(cornerRadius: 8)

            List {
                Section("Unmatched Remote Shots") {
                    if filtered.isEmpty {
                        Text("Nothing unmatched on the remote side.").foregroundColor(.secondary)
                    }
                    ForEach(filtered) { item in
                        Button { onPick(item); dismiss() } label: {
                            Text(displayName(item))
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
