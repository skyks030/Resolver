import Foundation

/// One DaVinci Resolve Color Group, as reported by color_groups.py.
struct ColorGroupInfo: Identifiable, Equatable {
    var id: String { name }
    let name: String
    /// Best-effort clip count for whichever timeline is currently open in Resolve — see
    /// color_groups.py's do_list for why this isn't a project-wide total.
    let clipCount: Int
}

/// Bridges Resolve/Tools/color_groups.py — lists and deletes DaVinci Resolve's project-wide Color
/// Groups (Project.GetColorGroupsList()/DeleteColorGroup(), the Color page's grouping feature).
/// Used by ColorGroupManagerView.
enum ColorGroupManagerRunner {
    enum RunnerError: LocalizedError {
        case noResponse
        case remote(String)

        var errorDescription: String? {
            switch self {
            case .noResponse: return "No response from DaVinci Resolve. Check Debug Mode for details."
            case .remote(let message): return message
            }
        }
    }

    static func list() async throws -> [ColorGroupInfo] {
        let json = try await run(payload: ["action": "list"])
        let groups = (json["groups"] as? [[String: Any]]) ?? []
        return groups.map {
            ColorGroupInfo(name: ($0["name"] as? String) ?? "", clipCount: ($0["clipCount"] as? Int) ?? 0)
        }
    }

    static func delete(groupName: String) async throws {
        _ = try await run(payload: ["action": "delete", "groupName": groupName])
    }

    private static func run(payload: [String: Any]) async throws -> [String: Any] {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: tmpURL)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
            PyScriptRunner.run(scriptName: "Resolve/Tools/color_groups", args: [tmpURL.path], showOutput: false, completion: { output in
                try? FileManager.default.removeItem(at: tmpURL)

                guard let line = output.flatMap({ PyScriptRunner.lastJSONLine(in: $0) }),
                      let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    continuation.resume(throwing: RunnerError.noResponse)
                    return
                }
                if let err = json["error"] as? String {
                    continuation.resume(throwing: RunnerError.remote(err))
                    return
                }
                guard json["status"] as? String == "success" else {
                    continuation.resume(throwing: RunnerError.noResponse)
                    return
                }
                continuation.resume(returning: json)
            })
        }
    }
}
