import SwiftUI

// Lets the user hand-pick which VFX shots to (re)generate thumbnails for, instead of every shot
// across every registered episode. Search-and-checkbox-list, same shape as BatchEditSheet.
struct ThumbnailShotPickerSheet: View {
    let clips: [ClipData]
    @Binding var selectedIds: Set<UUID>
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var filteredClips: [ClipData] {
        guard !searchText.isEmpty else { return clips }
        return clips.filter { $0.vfxName.localizedCaseInsensitiveContains(searchText) }
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
                    Toggle(isOn: Binding(
                        get: { selectedIds.contains(clip.id) },
                        set: { isOn in
                            if isOn { selectedIds.insert(clip.id) } else { selectedIds.remove(clip.id) }
                        }
                    )) {
                        Text(clip.vfxName)
                    }
                }
            }
            .frame(minHeight: 260)

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
