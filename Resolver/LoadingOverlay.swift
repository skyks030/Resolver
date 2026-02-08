import SwiftUI

struct LoadingOverlay: View {
    var message: String = "Processing..."
    var progress: Double? = nil // 0.0 to 1.0
    var current: Int? = nil
    var total: Int? = nil
    
    var body: some View {
        ZStack {
            // Glassmorphic Background
            if #available(macOS 12.0, *) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
            } else {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
            }
            
            VStack(spacing: 20) {
                if let progress = progress {
                     VStack(spacing: 8) {
                        ProgressView(value: progress) {
                             if let current = current, let total = total {
                                 Text("\(current) / \(total) Clips")
                                     .font(.caption)
                                     .foregroundColor(.secondary)
                             }
                        }
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                     }
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
                
                Text(message)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(radius: 10)
            )
        }
    }
}

struct LoadingOverlay_Previews: PreviewProvider {
    static var previews: some View {
        LoadingOverlay(message: "Indexing VFX Clips...", progress: 0.45, current: 45, total: 100)
            .frame(width: 400, height: 300)
    }
}
