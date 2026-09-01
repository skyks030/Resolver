import SwiftUI

struct ThumbnailImportSheet: View {
    @Binding var vfxThumbnailTrack: String
    @Binding var allShots: Bool
    var selectedShotCount: Int = 0
    var hasExistingThumbnails: Bool = false
    let onPickShots: () -> Void
    let onStart: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    private var mainButtonTitle: String {
        if allShots {
            return hasExistingThumbnails ? "Regenerate All Thumbnails" : "Generate All Thumbnails"
        } else {
            return "Regenerate \(selectedShotCount) Shot\(selectedShotCount == 1 ? "" : "s")"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Thumbnails")
                    .font(.title2)
                    .bold()
                Spacer()
            }
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 12) {
                Text("Select the track DaVinci Resolve should pull thumbnails from:")
                    .font(.body)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Source Video Track:")
                        .bold()
                        .frame(width: 200, alignment: .leading)

                    TextField("e.g. 1", text: $vfxThumbnailTrack)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 80)
                        .onChange(of: vfxThumbnailTrack) { newValue in
                            let filtered = newValue.filter { "0123456789".contains($0) }
                            if filtered != newValue { vfxThumbnailTrack = filtered }
                            if vfxThumbnailTrack.count > 2 { vfxThumbnailTrack = String(vfxThumbnailTrack.prefix(2)) }
                        }
                }

                Divider()

                Toggle(isOn: $allShots) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Generate for all episodes / all shots")
                        Text("Opens and processes every registered episode's timeline. Turn off to pick specific VFX shots instead.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: allShots) { isOn in
                    if !isOn { onPickShots() }
                }

                if !allShots {
                    HStack {
                        Text(selectedShotCount == 0 ? "No shots selected yet." : "\(selectedShotCount) shot\(selectedShotCount == 1 ? "" : "s") selected.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Select Shots…") { onPickShots() }
                            .liquidGlassButton(prominent: false)
                            .controlSize(.small)
                    }
                }
            }
            .padding()
            .liquidGlassPanel(cornerRadius: 8)

            Spacer()

            Divider()

            HStack {
                Button("Delete All", role: .destructive) {
                    onDelete()
                }

                Spacer()

                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(mainButtonTitle) {
                    onStart()
                }
                .liquidGlassButton(prominent: true)
                .disabled(vfxThumbnailTrack.isEmpty || (!allShots && selectedShotCount == 0))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 480, height: allShots ? 320 : 360)
    }
}
