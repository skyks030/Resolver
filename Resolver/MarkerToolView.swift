import SwiftUI

struct TimelineMarker: Codable, Identifiable {
    var id: String { "\(frameId)_\(color)" }
    let frameId: Int
    let color: String
    let name: String
    let note: String
    let duration: Int
}

struct MarkerToolView: View {
    @State private var markers: [TimelineMarker] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Marker Manager")
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                Button(action: fetchMarkers) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            if isLoading {
                Spacer()
                ProgressView("Loading Markers...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
                Button("Retry", action: fetchMarkers)
                Spacer()
            } else if markers.isEmpty {
                Spacer()
                Text("No markers found in current timeline.")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                // Markers List
                List {
                    ForEach(markers) { marker in
                        HStack(alignment: .center, spacing: 12) {
                            // Color Dot
                            Circle()
                                .fill(colorForMarker(marker.color))
                                .frame(width: 12, height: 12)
                                .help(marker.color)
                            
                            VStack(alignment: .leading) {
                                Text(marker.name.isEmpty ? "(No Name)" : marker.name)
                                    .font(.headline)
                                Text("\(marker.color) | Frame: \(marker.frameId)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if !marker.note.isEmpty {
                                Text(marker.note)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                deleteMarker(marker)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Delete Marker")
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
            
            Divider()
            
            // Footer status
            HStack {
                Text("\(markers.count) Markers")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(10)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear(perform: fetchMarkers)
    }
    
    private func fetchMarkers() {
        isLoading = true
        errorMessage = nil
        
        // Path matches directory structure: Scripts/Resolve/Tools/list_markers.py
        PyScriptRunner.run(scriptName: "Resolve/Tools/list_markers", showOutput: false, enableDownload: false, completion: { output in
            DispatchQueue.main.async {
                isLoading = false
                guard let jsonString = output, let data = jsonString.data(using: .utf8) else {
                    self.errorMessage = "No output from Resolve."
                    return
                }
                
                // Check for error object in JSON
                if let errorDict = try? JSONDecoder().decode([String: String].self, from: data), let metaError = errorDict["error"] {
                     self.errorMessage = metaError
                     return
                }

                do {
                    self.markers = try JSONDecoder().decode([TimelineMarker].self, from: data)
                } catch {
                    self.errorMessage = "Failed to parse markers: \(error.localizedDescription)"
                }
            }
        })
    }
    
    private func deleteMarker(_ marker: TimelineMarker) {
        // Path matches directory structure: Scripts/Resolve/Tools/delete_marker.py
        // Args: FrameID, Color
        PyScriptRunner.run(scriptName: "Resolve/Tools/delete_marker", args: [String(marker.frameId), marker.color], showOutput: false, enableDownload: false, completion: { _ in
            // Refresh list after deletion logic (optimistic remove or refresh)
            DispatchQueue.main.async {
                // Optimistic remove to feel snappier? Or safe refresh?
                // Safe refresh ensures it's actually gone.
                // But list might be long. Let's try optimistic removal first.
                if let index = markers.firstIndex(where: { $0.id == marker.id }) {
                    markers.remove(at: index)
                }
                // Optional: Trigger background refresh?
            }
        })
    }
    
    private func colorForMarker(_ name: String) -> Color {
        switch name.lowercased() {
        case "blue": return .blue
        case "cyan": return .cyan
        case "green": return .green
        case "yellow": return .yellow
        case "red": return .red
        case "pink": return .pink
        case "purple": return .purple
        case "fuchsia": return .purple
        case "rose": return .pink
        case "lavender": return .purple.opacity(0.5)
        case "cream": return Color(red: 1.0, green: 0.99, blue: 0.82)
        case "chocolate": return .brown
        case "cocoa": return .brown
        case "sand": return .orange.opacity(0.5)
        case "mint": return .mint
        case "lemon": return .yellow
        default: return .gray
        }
    }
}
