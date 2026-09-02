import SwiftUI
import Combine

class ConsoleLogger: ObservableObject {
    static let shared = ConsoleLogger()
    
    @Published var logs: [String] = []
    
    private init() {}
    
    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timeString = formatter.string(from: Date())
        
        let logMessage = "[\(timeString)] \(message)"
        
        DispatchQueue.main.async {
            self.logs.append(logMessage)
            print(logMessage) // Still print to standard stdout for Xcode
        }
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
    }
}

struct DebugConsoleView: View {
    @ObservedObject var logger = ConsoleLogger.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Debug Console")
                    .font(.headline)
                Spacer()
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(logger.logs.joined(separator: "\n"), forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy All Logs")
                .disabled(logger.logs.isEmpty)

                Button(action: {
                    logger.clear()
                }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Clear Logs")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logger.logs.enumerated()), id: \.offset) { index, log in
                            Text(log)
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .foregroundColor(log.lowercased().contains("error") || log.lowercased().contains("fehlschlag") ? .red : .primary)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: logger.logs.count) { _ in
                    if !logger.logs.isEmpty {
                        proxy.scrollTo(logger.logs.count - 1, anchor: .bottom)
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
