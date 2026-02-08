import SwiftUI

struct SettingsView: View {
    @AppStorage("thumbnailFormat") private var thumbnailFormat: String = "jpg"
    @AppStorage("thumbnailHeight") private var thumbnailHeight: Int = 512
    @AppStorage("thumbnailQuality") private var thumbnailQuality: Double = 0.8 // Future proofing? sips doesn't easily take quality with resample, but we can try.
    
    // Update Checker
    @StateObject private var updateChecker = UpdateChecker()
    
    var body: some View {
        TabView {
            GeneralSettingsView(format: $thumbnailFormat, height: $thumbnailHeight)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            AboutSettingsView(updateChecker: updateChecker)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 250)
    }
}

struct GeneralSettingsView: View {
    @Binding var format: String
    @Binding var height: Int
    
    var body: some View {
        Form {
            Section(header: Text("Thumbnails")) {
                Picker("Format:", selection: $format) {
                    Text("JPEG").tag("jpg")
                    Text("PNG").tag("png")
                }
                .pickerStyle(.inline)
                
                HStack {
                    TextField("Max Height:", value: $height, formatter: NumberFormatter())
                        .frame(width: 80)
                    Text("pixels")
                }
                
                Text("Thumbnails will be resized to fit this height while maintaining aspect ratio.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

struct AboutSettingsView: View {
    @ObservedObject var updateChecker: UpdateChecker
    
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "die.face.6.fill")
                .resizable()
                .frame(width: 64, height: 64)
                .foregroundColor(.accentColor)
            
            VStack(spacing: 4) {
                Text("Resolver")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 12) {
                Button("GitHub Repository") {
                    if let url = URL(string: "https://github.com/skyks030/Resolver") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                Button("Check for Updates") {
                    // UpdateChecker.runUpdateCheck(showOutput: true) // Static method shows Alert
                    UpdateChecker.runUpdateCheck(showOutput: true)
                    // Also refresh local state
                    updateChecker.checkForUpdates() 
                }
            }
            
            if let updateAvailable = updateChecker.isUpdateAvailable {
                if updateAvailable {
                    Text("Update Available!")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    Text("You are up to date.")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .padding()
    }
}
