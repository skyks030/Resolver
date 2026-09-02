import SwiftUI

/// Live status for the "Resync" apply step, shown as a status bar in place of the footer's
/// buttons while it's non-nil — see SyncReviewView.applyStatusBar. The presenting view (import
/// or Sheet Sync) owns and drives this via the `applyProgress` binding as it actually writes
/// changes into the master list and, for Sheet Sync, out to the remote sheet.
struct SyncApplyProgress: Equatable {
    var current: Int
    var total: Int
    var label: String
}

// Shared review window for both the DaVinci Resolve/CSV import merge and Sheet Sync's "Compare
// Now" — same layout, same matching model (MergeManager.compareColumnAware), so switching
// between the two feels like the same tool. The main list is always the full VFX Master List,
// sorted by VFX Name (see `masterOrderedItems`) — every master shot appears there whether the
// matcher paired it with something or not, headed by its VFX Master List name either way, so an
// unmatched master shot still sits at its normal alphabetical spot instead of floating off
// somewhere else. Only an unmatched *remote/imported* shot (nothing to head it by yet) floats in
// its own "Needs a Match" pool up top, for manual relinking or declaring it a brand-new shot.
// Every remaining per-column discrepancy is resolved one direction or the other before Resync
// unlocks.
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
    /// The presenting window's size, captured right before this sheet was opened — this window
    /// sizes itself relative to it (see `reviewWindowSize`) rather than to its own content, which
    /// on a long list/many columns could otherwise balloon far past the rest of the app, most
    /// visibly on a 4K display where the point-size gap is largest.
    var preferredSize: CGSize = SyncReviewView.currentReferenceWindowSize()
    /// Non-nil while Resync is actively writing changes out (to the master list, and for Sheet
    /// Sync, to the remote sheet too) — see `SyncApplyProgress`.
    @Binding var applyProgress: SyncApplyProgress?
    /// When set, every shot name shown in this review becomes clickable, jumping DaVinci Resolve's
    /// playhead to that shot's saved timecode/episode. Only wired up for a real DaVinci Resolve
    /// index review (ProjectExportView.jumpToClipInResolve) — a hand-picked CSV import may be old
    /// or from a different project, and Sheet Sync's review can reasonably be used with Resolve
    /// not even running, so both leave this nil (no click affordance shown at all).
    var onJumpToClip: ((ClipData) -> Void)? = nil
    let onApply: () -> Void
    let onCancel: () -> Void

    // Hides every item with no remaining discrepancy — not just `.identical` matches, but any
    // `.modified`/`.new`/`.missing` item the user has fully resolved too — so cleaning up the
    // last field on a conflict makes it disappear immediately, same as a plain match, letting
    // the list progressively narrow down to only what still needs attention.
    @State private var hideResolved = false
    @State private var relinkTarget: UUID? = nil
    // Which unmatched master shot's (missingRow) Link… button was pressed, to link it to an
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

    /// Sort key for `masterOrderedItems`: the master clip's VFX Name — this review's heading for
    /// a shot is always the VFX Master List's own name for it (see `clipNameText`), so the list
    /// sorts by that same name too. Falls back to `displayName` on the rare chance a master clip
    /// has no VFX Name at all.
    private func masterSortKey(_ item: MergeItem) -> String {
        let name = item.masterClip?.vfxName ?? ""
        return name.isEmpty ? displayName(for: item.masterClip ?? item.importedClip) : name
    }

    /// Every VFX Master List shot — matched (`comparedItems`) or not (`unmatchedMasterItems`) —
    /// together, sorted by VFX Name, so the full master list is always visible in its normal order
    /// and an unmatched master shot still sits exactly where it belongs instead of floating off in
    /// a separate pool. Only unmatched *remote* shots stay elsewhere (`needsMatchSection`) — they
    /// don't have a VFX Name yet to sort into this order by.
    private var masterOrderedItems: [MergeItem] {
        (comparedItems + unmatchedMasterItems).sorted {
            masterSortKey($0).localizedStandardCompare(masterSortKey($1)) == .orderedAscending
        }
    }

    /// `hideResolved`-filtered versions of the groups above — what actually gets rendered.
    /// A fully-resolved compared item (identical, or a conflict with every field decided) is what
    /// subsumed the old "Hide Matching" behavior: turning this on empties it out of the list
    /// along with everything else that's clean.
    private func visible(_ items: [MergeItem]) -> [MergeItem] { hideResolved ? items.filter { !$0.isResolved } : items }
    private var visibleUnmatchedRemote: [MergeItem] { visible(unmatchedRemoteItems) }
    private var visibleComparedItems: [MergeItem] { visible(masterOrderedItems) }
    // Select All/Deselect All and the selection-count caption only ever target real field-level
    // conflicts — a `.missing` row (interleaved into `visibleComparedItems` above) has no
    // checkbox and nothing for a bulk column resolution to apply to.
    private var visibleSelectableItems: [MergeItem] { visible(comparedItems) }

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

    /// A shot's name, bold like everywhere else — but clickable (jumping DaVinci Resolve to it,
    /// see `onJumpToClip`) whenever that's wired up and this particular clip actually has a saved
    /// TC In to jump to. Falls back to plain, non-interactive text otherwise.
    @ViewBuilder
    private func clipNameText(_ clip: ClipData?) -> some View {
        clipNameText(nameFrom: clip, jumpFrom: clip)
    }

    /// Same idea, but the displayed name and the jump target can be two different clips — used by
    /// `conflictPair`, where the heading is always the VFX Master List's own name for a shot (see
    /// `masterOrderedItems`), while the freshest, most-likely-to-still-be-accurate TC to actually
    /// jump to is whichever side's import just reported it (falling back to the master clip's own
    /// TC only when there's no imported clip to prefer, e.g. an unmatched master-only shot).
    @ViewBuilder
    private func clipNameText(nameFrom nameClip: ClipData?, jumpFrom jumpClip: ClipData?) -> some View {
        let name = displayName(for: nameClip)
        if let jumpClip, let onJumpToClip, !jumpClip.tcIn.isEmpty {
            Button { onJumpToClip(jumpClip) } label: {
                Text(name).bold()
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .help("Jump to this shot's timecode in DaVinci Resolve")
        } else {
            Text(name).bold()
        }
    }

    /// Same idea as `clipNameText`, for `missingRow`'s master-only shots — which additionally
    /// need the strikethrough/dimming treatment once marked removed, and a tooltip that's honest
    /// about the jump target possibly being stale (this is the *last known* position; nothing in
    /// the fresh import claimed this shot, so Resolve may no longer have anything there).
    @ViewBuilder
    private func missingRowNameText(_ clip: ClipData?, resolution: MissingResolution?) -> some View {
        let name = displayName(for: clip)
        let removed = resolution == .markRemoved
        if let clip, let onJumpToClip, !clip.tcIn.isEmpty {
            Button { onJumpToClip(clip) } label: {
                Text(name).bold().strikethrough(removed)
            }
            .buttonStyle(.plain)
            .foregroundColor(removed ? .secondary : .accentColor)
            .help("Jump to this shot's last known timecode in DaVinci Resolve")
        } else {
            Text(name)
                .bold()
                .strikethrough(removed)
                .foregroundColor(removed ? .secondary : .primary)
        }
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

    /// The size (in points — already display-scale-aware, so this isn't a Retina/4K pixel-vs-point
    /// mixup) of whichever window is in front right before this sheet opens. Callers capture this
    /// explicitly just before setting their `show...Review` flag, since by the time this view's
    /// body actually runs, the sheet's own window may already be key. The default here only
    /// matters if a call site is ever added that forgets to pass `preferredSize` explicitly.
    static func currentReferenceWindowSize() -> CGSize {
        if let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow, window.isVisible {
            return window.frame.size
        }
        if let screen = NSScreen.main {
            return CGSize(width: screen.visibleFrame.width * 0.75, height: screen.visibleFrame.height * 0.8)
        }
        return CGSize(width: 1200, height: 800)
    }

    /// `preferredSize`, scaled down a bit and clamped between the window's practical floor (the
    /// old fixed minimum) and the current screen's visible area — so the review window tracks
    /// wherever the presenting window currently is/how it's currently sized, instead of expanding
    /// to fit a long shot list or wide column set on its own.
    private var reviewWindowSize: CGSize {
        let screenLimit = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1600, height: 1000)
        let width = max(880, min(preferredSize.width * 0.92, screenLimit.width * 0.95))
        let height = max(620, min(preferredSize.height * 0.92, screenLimit.height * 0.92))
        return CGSize(width: width, height: height)
    }

    /// Plain-language reason Resync is still disabled — shown both as caption text and as the
    /// button's own tooltip, so it's never a mystery why it's grayed out.
    private var unresolvedSummary: String {
        let needsMatch = unmatchedRemoteItems.count + unmatchedMasterItems.count
        let conflicts = unresolvedConflictItems.count
        var parts: [String] = []
        if needsMatch > 0 { parts.append("\(needsMatch) shot\(needsMatch == 1 ? "" : "s") still \(needsMatch == 1 ? "needs" : "need") a match") }
        if conflicts > 0 { parts.append("\(conflicts) unresolved conflict\(conflicts == 1 ? "" : "s")") }
        guard !parts.isEmpty else { return "" }
        return "Resolve \(parts.joined(separator: " and ")) before you can Resync."
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    needsMatchSection
                    comparedSection

                    if visibleUnmatchedRemote.isEmpty && visibleComparedItems.isEmpty {
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
        .frame(
            minWidth: 880, idealWidth: reviewWindowSize.width, maxWidth: reviewWindowSize.width,
            minHeight: 620, idealHeight: reviewWindowSize.height, maxHeight: reviewWindowSize.height
        )
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
        }
        .padding()
        .liquidGlassBar()
    }

    @ViewBuilder
    private var footer: some View {
        if let progress = applyProgress {
            applyStatusBar(progress)
                .padding()
        } else {
            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])

                // Right next to Resync, not up in the header, so it reads as "only show me what
                // still needs a decision before I sync" rather than an unrelated view option.
                Button(hideResolved ? "Show Resolved" : "Hide Resolved") { hideResolved.toggle() }
                    .controlSize(.small)
                    .help("Hide every shot with no remaining discrepancy, matches included, so only what still needs attention stays visible.")

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if !allResolved {
                        Text(unresolvedSummary)
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
                    // Same reason shown as caption text, but right on the button itself — so
                    // hovering the grayed-out button directly answers "why can't I click this".
                    .help(allResolved ? "Apply every resolved change." : unresolvedSummary)
            }
            .padding()
        }
    }

    /// Shown in place of the footer's buttons while `onApply()` is actively writing changes out —
    /// to the VFX Master List and, for Sheet Sync, the remote sheet too — so a run over many shots
    /// reads as "in progress, this many left" instead of the window just looking stuck.
    private func applyStatusBar(_ progress: SyncApplyProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ProgressView(value: progress.total > 0 ? Double(progress.current) : 0, total: Double(max(progress.total, 1)))
                Text("\(progress.current)/\(progress.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(minWidth: 50, alignment: .trailing)
            }
            Text(progress.label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Needs a Match

    // Only the remote side now — an unmatched *master* shot isn't segregated up here anymore, it
    // stays inline in the VFX Master List below, sorted into its normal alphabetical position
    // (see `masterOrderedItems`), since it does have a real VFX Name to sit in that order by. An
    // unmatched *remote* shot doesn't (nothing's claimed it yet), so it has nowhere meaningful to
    // sort into and stays here instead.
    @ViewBuilder
    private var needsMatchSection: some View {
        if !visibleUnmatchedRemote.isEmpty {
            section(title: "Needs a Match", systemImage: "questionmark.circle.fill", color: .orange) {
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
        }
    }

    private func unlinkedRow(item: MergeItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                clipNameText(item.importedClip)
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
            section(title: "VFX Master List", systemImage: "list.bullet.rectangle", color: .secondary) {
                let selectedVisibleCount = selectedConflictIds.intersection(Set(visibleSelectableItems.map(\.id))).count
                HStack {
                    Button("Select All") {
                        selectedConflictIds = Set(visibleSelectableItems.map(\.id))
                        lastSelectedConflictId = visibleSelectableItems.last?.id
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    Button("Deselect All") {
                        selectedConflictIds.removeAll()
                        lastSelectedConflictId = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .disabled(selectedVisibleCount == 0)
                    if selectedVisibleCount > 0 {
                        Text("\(selectedVisibleCount) selected — resolving a field applies it to all of them")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 18) {
                        columnHeaderRow
                        // Every VFX Master List shot, in its normal alphabetical order — matched
                        // shots render as a full conflict/match pair, an unmatched one (no import
                        // claimed it) as a plain row with its own Link…/Push/Mark Removed actions,
                        // right where it belongs instead of floating off in a separate section.
                        ForEach(visibleComparedItems) { item in
                            if item.state == .missing {
                                missingRow(item: item)
                            } else {
                                conflictPair(itemId: item.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // Standard modern-UI selection semantics: a plain click selects only that row (replacing
    // whatever was selected before); shift-click extends a contiguous range from the last
    // anchor; command-click adds/removes just that row without touching the rest.
    private func toggleConflictSelection(_ id: UUID) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift), let anchor = lastSelectedConflictId {
            let ids = visibleSelectableItems.map(\.id)
            if let anchorIdx = ids.firstIndex(of: anchor), let clickedIdx = ids.firstIndex(of: id) {
                let range = anchorIdx <= clickedIdx ? anchorIdx...clickedIdx : clickedIdx...anchorIdx
                selectedConflictIds = Set(range.map { ids[$0] })
                return // keep the existing anchor so further shift-clicks extend from the same origin
            }
        }
        if modifiers.contains(.command) {
            if selectedConflictIds.contains(id) {
                selectedConflictIds.remove(id)
            } else {
                selectedConflictIds.insert(id)
            }
            lastSelectedConflictId = id
            return
        }
        selectedConflictIds = [id]
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
                    .help("Click to select just this shot, ⇧-click to select a range, ⌘-click to add/remove it from the selection. Resolving one field then applies it to every selected shot with a conflict there.")
                clipNameText(nameFrom: item.wrappedValue.masterClip, jumpFrom: item.wrappedValue.importedClip ?? item.wrappedValue.masterClip)
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
            missingRowNameText(item.masterClip, resolution: resolution)
            Text("not in \(sourceLabel)").font(.caption2).foregroundColor(.secondary)
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
        .padding(8)
        // Interleaved among conflictPair's cards in the same master-ordered list now (rather than
        // its own segregated section), so it gets the same card treatment to read as one of the
        // list's normal rows instead of looking like a stray leftover row.
        .liquidGlassPanel(cornerRadius: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(resolution != nil ? Color.green.opacity(0.4) : Color.clear, lineWidth: 2)
        )
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
