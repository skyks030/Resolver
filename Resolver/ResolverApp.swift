import SwiftUI

@main
struct ResolverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var projectManager = ProjectManager()
    
    init() {
        UpdateChecker.runUpdateCheck(showOutput: false)
    }
    
    var body: some Scene {
        WindowGroup("Resolver", id: "export") {
            ProjectExportView()
                .environmentObject(projectManager)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        
        MenuBarExtra("Resolver", systemImage: "die.face.6.fill") {
            DropDownMenu()
                .environmentObject(projectManager)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(projectManager)
        }
        
        Window("Double Clip Finder", id: "double-clips") {
            DoubleClipsView()
        }
        
        
        Window("Marker Manager", id: "marker-tool") {
            MarkerToolView()
        }
        
        Window("Processing", id: "loading") {
            LoadingOverlay(message: "Processing...")
                .frame(width: 300, height: 200)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
