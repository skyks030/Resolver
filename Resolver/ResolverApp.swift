import SwiftUI

@main
struct ResolverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var projectManager = ProjectManager()
    
    init() {
        UpdateChecker.runUpdateCheck(showOutput: false)
        CrashManager.shared.checkForCrash() // Check immediately
    }
    
    var body: some Scene {
        WindowGroup("Resolver", id: "export") {
            ProjectExportView()
                .environmentObject(projectManager)
                .background(CrashObserver())
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
        
        Window("Crash Report", id: "crash-report") {
            CrashReportView()
        }
    }
}

struct CrashObserver: View {
    @Environment(\.openWindow) var openWindow
    @ObservedObject var crashManager = CrashManager.shared
    
    var body: some View {
        EmptyView()
            .onAppear {
                if crashManager.hasCrashReport {
                    openWindow(id: "crash-report")
                }
            }
            .onChange(of: crashManager.hasCrashReport) { hasCrash in
                if hasCrash {
                    openWindow(id: "crash-report")
                }
            }
    }
}
