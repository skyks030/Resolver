import SwiftUI

@main
struct ResolverApp: App {
    init() {
        UpdateChecker.runUpdateCheck(showOutput: false)
        }
    var body: some Scene {
        MenuBarExtra("Resolver", systemImage: "pill.fill") { //cup.and.heat.waves.fill //cup.and.heat.waves
            DropDownMenu()
        }
        .menuBarExtraStyle(.menu)
    }
}
