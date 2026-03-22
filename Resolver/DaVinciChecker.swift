import Foundation
import SwiftUI

struct DaVinciDiagnostic: Codable {
    let success: Bool
    let errorCode: String
    let message: String
    let tips: [String]
    
    enum CodingKeys: String, CodingKey {
        case success
        case errorCode = "error_code"
        case message
        case tips
    }
}

class DaVinciChecker {
    
    static func performPreflightCheck(completion: @escaping (DaVinciDiagnostic?) -> Void) {
        // Run the check_resolve.py script
        PyScriptRunner.run(scriptName: "Resolve/Tools/check_resolve", showOutput: false, enableDownload: false, onProgress: nil) { output in
            guard let jsonString = output, let data = jsonString.data(using: .utf8) else {
                let fallback = DaVinciDiagnostic(
                    success: false,
                    errorCode: "PYTHON_RUNNER_ERROR",
                    message: "Der DaVinci Checker konnte nicht ausgeführt werden.",
                    tips: ["Überprüfen Sie, ob Python 3 auf diesem Mac installiert ist."]
                )
                DispatchQueue.main.async { completion(fallback) }
                return
            }
            
            do {
                let result = try JSONDecoder().decode(DaVinciDiagnostic.self, from: data)
                DispatchQueue.main.async {
                    completion(result)
                }
            } catch {
                let fallback = DaVinciDiagnostic(
                    success: false,
                    errorCode: "JSON_PARSE_ERROR",
                    message: "Fehler beim Auswerten der DaVinci-Diagnosedaten.",
                    tips: ["Das Skript hat unerwartete Ausgabe geliefert:", "\(output ?? "")"]
                )
                DispatchQueue.main.async { completion(fallback) }
            }
        }
    }
    
    /// Helper to format the diagnostic into a readable string for SwiftUI Alerts
    static func formatError(diagnostic: DaVinciDiagnostic) -> String {
        var text = "\(diagnostic.message)\n\n"
        if !diagnostic.tips.isEmpty {
            text += "Lösungsvorschläge:\n"
            for (index, tip) in diagnostic.tips.enumerated() {
                text += "\(index + 1). \(tip)\n"
            }
        }
        text += "\n(Error Code: \(diagnostic.errorCode))"
        return text
    }
}
