import Foundation

/// Bridges Resolve/Tools/jump_to_clip.py — moves DaVinci Resolve's current playhead to a shot's
/// saved Record Timecode In, switching to its registered Episode timeline first if needed. Used by
/// SyncReviewView's clickable clip names when reviewing a DaVinci Resolve index import; see
/// ProjectExportView.jumpToClipInResolve for the call site and episodesMap construction.
enum JumpToClipRunner {
    enum JumpError: LocalizedError {
        case noResponse
        case remote(String)

        var errorDescription: String? {
            switch self {
            case .noResponse: return "No response from DaVinci Resolve. Check Debug Mode for details."
            case .remote(let message): return message
            }
        }
    }

    static func jump(timecode: String, episode: String, episodesMap: [[String: Any]]) async throws {
        let payload: [String: Any] = [
            "timecode": timecode,
            "episode": episode,
            "episodesMap": episodesMap,
        ]
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: tmpURL)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PyScriptRunner.run(scriptName: "Resolve/Tools/jump_to_clip", args: [tmpURL.path], showOutput: false, completion: { output in
                try? FileManager.default.removeItem(at: tmpURL)

                guard let line = output.flatMap({ PyScriptRunner.lastJSONLine(in: $0) }),
                      let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    continuation.resume(throwing: JumpError.noResponse)
                    return
                }
                if let err = json["error"] as? String {
                    continuation.resume(throwing: JumpError.remote(err))
                    return
                }
                guard json["status"] as? String == "success" else {
                    continuation.resume(throwing: JumpError.noResponse)
                    return
                }
                continuation.resume(returning: ())
            })
        }
    }
}
