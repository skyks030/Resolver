import Foundation

enum SheetSyncError: LocalizedError {
    case noResponse
    case remote(String)
    case unexpected

    var errorDescription: String? {
        switch self {
        case .noResponse: return "No response from the sync script. Check Debug Mode for details."
        case .remote(let message): return message
        case .unexpected: return "Unexpected response from the sync script. Check Debug Mode for details."
        }
    }
}

// Shared result shape for every Resolve/Tools/sheet_sync.py action — only the fields relevant to
// the action that was actually run get populated.
struct SheetSyncScriptResult {
    var rows: [[String: String]] = []
    var sheetName: String = ""
    var name: String = ""
    var email: String = ""
    var written: Int = 0
}

// Auth + script plumbing shared by SheetSyncView (linking a project's sheet) and
// SheetSyncSettingsView (testing a provider's sign-in independent of any specific sheet).
enum SheetSyncScriptRunner {
    /// A currently-valid access token for `kind`, prompting an interactive sign-in if there's no
    /// stored session yet (or the provider revoked it).
    @MainActor
    static func validToken(for kind: SheetSyncProviderKind) async throws -> String {
        let session = OAuthPKCESession.shared(for: kind)
        do {
            return try await session.validAccessToken()
        } catch OAuthError.notSignedIn {
            try await session.signIn()
            return try await session.validAccessToken()
        }
    }

    /// Wraps PyScriptRunner's completion-handler API (see Resolve/Tools/sheet_sync.py) as async.
    static func run(
        action: String, provider: SheetSyncProviderKind, token: String,
        link: String? = nil, sheetName: String? = nil, rows: [[String: String]]? = nil,
        columnOrder: [String]? = nil
    ) async throws -> SheetSyncScriptResult {
        var payload: [String: Any] = [
            "action": action,
            "provider": provider.rawValue,
            "accessToken": token,
        ]
        if let link { payload["link"] = link }
        if let sheetName, !sheetName.isEmpty { payload["sheetName"] = sheetName }
        if let rows { payload["rows"] = rows }
        // A Swift [String: String] row has no defined key order, so on a brand-new/empty sheet
        // (nothing existing to anchor a header order on) the very first write needs an explicit
        // column order to follow — otherwise new columns land in whatever arbitrary order
        // JSONSerialization happened to produce. See sheet_sync.py's build_header.
        if let columnOrder, !columnOrder.isEmpty { payload["columnOrder"] = columnOrder }

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: tmpURL)

        return try await withCheckedThrowingContinuation { continuation in
            PyScriptRunner.run(scriptName: "Resolve/Tools/sheet_sync", args: [tmpURL.path], showOutput: false, completion: { output in
                try? FileManager.default.removeItem(at: tmpURL)

                guard let line = output.flatMap({ PyScriptRunner.lastJSONLine(in: $0) }),
                      let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    continuation.resume(throwing: SheetSyncError.noResponse)
                    return
                }
                if let err = json["error"] as? String {
                    continuation.resume(throwing: SheetSyncError.remote(err))
                    return
                }
                guard json["status"] as? String == "success" else {
                    continuation.resume(throwing: SheetSyncError.unexpected)
                    return
                }
                var result = SheetSyncScriptResult()
                result.rows = (json["rows"] as? [[String: String]]) ?? []
                result.sheetName = (json["sheetName"] as? String) ?? ""
                result.name = (json["name"] as? String) ?? ""
                result.email = (json["email"] as? String) ?? ""
                result.written = (json["written"] as? Int) ?? 0
                continuation.resume(returning: result)
            })
        }
    }
}
