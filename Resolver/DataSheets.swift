import SwiftUI

struct ImportDataSheet: View {
    let onDaVinciImport: () -> Void
    let onSceneMarkersImport: () -> Void
    let onCSVImport: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Import Data")
                .font(.title2)
                .bold()
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("Choose a data source:")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 16) {
                Button(action: onCSVImport) {
                    VStack(spacing: 8) {
                        Image(systemName: "tablecells").font(.largeTitle)
                        Text("CSV (UTF-8)")
                            .font(.subheadline)
                        Text("Import VFX clips\nfrom a spreadsheet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 150, height: 130)
                }
                .buttonStyle(.bordered)
                
                Button(action: onDaVinciImport) {
                    VStack(spacing: 8) {
                        Image(systemName: "film").font(.largeTitle)
                        Text("VFX Clips")
                            .font(.subheadline)
                        Text("Index VFX shots\nfrom DaVinci Resolve")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 150, height: 130)
                }
                .buttonStyle(.bordered)
                
                Button(action: onSceneMarkersImport) {
                    VStack(spacing: 8) {
                        Image(systemName: "film.stack").font(.largeTitle)
                        Text("Scene Markers")
                            .font(.subheadline)
                        Text("Import Cream markers\nas Scenes with Timecodes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 150, height: 130)
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical)
            
            Divider()
            
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding()
        .frame(width: 560, height: 340)
    }
}


struct ExportDataSheet: View {
    let onCSVExport: () -> Void
    let onExcelExport: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Export Data")
                .font(.title2)
                .bold()
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("Choose an export format:")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 20) {
                Button(action: onCSVExport) {
                    VStack {
                        Image(systemName: "doc.text").font(.largeTitle).padding(.bottom, 2)
                        Text("CSV Format")
                    }
                    .frame(width: 140, height: 110)
                }
                .buttonStyle(.bordered)
                
                Button(action: onExcelExport) {
                    VStack {
                        Image(systemName: "doc.zipper").font(.largeTitle).padding(.bottom, 2)
                        Text("Excel (w/ Images)")
                    }
                    .frame(width: 140, height: 110)
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical)
            
            Divider()
            
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding()
        .frame(width: 450, height: 320)
    }
}
