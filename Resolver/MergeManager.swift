import Foundation

enum MergeState: String, Codable {
    case identical
    case modified
    case new       // only on the imported/remote side — floats in the review UI's unlinked pool
    case missing   // only on the master side — nothing on the other side matched it this round
}

enum FieldSide: String, Codable {
    case incoming
    case master
}

enum MissingResolution: String, Codable {
    case keep         // dismiss the discrepancy, leave the master row untouched
    case markRemoved  // flag the master row as removed (ClipData.isRemoved) — never deleted
}

/// How confident the tiered matcher is that a given imported clip is the same shot as the
/// master clip it got paired with. Set only for matches found by `MergeManager`'s exact-signal
/// tiers (see `compareColumnAware`) — a match found by the generic column-overlap scorer instead
/// carries `matchColumnScore`.
enum MatchConfidence: String, Codable {
    case sourceRange // Same reel/media + identical Source In & Out — same source content,
                      // record TC (timeline position) is free to have moved (a reconform).
    case sourceTrim  // Same reel/media + same Source In + same duration, Source Out not
                      // compared directly — catches a shot whose tail got trimmed.
    case clipName    // Fallback: exact VFX/clip name match, no timecode signal available.

    var label: String {
        switch self {
        case .sourceRange: return "Source TC"
        case .sourceTrim: return "Source TC (trimmed)"
        case .clipName: return "Clip Name"
        }
    }
}

struct MergeItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var masterClip: ClipData?
    var importedClip: ClipData?  // nil only for .missing items (nothing on the import/remote side)
    var state: MergeState

    /// Set only by an exact-signal tier match — which signal linked this pair.
    var matchConfidence: MatchConfidence? = nil
    /// Set only by the generic column-overlap matcher — how many columns agreed.
    var matchColumnScore: Int? = nil
    /// Other master clips that scored close to (but lower than) the one this import matched, or
    /// — for an unmatched `.new` item — the master clips that came closest without clearing the
    /// match floor. Pre-seeds the manual relink picker.
    var candidateMasterClips: [ClipData] = []

    /// Per differing column, which side's value wins once the user decides. A key present in
    /// `diffKeys` without an entry here is still an unresolved discrepancy.
    var fieldWinners: [String: FieldSide] = [:]
    /// Explicit "yes, add this as a new shot" confirmation for a `.new` item — required before
    /// it can be applied, so an unmatched import can never be silently inserted.
    var confirmedNew: Bool = false
    /// User's decision for a `.missing` item (master row absent from this round's import/fetch).
    var missingResolution: MissingResolution? = nil
    /// Columns this comparison deliberately doesn't treat as a discrepancy — e.g. "VFX Name" for
    /// a DaVinci Resolve import, which never carries one at all (see
    /// `MergeManager.compareColumnAware`'s `ignoredDiffKeys` parameter). Never counted in
    /// `diffKeys`/`isResolved`, so the user is never asked to resolve something that isn't a real
    /// discrepancy in the first place.
    var ignoredKeys: Set<String> = []

    var diffKeys: [String] {
        guard let m = masterClip, let imp = importedClip else { return [] }
        return MergeManager.diffKeys(master: m, imported: imp).filter { !ignoredKeys.contains($0) }
    }

    /// Whether this item is fully decided — i.e. no longer blocks the Resync button.
    var isResolved: Bool {
        switch state {
        case .identical: return true
        case .modified: return diffKeys.allSatisfy { fieldWinners[$0] != nil }
        case .new: return confirmedNew
        case .missing: return missingResolution != nil
        }
    }
}

class MergeManager {

    /// Dict keys that are app-internal bookkeeping, not real shot data — never diffed, scored,
    /// or shown as a column.
    private static let internalOnlyKeys: Set<String> = ["Removed"]

    /// Column display order shared by both review windows: well-known fields first (in this
    /// order, only the ones actually present), then any custom columns alphabetically.
    private static let wellKnownColumnOrder: [String] = [
        "VFX Name", "TC In", "TC Out", "Source TC In", "Source TC Out", "Duration",
        "Reel Name", "File Names", "Episode", "Scene", "Frame Start", "Frame End",
        "Thumbnail Updated",
    ]

    static func orderedColumns(for clips: [ClipData]) -> [String] {
        let present = clips.reduce(into: Set<String>()) { $0.formUnion($1.dict.keys) }
            .subtracting(internalOnlyKeys)
        let known = wellKnownColumnOrder.filter { present.contains($0) }
        let custom = present.subtracting(wellKnownColumnOrder).sorted()
        return known + custom
    }

    /// Every dict key (across both sides) whose value differs, ignoring internal-only keys.
    static func diffKeys(master: ClipData, imported: ClipData) -> [String] {
        let keys = Set(master.dict.keys).union(imported.dict.keys).subtracting(internalOnlyKeys)
        return keys.filter { (master.dict[$0] ?? "") != (imported.dict[$0] ?? "") }.sorted()
    }

    /// Master clips no `MergeItem` in `mergeItems` has claimed — i.e. present locally but not
    /// matched to anything found this round. Deliberately computed live from current state
    /// rather than cached, so breaking a link (or a fresh compare) is always reflected correctly.
    /// Excludes already-removed clips — those are archived and no longer part of any comparison.
    static func unclaimedMasterClips(master: [ClipData], mergeItems: [MergeItem]) -> [ClipData] {
        let claimed = Set(mergeItems.compactMap { $0.masterClip?.id })
        return master.filter { !claimed.contains($0.id) && !$0.isRemoved }
    }

    /// Minimum number of shared, non-empty columns for the generic scorer to consider two clips
    /// a plausible pair at all — guards against one incidental shared value (e.g. both blank
    /// "Notes") forcing an unrelated match.
    private static let minColumnMatchScore = 2

    /// Reconform-aware, multi-signal matcher. Each imported clip is tested against the master
    /// pool in two passes:
    ///
    /// 1. Tiered exact-signal matching (source range → source trim → clip name, strongest
    ///    first) — cheap and precise; a tier only claims a match when exactly one
    ///    unclaimed master clip qualifies (an ambiguous tie is left for pass 2 / manual review).
    /// 2. For everything still unmatched on both sides, a generic column-overlap scorer: every
    ///    remaining (imported, master) pair scores by how many dict columns agree (not just the
    ///    fixed signal fields), and pairs are assigned highest-score-first (a shot sharing 3
    ///    columns wins its master clip over one sharing only 2, even if that clip was also a
    ///    candidate) — a greedy max-weight matching, not first-match.
    ///
    /// Anything still unmatched after both passes becomes `.new` (the review UI's "unlinked
    /// pool"), carrying its closest near-misses in `candidateMasterClips` to speed up manual
    /// relinking. Already-removed master clips are excluded from matching entirely.
    ///
    /// `ignoredDiffKeys` are columns a matched pair is never treated as disagreeing on (see
    /// `MergeItem.ignoredKeys`) — e.g. "VFX Name" for a DaVinci Resolve import, which never
    /// carries one, so every pair would otherwise show a bogus conflict on that field alone.
    static func compareColumnAware(master: [ClipData], imported: [ClipData], ignoredDiffKeys: Set<String> = []) -> [MergeItem] {
        let activeMaster = master.filter { !$0.isRemoved }
        var results = [MergeItem?](repeating: nil, count: imported.count)
        var claimedMasterIds = Set<UUID>()
        var candidatesByImport: [Int: [ClipData]] = [:]

        // Pass 1: exact reconform-aware signal tiers.
        for tier in MatchTier.allCases {
            for (idx, imp) in imported.enumerated() {
                guard results[idx] == nil else { continue }

                let matches = candidateMasters(for: tier, imp: imp, master: activeMaster)
                    .filter { !claimedMasterIds.contains($0.id) }
                guard !matches.isEmpty else { continue }

                if matches.count == 1 {
                    let masterClip = matches[0]
                    claimedMasterIds.insert(masterClip.id)
                    results[idx] = makeItem(masterClip: masterClip, imported: imp, confidence: tier.confidence, score: nil, ignoredKeys: ignoredDiffKeys)
                } else if candidatesByImport[idx] == nil {
                    candidatesByImport[idx] = matches
                }
            }
        }

        // Pass 2: generic column-overlap scoring for whatever's left.
        let unmatchedImportIdx = imported.indices.filter { results[$0] == nil }
        let unclaimedMaster = activeMaster.filter { !claimedMasterIds.contains($0.id) }

        if !unmatchedImportIdx.isEmpty && !unclaimedMaster.isEmpty {
            struct Candidate { let importIdx: Int; let master: ClipData; let score: Int }

            var candidates: [Candidate] = []
            for idx in unmatchedImportIdx {
                let imp = imported[idx]
                for m in unclaimedMaster {
                    let score = columnMatchScore(imp, m)
                    if score >= minColumnMatchScore {
                        candidates.append(Candidate(importIdx: idx, master: m, score: score))
                    }
                }
            }
            // Stable sort (Swift's sort is guaranteed stable) — ties keep insertion order, i.e.
            // earlier imports and earlier master clips win ties rather than an arbitrary reorder.
            candidates.sort { $0.score > $1.score }

            for c in candidates {
                guard results[c.importIdx] == nil, !claimedMasterIds.contains(c.master.id) else { continue }
                claimedMasterIds.insert(c.master.id)
                results[c.importIdx] = makeItem(masterClip: c.master, imported: imported[c.importIdx], confidence: nil, score: c.score, ignoredKeys: ignoredDiffKeys)
            }
        }

        // Anything left is genuinely unmatched — surface near-misses to help manual relinking.
        for idx in imported.indices where results[idx] == nil {
            let stillUnclaimed = activeMaster.filter { !claimedMasterIds.contains($0.id) }
            let nearMisses = (candidatesByImport[idx] ?? stillUnclaimed
                .map { ($0, columnMatchScore(imported[idx], $0)) }
                .filter { $0.1 >= minColumnMatchScore }
                .sorted { $0.1 > $1.1 }
                .prefix(5)
                .map { $0.0 })
            results[idx] = MergeItem(masterClip: nil, importedClip: imported[idx], state: .new, candidateMasterClips: nearMisses)
        }

        return results.map { $0! }
    }

    // MARK: - Smart matching internals

    private enum MatchTier: CaseIterable {
        case sourceRange
        case sourceTrim
        case clipName

        var confidence: MatchConfidence {
            switch self {
            case .sourceRange: return .sourceRange
            case .sourceTrim: return .sourceTrim
            case .clipName: return .clipName
            }
        }
    }

    /// Normalizes a string for comparison purposes only (never written back): trims whitespace
    /// and lowercases, so incidental casing/whitespace differences don't defeat a match.
    private static func norm(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Identifies *which* source media a clip came from, for disambiguating source timecodes
    /// that repeat across different reels/files.
    private static func mediaKey(_ clip: ClipData) -> String {
        let reel = norm(clip.reelName)
        if !reel.isEmpty { return reel }
        return norm(clip.fileNames)
    }

    private static func candidateMasters(for tier: MatchTier, imp: ClipData, master: [ClipData]) -> [ClipData] {
        switch tier {
        case .sourceRange:
            let impMedia = mediaKey(imp)
            let impIn = norm(imp.sourceTcIn), impOut = norm(imp.sourceTcOut)
            guard !impMedia.isEmpty, !impIn.isEmpty, !impOut.isEmpty else { return [] }
            return master.filter {
                mediaKey($0) == impMedia && norm($0.sourceTcIn) == impIn && norm($0.sourceTcOut) == impOut
            }

        case .sourceTrim:
            let impMedia = mediaKey(imp)
            let impIn = norm(imp.sourceTcIn)
            guard !impMedia.isEmpty, !impIn.isEmpty, imp.duration != nil else { return [] }
            return master.filter {
                mediaKey($0) == impMedia && norm($0.sourceTcIn) == impIn && $0.duration == imp.duration
            }

        case .clipName:
            let key = norm(imp.originalVfxName ?? imp.vfxName)
            guard !key.isEmpty else { return [] }
            return master.filter { norm($0.originalVfxName ?? $0.vfxName) == key }
        }
    }

    /// Number of dict columns (excluding internal-only keys) that are non-empty and equal
    /// (normalized) on both clips — the generic matching signal for pass 2.
    private static func columnMatchScore(_ a: ClipData, _ b: ClipData) -> Int {
        var score = 0
        for (key, aVal) in a.dict {
            guard !internalOnlyKeys.contains(key) else { continue }
            let av = norm(aVal)
            guard !av.isEmpty, let bVal = b.dict[key], norm(bVal) == av else { continue }
            score += 1
        }
        return score
    }

    private static func makeItem(masterClip: ClipData, imported: ClipData, confidence: MatchConfidence?, score: Int?, ignoredKeys: Set<String>) -> MergeItem {
        let keys = diffKeys(master: masterClip, imported: imported).filter { !ignoredKeys.contains($0) }
        return MergeItem(
            masterClip: masterClip,
            importedClip: imported,
            state: keys.isEmpty ? .identical : .modified,
            matchConfidence: confidence,
            matchColumnScore: score,
            ignoredKeys: ignoredKeys
        )
    }

    // MARK: - Apply

    /// Applies a fully-reviewed set of `MergeItem`s into the master list. Every item is expected
    /// to be `isResolved` (the review UI's Resync button is gated on that) — an item that isn't
    /// is simply skipped rather than guessed, so calling this on a partially-reviewed set can
    /// never silently overwrite or insert something the user hasn't decided on.
    static func applyMerge(master: inout [ClipData], mergeItems: [MergeItem]) {
        for item in mergeItems {
            guard item.isResolved else { continue }

            switch item.state {
            case .new:
                guard let imp = item.importedClip else { continue }
                master.append(imp)

            case .modified, .identical:
                guard let masterClip = item.masterClip, let imp = item.importedClip,
                      let idx = master.firstIndex(where: { $0.id == masterClip.id }) else { continue }
                var merged = masterClip
                for key in item.diffKeys {
                    if item.fieldWinners[key] == .incoming {
                        merged.dict[key] = imp.dict[key]
                    }
                    // .master (or, defensively, unresolved) keeps the existing master value.
                }
                master[idx] = merged

            case .missing:
                guard let masterClip = item.masterClip,
                      let idx = master.firstIndex(where: { $0.id == masterClip.id }) else { continue }
                if item.missingResolution == .markRemoved {
                    master[idx].isRemoved = true
                }
            }
        }
    }

    /// Wraps every currently-unclaimed master clip as a `.missing` item — used only by the
    /// DaVinci/CSV import review (a one-way read of "what currently exists"), so a shot Resolve
    /// no longer has surfaces as a discrepancy instead of silently staying untouched forever.
    /// Sheet Sync deliberately does not call this — its local-only rows are "not yet pushed",
    /// not "deleted remotely", and stay in the push section instead.
    static func missingItems(master: [ClipData], mergeItems: [MergeItem]) -> [MergeItem] {
        unclaimedMasterClips(master: master, mergeItems: mergeItems).map {
            MergeItem(masterClip: $0, importedClip: nil, state: .missing)
        }
    }

    /// Silent, no-review merge used by the menu-bar quick-reindex path (`DropDownMenu.swift`) —
    /// there's no review UI in that flow, so it always takes the incoming value wholesale for a
    /// changed shot and appends anything unmatched, mirroring how that shortcut has always
    /// behaved. Never touches `.missing`/removal — that's a review-window-only concept.
    static func quickMerge(master: inout [ClipData], imported: [ClipData]) {
        let items = compareColumnAware(master: master, imported: imported)
        for item in items {
            switch item.state {
            case .new:
                if let imp = item.importedClip { master.append(imp) }
            case .modified:
                // Merge rather than wholesale-replace: an import that simply doesn't carry a
                // field (e.g. DaVinci Resolve never supplies VFX Name) must not blank out
                // whatever master already has there — only a genuinely non-empty incoming value
                // overwrites.
                if let masterClip = item.masterClip, let imp = item.importedClip,
                   let idx = master.firstIndex(where: { $0.id == masterClip.id }) {
                    var merged = masterClip
                    for (key, value) in imp.dict where !value.isEmpty {
                        merged.dict[key] = value
                    }
                    master[idx] = merged
                }
            case .identical, .missing:
                break
            }
        }
    }
}
