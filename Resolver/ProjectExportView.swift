import SwiftUI

struct ProjectExportView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var selection: Set<UUID> = []
    
    // Column Toggles
    @State private var showVfxName = true
    @State private var showTcIn = true
    @State private var showTcOut = true
    @State private var showFileNames = true
    
    var body: some View {
        VStack {
            if let project = projectManager.currentProject {
                HStack {
                    Text(project.name)
                        .font(.title)
                        .bold()
                    Spacer()
                    Text("\(project.clips.count) Clips")
                        .foregroundColor(.secondary)
                }
                .padding()
                
                // Column Toggles
                HStack {
                    Toggle("VFX Name", isOn: $showVfxName)
                    Toggle("TC In", isOn: $showTcIn)
                    Toggle("TC Out", isOn: $showTcOut)
                    Toggle("Files", isOn: $showFileNames)
                    Spacer()
                    Button("Export CSV") {
                        exportCSV(project: project)
                    }
                }
                .padding(.horizontal)
                
                // Table
                Table(project.clips, selection: $selection) {
                    TableColumn("VFX Name", value: \.vfxName)
                    TableColumn("TC In", value: \.tcIn)
                    TableColumn("TC Out", value: \.tcOut)
                    TableColumn("File Names", value: \.fileNames)
                }
                .tableStyle(.inset)
                
            } else {
                Text("No Project Selected")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    private func exportCSV(project: Project) {
        // Build Header
        var headers: [String] = []
        if showVfxName { headers.append("VFX-Name") }
        if showTcIn { headers.append("Rec-TC-In") }
        if showTcOut { headers.append("Rec-TC-Out") }
        if showFileNames { headers.append("File-Names") }
        
        // Build Rows
        let rows = project.clips.map { clip -> String in
            var columns: [String] = []
            if showVfxName { columns.append(clip.vfxName) }
            if showTcIn { columns.append(clip.tcIn) }
            if showTcOut { columns.append(clip.tcOut) }
            if showFileNames { columns.append(clip.fileNames) }
            return columns.joined(separator: ",")
        }
        
        let csvContent = ([headers.joined(separator: ",")] + rows).joined(separator: "\n")
        
        // Save Panel
        let panel = NSSavePanel()
        panel.title = "Export Project Data"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(project.name)_Export.csv"
        
        if panel.runModal() == .OK, let url = panel.url {
            try? csvContent.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
