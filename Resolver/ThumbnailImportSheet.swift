import SwiftUI

struct ThumbnailImportSheet: View {
    @Binding var vfxThumbnailTrack: String
    let onStart: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    
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
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
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
                
                Button("Create Thumbnails") {
                    onStart()
                }
                .buttonStyle(.borderedProminent)
                .disabled(vfxThumbnailTrack.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 450, height: 300)
    }
}
