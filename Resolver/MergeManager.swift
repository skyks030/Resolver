import Foundation

enum MergeState: String, Codable {
    case identical
    case modified
    case new
}

enum MergeKeyOption: String, CaseIterable {
    case smart = "Smart (Recommended)"
    case clipName = "Clip Name"
    case startTC = "Start TC / Timeline In"
    case sourceIn = "Source In"
    case uniqueId = "DaVinci Unique ID"
}

/// How confident `.smart` matching is that a given imported clip is the same shot as
/// the master clip it got paired with. Higher-confidence tiers are tried first and
/// claim their master clip before weaker tiers get a chance — see `MergeManager.smartCompare`.
enum MatchConfidence: String, Codable {
    case uniqueId    // Resolve's own per-clip-instance ID matched exactly.
    case sourceRange // Same reel/media + identical Source In & Out — same source content,
                      // record TC (timeline position) is free to have moved (a reconform).
    case sourceTrim  // Same reel/media + same Source In + same duration, Source Out not
                      // compared directly — catches a shot whose tail got trimmed.
    case clipName    // Fallback: exact VFX/clip name match, no timecode signal available.

    var label: String {
        switch self {
        case .uniqueId: return "Resolve ID"
        case .sourceRange: return "Source TC"
        case .sourceTrim: return "Source TC (trimmed)"
        case .clipName: return "Clip Name"
        }
    }
}

struct MergeItem: Codable, Identifiable {
    var id: UUID = UUID()
    var masterClip: ClipData?
    var importedClip: ClipData
    var state: MergeState
    var selected: Bool = true // true means user wants to apply this change

    /// Set only by `.smart` matching: which signal linked this import to `masterClip`.
    /// nil for the legacy single-key modes and for unmatched (`.new`) items.
    var matchConfidence: MatchConfidence? = nil

    /// Set only by `.smart` matching, only on unmatched (`.new`) items: other master
    /// clips that matched the same signal, so the match was ambiguous and was
    /// deliberately left for the user to resolve rather than guessed. Not yet surfaced
    /// in the review UI — reserved for a future "link to existing shot" picker.
    var candidateMasterClips: [ClipData] = []
}

class MergeManager {

    /// Compares an imported clip list against the master list and classifies each
    /// import as `.new`, `.modified`, or `.identical`.
    ///
    /// `.smart` (the default) runs a tiered match — see `smartCompare` — so a shot is
    /// still recognized after a reconform shifts its record TC, as long as its source
    /// content (reel + source in/out, or reel + source-in + duration) didn't change.
    /// The other cases are the original single-field exact-match modes, kept as a
    /// manual override for when the user wants to force matching on one specific column.
    static func compare(master: [ClipData], imported: [ClipData], mergeKey: MergeKeyOption = .smart) -> [MergeItem] {
        if mergeKey == .smart {
            return smartCompare(master: master, imported: imported)
        }

        var results: [MergeItem] = []

        // Build lookup maps for Master list based on selected mergeKey
        var masterMap: [String: ClipData] = [:]

        for clip in master {
            let key: String
            switch mergeKey {
            case .smart: fatalError("handled above")
            case .clipName:
                key = clip.originalVfxName ?? clip.vfxName
            case .startTC:
                key = clip.tcIn
            case .sourceIn:
                key = clip.sourceTcIn
            case .uniqueId:
                key = clip.uniqueId ?? ""
            }

            if !key.isEmpty {
                masterMap[key] = clip
            }
        }

        for imp in imported {
            var matchedMaster: ClipData?

            let searchKey: String
            switch mergeKey {
            case .smart: fatalError("handled above")
            case .clipName:
                // When we import CSV, the raw Clip Name typically maps to vfxName temporarily
                searchKey = imp.originalVfxName ?? imp.vfxName
            case .startTC:
                searchKey = imp.tcIn
            case .sourceIn:
                searchKey = imp.sourceTcIn
            case .uniqueId:
                searchKey = imp.uniqueId ?? ""
            }

            if !searchKey.isEmpty, let match = masterMap[searchKey] {
                matchedMaster = match
            }

            if let masterClip = matchedMaster {
                let state = classify(masterClip: masterClip, imp: imp)
                // By default, do not select "identical" to save processing/visual clutter, but select new & modified
                results.append(MergeItem(masterClip: masterClip, importedClip: imp, state: state, selected: state == .modified))
            } else {
                // Completely new
                results.append(MergeItem(masterClip: nil, importedClip: imp, state: .new, selected: true))
            }
        }

        return results
    }

    /// Tiered reconform-aware matching. Each imported clip is tested against the master
    /// list tier by tier, strongest signal first; a tier only wins if exactly one
    /// unclaimed master clip matches (an ambiguous tie is left unmatched — recorded as
    /// `candidateMasterClips` — rather than guessed). A master clip claimed by one import
    /// is removed from the pool for every later import, so two imports can never both
    /// silently latch onto the same existing shot.
    static func smartCompare(master: [ClipData], imported: [ClipData]) -> [MergeItem] {
        var results = [MergeItem?](repeating: nil, count: imported.count)
        var claimedMasterIds = Set<UUID>()
        var candidatesByImport: [Int: [ClipData]] = [:]

        for tier in MatchTier.allCases {
            for (idx, imp) in imported.enumerated() {
                guard results[idx] == nil else { continue } // already matched at a stronger tier

                let matches = candidateMasters(for: tier, imp: imp, master: master)
                    .filter { !claimedMasterIds.contains($0.id) }
                guard !matches.isEmpty else { continue }

                if matches.count == 1 {
                    let masterClip = matches[0]
                    claimedMasterIds.insert(masterClip.id)
                    let state = classify(masterClip: masterClip, imp: imp)
                    results[idx] = MergeItem(
                        masterClip: masterClip,
                        importedClip: imp,
                        state: state,
                        selected: state == .modified,
                        matchConfidence: tier.confidence
                    )
                } else {
                    // More than one plausible master clip at this tier — don't pick one
                    // for the user. Keep the strongest tier's candidates only (later,
                    // weaker tiers might otherwise pile on unrelated near-misses).
                    if candidatesByImport[idx] == nil {
                        candidatesByImport[idx] = matches
                    }
                }
            }
        }

        for (idx, imp) in imported.enumerated() where results[idx] == nil {
            results[idx] = MergeItem(
                masterClip: nil,
                importedClip: imp,
                state: .new,
                selected: true,
                candidateMasterClips: candidatesByImport[idx] ?? []
            )
        }

        return results.map { $0! }
    }

    // MARK: - Smart matching internals

    private enum MatchTier: CaseIterable {
        case uniqueId
        case sourceRange
        case sourceTrim
        case clipName

        var confidence: MatchConfidence {
            switch self {
            case .uniqueId: return .uniqueId
            case .sourceRange: return .sourceRange
            case .sourceTrim: return .sourceTrim
            case .clipName: return .clipName
            }
        }
    }

    /// Normalizes a string for comparison purposes only (never written back): trims
    /// whitespace and lowercases, so incidental casing/whitespace differences between
    /// two exports of the same source media don't defeat a match.
    private static func norm(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Identifies *which* source media a clip came from, for disambiguating source
    /// timecodes that repeat across different reels/files. Empty only when the clip
    /// carries neither reel name nor file name metadata.
    private static func mediaKey(_ clip: ClipData) -> String {
        let reel = norm(clip.reelName)
        if !reel.isEmpty { return reel }
        return norm(clip.fileNames)
    }

    private static func candidateMasters(for tier: MatchTier, imp: ClipData, master: [ClipData]) -> [ClipData] {
        switch tier {
        case .uniqueId:
            guard let impId = imp.uniqueId, !impId.isEmpty else { return [] }
            return master.filter { $0.uniqueId == impId }

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

    /// Shared "did anything actually change" check used by both the legacy single-key
    /// path and `.smart` once a master/import pair has been decided.
    private static func classify(masterClip: ClipData, imp: ClipData) -> MergeState {
        let isIdentical = (
            masterClip.tcIn == imp.tcIn &&
            masterClip.tcOut == imp.tcOut &&
            masterClip.duration == imp.duration &&
            masterClip.sourceTcIn == imp.sourceTcIn &&
            masterClip.sourceTcOut == imp.sourceTcOut &&
            masterClip.fileNames == imp.fileNames &&
            masterClip.reelName == imp.reelName &&
            masterClip.dict["Episode"] == imp.dict["Episode"] &&
            masterClip.dict["Scene"] == imp.dict["Scene"]
        )
        return isIdentical ? .identical : .modified
    }

    // Apply changes from MergeItems into the Master List
    static func applyMerge(master: inout [ClipData], mergeItems: [MergeItem]) {
        for item in mergeItems {
            guard item.selected else { continue }

            switch item.state {
            case .new:
                master.append(item.importedClip)
            case .modified:
                // Find and update the existing clip
                if let oldClip = item.masterClip, let index = master.firstIndex(where: { $0.id == oldClip.id }) {
                    // Update metadata but keep the main ID
                    var updated = item.importedClip
                    updated.id = master[index].id

                    // Maintain naming overrides if the user customized the VFX Name previously
                    if master[index].vfxName != master[index].originalVfxName {
                         updated.vfxName = master[index].vfxName
                    }

                    master[index] = updated
                } else {
                    // Fallback if not found for some reason
                    master.append(item.importedClip)
                }
            case .identical:
                // Do nothing
                break
            }
        }
    }
}
