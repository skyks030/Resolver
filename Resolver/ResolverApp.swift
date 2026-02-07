import SwiftUI

@main
struct ResolverApp: App {
    @StateObject private var projectManager = ProjectManager()
    
    init() {
        UpdateChecker.runUpdateCheck(showOutput: false)
    }
    
    var body: some Scene {
        MenuBarExtra("Resolver", systemImage: "die.face.6.fill") {
            DropDownMenu()
                .environmentObject(projectManager)
        }
        .menuBarExtraStyle(.window)
        
        WindowGroup("Project Export", id: "export") {
            ProjectExportView()
                .environmentObject(projectManager)
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "export"))
    }
}
