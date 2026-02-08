import SwiftUI

struct LoadingOverlay: View {
    var message: String = "Processing..."
    
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
                ProgressView()
                    .controlSize(.large)
                
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
        LoadingOverlay(message: "Generating Thumbnails...")
            .frame(width: 400, height: 300)
    }
}
