import Foundation

enum MergeState: String, Codable {
    case identical
    case modified
    case new
}

struct MergeItem: Codable, Identifiable {
    var id: UUID = UUID()
    var masterClip: ClipData?
    var importedClip: ClipData
    var state: MergeState
    var selected: Bool = true // true means user wants to apply this change
}

class MergeManager {
    static func compare(master: [ClipData], imported: [ClipData]) -> [MergeItem] {
        var results: [MergeItem] = []
        
        // Build lookup maps for Master list
        var masterById: [String: ClipData] = [:]
        var masterByName: [String: ClipData] = [:]
        var masterByFileAndReel: [String: ClipData] = [:]
        
        for clip in master {
            if let uid = clip.uniqueId, !uid.isEmpty {
                masterById[uid] = clip
            }
            let nameKey = clip.originalVfxName ?? clip.vfxName
            if !nameKey.isEmpty {
                masterByName[nameKey] = clip
            }
            
            let fileReelKey = "\(clip.fileNames)|\(clip.reelName)"
            if !clip.fileNames.isEmpty || !clip.reelName.isEmpty {
                masterByFileAndReel[fileReelKey] = clip
            }
        }
        
        for imp in imported {
            var matchedMaster: ClipData?
            
            // 1. Try resolving by DaVinci Unique ID
            if let uid = imp.uniqueId, !uid.isEmpty, let match = masterById[uid] {
                matchedMaster = match
            } 
            // 2. Try resolving by VFX Name
            else {
                let nameKey = imp.originalVfxName ?? imp.vfxName
                if !nameKey.isEmpty, let match = masterByName[nameKey] {
                    matchedMaster = match
                }
                // 3. Try resolving by File and Reel matching exactly
                else {
                    let fileReelKey = "\(imp.fileNames)|\(imp.reelName)"
                    if (!imp.fileNames.isEmpty || !imp.reelName.isEmpty), let match = masterByFileAndReel[fileReelKey] {
                        matchedMaster = match
                    }
                }
            }
            
            if let masterClip = matchedMaster {
                // Check if properties changed
                let isIdentical = (
                    masterClip.tcIn == imp.tcIn &&
                    masterClip.tcOut == imp.tcOut &&
                    masterClip.duration == imp.duration &&
                    masterClip.sourceTcIn == imp.sourceTcIn &&
                    masterClip.sourceTcOut == imp.sourceTcOut &&
                    masterClip.fileNames == imp.fileNames &&
                    masterClip.reelName == imp.reelName
                )
                
                let state: MergeState = isIdentical ? .identical : .modified
                // By default, do not select "identical" to save processing/visual clutter, but select new & modified
                results.append(MergeItem(masterClip: masterClip, importedClip: imp, state: state, selected: state == .modified))
            } else {
                // Completely new
                results.append(MergeItem(masterClip: nil, importedClip: imp, state: .new, selected: true))
            }
        }
        
        return results
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
