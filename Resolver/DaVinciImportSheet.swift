import SwiftUI

struct DaVinciImportSheet: View {
    @Binding var vfxTrack: String
    @Binding var indexAllEpisodes: Bool
    var episodesCount: Int = 0
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("DaVinci Resolve Import")
                    .font(.title2)
                    .bold()
                Spacer()
            }
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 12) {
                Text(episodesCount > 0 && indexAllEpisodes
                     ? "Please configure the import settings. Every registered episode's timeline will be opened and indexed in turn:"
                     : "Please configure the import settings for your current DaVinci Resolve timeline:")
                    .font(.body)
                    .foregroundColor(.secondary)

                HStack {
                    Text("VFX Video Track Number:")
                        .bold()
                        .frame(width: 200, alignment: .leading)

                    TextField("e.g. 1", text: $vfxTrack)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 80)
                        .onChange(of: vfxTrack) { newValue in
                            let filtered = newValue.filter { "0123456789".contains($0) }
                            if filtered != newValue { vfxTrack = filtered }
                            if vfxTrack.count > 2 { vfxTrack = String(vfxTrack.prefix(2)) }
                        }
                }

                if episodesCount > 0 {
                    Divider()
                    Toggle(isOn: $indexAllEpisodes) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Index All Episodes")
                            Text("Automatically opens and indexes all \(episodesCount) registered episode timelines, instead of only the one currently open in Resolve.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            .liquidGlassPanel(cornerRadius: 8)

            Spacer()
            
            Divider()
            
            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button("Start Import") {
                    onStart()
                }
                .liquidGlassButton(prominent: true)
                .tint(.orange)
                .disabled(vfxTrack.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 480, height: episodesCount > 0 ? 360 : 300)
    }
}
