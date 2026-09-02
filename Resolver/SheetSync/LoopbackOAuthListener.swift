import Foundation
import Network

// A minimal one-shot local HTTP server for OAuth "loopback" redirects. Google explicitly
// deprecated custom URL scheme redirects for native/desktop apps (app-impersonation risk) and
// now requires this instead: https://developers.google.com/identity/protocols/oauth2/native-app
// — redirect to http://127.0.0.1:<port>, on ANY OS-assigned port, which Google's OAuth backend
// accepts automatically for "Desktop app" clients with no need to pre-register a specific port.
//
// Listens on an ephemeral port, opens the system browser to the authorization URL, accepts
// exactly one incoming request (the redirect), extracts its query string, replies with a short
// "you can close this" page, and shuts down.
//
// @MainActor + explicit `queue: .main` everywhere below is deliberate, not incidental: Network.framework's
// callbacks are plain GCD closures, not natively Swift-Concurrency-aware, so the compiler can't
// prove on its own that they're isolated the way a normal `async` function is. Pinning the whole
// class to the main actor and always scheduling on `.main` makes that true in practice; the
// `MainActor.assumeIsolated` calls inside each callback are what tell the Swift 6 strict
// concurrency checker to trust that guarantee, instead of erroring on the shared "did we already
// resume this continuation" flags below.
@MainActor
final class LoopbackOAuthListener {
    private var listener: NWListener?
    private var startResumed = false
    private var callbackResumed = false

    /// Starts listening on an OS-assigned ephemeral port on 127.0.0.1 and returns that port.
    func start() async throws -> UInt16 {
        ConsoleLogger.shared.log("▶️ Sheet Sync: starting local loopback listener…")
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        startResumed = false
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    guard let self, !self.startResumed else { return }
                    switch state {
                    case .ready:
                        if let port = listener.port {
                            self.startResumed = true
                            ConsoleLogger.shared.log("✅ Sheet Sync: loopback listener ready on port \(port.rawValue)")
                            continuation.resume(returning: port.rawValue)
                        }
                    case .failed(let error):
                        self.startResumed = true
                        ConsoleLogger.shared.log("❌ Sheet Sync: loopback listener failed to start: \(error)")
                        continuation.resume(throwing: error)
                    default:
                        break
                    }
                }
            }
            listener.start(queue: .main)
        }
    }

    /// Waits for exactly one incoming HTTP request and returns its request target (e.g.
    /// "/?code=...&state=..."), then stops listening. The caller is responsible for calling
    /// `start()` first.
    func waitForCallback() async throws -> String {
        guard let listener else {
            throw OAuthError.tokenExchangeFailed("Loopback listener was not started")
        }
        ConsoleLogger.shared.log("▶️ Sheet Sync: waiting for the browser to redirect back…")
        callbackResumed = false
        return try await withCheckedThrowingContinuation { continuation in
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                    connection.start(queue: .main)
                    self?.readRequestTarget(from: connection) { result in
                        MainActor.assumeIsolated {
                            guard let self, !self.callbackResumed else { return }
                            self.callbackResumed = true
                            switch result {
                            case .success(let target):
                                ConsoleLogger.shared.log("✅ Sheet Sync: received the local redirect")
                                self.respondAndClose(connection)
                                continuation.resume(returning: target)
                            case .failure(let error):
                                ConsoleLogger.shared.log("❌ Sheet Sync: local redirect failed: \(error)")
                                connection.cancel()
                                continuation.resume(throwing: error)
                            }
                            listener.cancel()
                        }
                    }
                }
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func readRequestTarget(from connection: NWConnection, completion: @escaping (Result<String, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data, let text = String(data: data, encoding: .utf8) else {
                completion(.failure(OAuthError.tokenExchangeFailed("Empty response from the local sign-in redirect")))
                return
            }
            // First line looks like: "GET /?code=...&state=... HTTP/1.1"
            guard let firstLine = text.components(separatedBy: "\r\n").first,
                  let target = firstLine.components(separatedBy: " ").dropFirst().first else {
                completion(.failure(OAuthError.tokenExchangeFailed("Malformed response from the local sign-in redirect")))
                return
            }
            completion(.success(target))
        }
    }

    private func respondAndClose(_ connection: NWConnection) {
        let body = "<html><body style=\"font-family: -apple-system, sans-serif; padding: 40px; text-align: center;\"><h2>Signed in</h2><p>You can close this tab and go back to Resolver.</p></body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
