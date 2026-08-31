import SwiftUI

struct ImportDataSheet: View {
    let onDaVinciImport: () -> Void
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
                    .frame(width: 170, height: 140)
                }
                .liquidGlassButton(prominent: false)

                Button(action: onDaVinciImport) {
                    VStack(spacing: 8) {
                        daVinciResolveBadge
                        Text("Import from DaVinci Resolve")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                        Text("Index VFX shots from the\ncurrently open timeline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 170, height: 140)
                }
                .liquidGlassButton(prominent: false)
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
        .frame(width: 580, height: 350)
    }

    // A small original badge evoking DaVinci Resolve's color-grading identity
    // (dark tile + colorful arc), used to visually flag "this specifically
    // pulls from the live DaVinci Resolve app" rather than a generic file.
    private var daVinciResolveBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.10, blue: 0.12), Color(red: 0.18, green: 0.18, blue: 0.21)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            Circle()
                .trim(from: 0, to: 0.78)
                .stroke(
                    AngularGradient(colors: [.orange, .pink, .purple, .blue, .cyan, .orange], center: .center),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(7)
            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 40, height: 40)
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
                .liquidGlassButton(prominent: false)
                
                Button(action: onExcelExport) {
                    VStack {
                        Image(systemName: "doc.zipper").font(.largeTitle).padding(.bottom, 2)
                        Text("Excel (w/ Images)")
                    }
                    .frame(width: 140, height: 110)
                }
                .liquidGlassButton(prominent: false)
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
