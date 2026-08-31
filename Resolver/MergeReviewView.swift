import SwiftUI

struct MergeReviewView: View {
    @Binding var mergeItems: [MergeItem]
    @Binding var mergeKey: MergeKeyOption
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @State private var filterState: MergeState? = nil // nil = all
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Review Changes")
                    .font(.title2)
                    .bold()
                Spacer()
                
                let newCount = mergeItems.filter({ $0.state == .new }).count
                let modCount = mergeItems.filter({ $0.state == .modified }).count
                let identCount = mergeItems.filter({ $0.state == .identical }).count
                
                HStack(spacing: 16) {
                    Label("\(newCount) New", systemImage: "plus.circle.fill").foregroundColor(.green)
                    Label("\(modCount) Modified", systemImage: "pencil.circle.fill").foregroundColor(.orange)
                    Label("\(identCount) Identical", systemImage: "checkmark.circle.fill").foregroundColor(.secondary)
                }
                .font(.subheadline)
            }
            .padding()
            .liquidGlassBar()

            Divider()

            // Toolbar
            HStack {
                Picker("Filter:", selection: $filterState) {
                    Text("All").tag(MergeState?.none)
                    Text("New").tag(MergeState.new as MergeState?)
                    Text("Modified").tag(MergeState.modified as MergeState?)
                    Text("Identical").tag(MergeState.identical as MergeState?)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 300)
                
                Spacer()
                
                HStack {
                    Text("Merge Key:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("", selection: $mergeKey) {
                        ForEach(MergeKeyOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 180)
                }
                
                Button("Select All Visible") {
                    for i in mergeItems.indices {
                        if filterState == nil || mergeItems[i].state == filterState {
                            mergeItems[i].selected = true
                        }
                    }
                }
                Button("Deselect All Visible") {
                    for i in mergeItems.indices {
                        if filterState == nil || mergeItems[i].state == filterState {
                            mergeItems[i].selected = false
                        }
                    }
                }
            }
            .padding(10)
            
            Divider()
            
            // Headers
            HStack(spacing: 12) {
                Text("Import").frame(width: 50)
                Text("Status").frame(width: 80, alignment: .leading)
                Text("VFX Name").frame(width: 150, alignment: .leading)
                Text("Changes").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .liquidGlassBar()
            
            Divider()
            
            // List
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach($mergeItems) { $item in
                        if filterState == nil || item.state == filterState {
                            MergeItemRow(item: $item)
                                .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }
            }
            
            Divider()
            
            // Footer Action
            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                let selectedCount = mergeItems.filter { $0.selected }.count
                Button("Apply \(selectedCount) Changes") {
                    onConfirm()
                }
                .liquidGlassButton(prominent: true)
                .disabled(selectedCount == 0)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

struct MergeItemRow: View {
    @Binding var item: MergeItem
    
    var rowColor: Color {
        switch item.state {
        case .new: return Color.green.opacity(0.1)
        case .modified: return Color.orange.opacity(0.1)
        case .identical: return Color.clear
        }
    }
    
    var stateLabel: some View {
        switch item.state {
        case .new:
            return Label("New", systemImage: "plus.circle.fill").foregroundColor(.green)
        case .modified:
            return Label("Modified", systemImage: "pencil.circle.fill").foregroundColor(.orange)
        case .identical:
            return Label("Identical", systemImage: "checkmark.circle.fill").foregroundColor(.secondary)
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $item.selected)
                .frame(width: 50)
                .labelsHidden()
            
            VStack(alignment: .leading, spacing: 1) {
                stateLabel
                    .font(.caption)
                if let confidence = item.matchConfidence {
                    Text("via \(confidence.label)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 80, alignment: .leading)

            Text(item.importedClip.vfxName)
                .bold()
                .frame(width: 150, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 2) {
                if item.state == .modified, let master = item.masterClip {
                    // Show dynamic diffs
                    let diffKeys = Set(master.dict.keys).union(item.importedClip.dict.keys).filter {
                        (master.dict[$0] ?? "") != (item.importedClip.dict[$0] ?? "")
                    }.sorted()
                    
                    if diffKeys.isEmpty {
                        Text("No visible differences in columns")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(diffKeys, id: \.self) { key in
                            diffText(title: key, old: master.dict[key] ?? "", new: item.importedClip.dict[key] ?? "")
                        }
                    }
                } else if item.state == .new {
                    Text("New Clip Entry")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !item.candidateMasterClips.isEmpty {
                        Text("\(item.candidateMasterClips.count) similar existing shot(s) found but not linked — ambiguous match, review manually")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                } else {
                    Text("No significant changes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
        }
        .padding(.horizontal)
        .background(rowColor)
    }
    
    @ViewBuilder
    func diffText(title: String, old: String, new: String) -> some View {
        HStack {
            Text("\(title):").font(.caption).bold().foregroundColor(.secondary)
            Text(old).font(.caption).strikethrough().foregroundColor(.red)
            Image(systemName: "arrow.right").font(.caption2).foregroundColor(.secondary)
            Text(new).font(.caption).foregroundColor(.green)
        }
    }
}
