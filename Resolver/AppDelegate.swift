import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // App started: Show Dock Icon & Window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // Start Session for Crash Detection
        CrashManager.shared.startSession()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // App terminating
        CrashManager.shared.endSession()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                if window.title == "Resolver" {
                    window.makeKeyAndOrderFront(self)
                    return true
                }
            }
            // If window not found (closed completely), we might need to recreate it?
            // WindowGroup usually handles this if we return true?
            // Or just activating the app is enough for WindowGroup to restore standard scenes?
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }
}
