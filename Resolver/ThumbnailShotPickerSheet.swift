import SwiftUI

// Lets the user hand-pick which VFX shots to (re)generate thumbnails for, instead of every shot
// across every registered episode. Search-and-checkbox-list, same shape as BatchEditSheet.
struct ThumbnailShotPickerSheet: View {
    let clips: [ClipData]
    @Binding var selectedIds: Set<UUID>
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    // Anchor for shift-click range selection — same pattern as the master list's
    // handleRowSelectionClick in ProjectExportView.swift.
    @State private var lastToggledId: UUID? = nil

    private var filteredClips: [ClipData] {
        guard !searchText.isEmpty else { return clips }
        return clips.filter { $0.vfxName.localizedCaseInsensitiveContains(searchText) }
    }

    private func handleRowClick(_ clipId: UUID) {
        if NSEvent.modifierFlags.contains(.shift), let anchorId = lastToggledId {
            let visibleIds = filteredClips.map(\.id)
            if let anchorIdx = visibleIds.firstIndex(of: anchorId), let clickedIdx = visibleIds.firstIndex(of: clipId) {
                let range = anchorIdx <= clickedIdx ? anchorIdx...clickedIdx : clickedIdx...anchorIdx
                for i in range { selectedIds.insert(visibleIds[i]) }
                return
            }
        }
        if selectedIds.contains(clipId) {
            selectedIds.remove(clipId)
        } else {
            selectedIds.insert(clipId)
        }
        lastToggledId = clipId
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Select VFX Shots")
                    .font(.title2)
                    .bold()
                Spacer()
                Text("\(selectedIds.count) selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search VFX Name...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .liquidGlassPanel(cornerRadius: 8)

            List {
                ForEach(filteredClips) { clip in
                    HStack {
                        Image(systemName: selectedIds.contains(clip.id) ? "checkmark.square.fill" : "square")
                            .foregroundColor(selectedIds.contains(clip.id) ? .accentColor : .secondary)
                        Text(clip.vfxName)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { handleRowClick(clip.id) }
                }
            }
            .frame(minHeight: 260)
            .help("Shift-click to select a range.")

            Divider()

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Use \(selectedIds.count)") {
                    dismiss()
                }
                .liquidGlassButton(prominent: true)
                .disabled(selectedIds.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420, height: 460)
    }
}
