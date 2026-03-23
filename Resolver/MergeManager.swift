import Foundation

enum MergeState: String, Codable {
    case identical
    case modified
    case new
}

enum MergeKeyOption: String, CaseIterable {
    case clipName = "Clip Name"
    case startTC = "Start TC / Timeline In"
    case sourceIn = "Source In"
    case uniqueId = "DaVinci Unique ID"
}

struct MergeItem: Codable, Identifiable {
    var id: UUID = UUID()
    var masterClip: ClipData?
    var importedClip: ClipData
    var state: MergeState
    var selected: Bool = true // true means user wants to apply this change
}

class MergeManager {
    static func compare(master: [ClipData], imported: [ClipData], mergeKey: MergeKeyOption = .clipName) -> [MergeItem] {
        var results: [MergeItem] = []
        
        // Build lookup maps for Master list based on selected mergeKey
        var masterMap: [String: ClipData] = [:]
        
        for clip in master {
            let key: String
            switch mergeKey {
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
