import SwiftUI

struct DaVinciImportSheet: View {
    @Binding var vfxTrack: String
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
                Text("Please configure the import settings for your current DaVinci Resolve timeline:")
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
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
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
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(vfxTrack.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 450, height: 300)
    }
}
