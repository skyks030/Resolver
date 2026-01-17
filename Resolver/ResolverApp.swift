import SwiftUI

@main
struct ResolverApp: App {
    init() {
        UpdateChecker.runUpdateCheck(showOutput: false)
        }
    var body: some Scene {
        MenuBarExtra("Resolver", systemImage: "die.face.6.fill") { //cup.and.heat.waves.fill //cup.and.heat.waves
            DropDownMenu()
        }
        .menuBarExtraStyle(.window)
    }
}
