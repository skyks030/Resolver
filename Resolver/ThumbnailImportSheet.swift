import SwiftUI

// Which point within a VFX shot's Record TC In/Out range the still is grabbed from.
enum ThumbnailFramePosition: String, CaseIterable, Identifiable {
    case start
    case middle
    case end

    var id: String { rawValue }

    var label: String {
        switch self {
        case .start: return "First Frame"
        case .middle: return "Middle Frame"
        case .end: return "Last Frame"
        }
    }
}

// The one named preset the scale control offers besides typing a custom pixel height.
let standardThumbnailHeight = 256

struct ThumbnailImportSheet: View {
    @Binding var framePosition: ThumbnailFramePosition
    @Binding var scaleHeight: Int
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

    // Whether the "Custom" option is selected — tracked independently of `scaleHeight` itself
    // (not derived from it), since a custom value can legitimately equal the standard one (e.g.
    // right after switching to Custom, before typing a new number) and comparing values alone
    // would then snap the picker straight back to "Standard".
    @State private var useCustomScale: Bool = false

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
                HStack {
                    Text("Take Thumbnail from:")
                        .bold()
                    Picker("", selection: $framePosition) {
                        ForEach(ThumbnailFramePosition.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Divider()

                HStack {
                    Text("Downscale to:")
                        .bold()
                    Picker("", selection: $useCustomScale) {
                        Text("Standard").tag(false)
                        Text("Custom").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                    .onChange(of: useCustomScale) { custom in
                        if !custom { scaleHeight = standardThumbnailHeight }
                    }

                    if useCustomScale {
                        TextField("px", value: $scaleHeight, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }

                    Text("→ \(scaleHeight)px")
                        .foregroundColor(.secondary)
                }
                .onAppear { useCustomScale = (scaleHeight != standardThumbnailHeight) }

                Divider()

                Toggle("Generate for all shots", isOn: $allShots)
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
                .disabled(!allShots && selectedShotCount == 0)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 480, height: allShots ? 300 : 340)
    }
}
