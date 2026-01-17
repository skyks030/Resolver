import SwiftUI


struct DropDownMenu: View {
    @State private var showOutput = true
    @State private var enableDownload = true
    
    var body: some View {
        VStack(spacing: 10){
            
            Menu("Resolve") {
                HoverButton(title: "VFX-LIST") {
                    PyScriptRunner.run(scriptName: "clip-grouping", showOutput: showOutput, enableDownload: enableDownload)
                    }
                    
                Menu("Render Notification") {
                    HoverButton(title: "Sky") {
                        PyScriptRunner.run(scriptName: "render-done-sky", showOutput: showOutput)
                    }
                    HoverButton(title: "Simon") {
                        PyScriptRunner.run(scriptName: "render-done-simon", showOutput: showOutput)
                    }
                }
                HoverButton(title: "Transcribe") {
                    PyScriptRunner.run(scriptName: "transcribe", showOutput: showOutput)
                }
            }
            
            
            Menu("DCP") {
                Link("sub-converter", destination: URL(string: "https://www.michaelcinquin.com/tools/DCP/DCP_subtitling")!)
                }
                //.padding(35)
            
            
            Divider()
            
            if let UserName = UserManager.shared.activeUserName {
                Text("Active User: \(UserName)")
            }
            
            Menu("Settings...") {
                
                Menu("User"){
                    HoverButton(title: "Simon"){
                        UserManager.shared.setActiveUser(named: "Simon")
                    }
                    HoverButton(title: "Sky"){
                        UserManager.shared.setActiveUser(named: "Sky")
                    }
                }
                
                Toggle("Show Output", isOn: $showOutput)
                Divider()
                Button("Check for Update") {
                    UpdateChecker.runUpdateCheck(showOutput: true)
                }
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                Divider()
                    // Version Info
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("Version \(version)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .opacity(0.5)
                       
                }
            }
        }.frame(maxWidth: 100)
    }
}
