import Foundation
import AuthenticationServices
import CryptoKit
import Security
import AppKit

// MARK: - Provider configuration

// Everything a specific OAuth provider (Microsoft, Google) needs to run the standard
// Authorization Code + PKCE flow for a native/public client — no client secret is treated as
// confidential here (Google issues one for "Desktop app" clients, but per Google's own docs it
// isn't meant to be kept secret; PKCE is the actual security layer for both providers).
struct OAuthProviderConfig {
    let providerId: String // "microsoft" or "google" — used as the Keychain account name
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let clientId: String
    let clientSecret: String? // nil for Microsoft; Google's installed-app "secret"
    let scope: String
    // Fixed custom-scheme redirect (Microsoft — still supported for its "Mobile and desktop
    // applications" platform). Unused when usesLoopbackRedirect is true.
    let redirectURI: String // e.g. "resolver-msauth://auth"
    let redirectScheme: String // e.g. "resolver-msauth" — must match a CFBundleURLSchemes entry
    // Google deprecated custom URL scheme redirects for native apps (app-impersonation risk) and
    // requires the loopback flow instead — see LoopbackOAuthListener. When true, redirectURI/
    // redirectScheme above are ignored; the redirect URI is built per sign-in as
    // "http://127.0.0.1:<ephemeral port>", which Google's backend accepts automatically for
    // "Desktop app" clients with nothing to pre-register.
    let usesLoopbackRedirect: Bool
    // Extra provider-specific authorization query params (e.g. Google needs
    // access_type=offline + prompt=consent to reliably hand back a refresh_token).
    let extraAuthParams: [String: String]
}

enum OAuthError: LocalizedError {
    case cancelled
    case missingCode
    case tokenExchangeFailed(String)
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Sign-in was cancelled."
        case .missingCode: return "The sign-in page didn't return an authorization code."
        case .tokenExchangeFailed(let detail): return "Sign-in failed: \(detail)"
        case .notSignedIn: return "Not signed in."
        }
    }
}

// Runs the OAuth2 Authorization Code + PKCE flow for one provider, via ASWebAuthenticationSession
// (the only piece of this that has to live in Swift — it needs a live window to present the
// sign-in sheet). Stores the refresh token in Keychain; the access token is cached in memory and
// silently refreshed on demand, never round-tripping through the sign-in UI again unless the
// refresh token itself is invalid/revoked (`OAuthError.notSignedIn`, at which point callers should
// prompt the user to sign in again via `signIn()`).
@MainActor
final class OAuthPKCESession: NSObject {
    private let config: OAuthProviderConfig
    private var webAuthSession: ASWebAuthenticationSession?
    private var cachedAccessToken: String?
    private var cachedAccessTokenExpiry: Date?

    init(config: OAuthProviderConfig) {
        self.config = config
    }

    var isSignedIn: Bool {
        (try? loadRefreshToken()) != nil
    }

    func signOut() {
        ConsoleLogger.shared.log("▶️ Sheet Sync: signing out of \(config.providerId).")
        cachedAccessToken = nil
        cachedAccessTokenExpiry = nil
        deleteRefreshToken()
    }

    /// Interactive sign-in: presents the provider's login page, exchanges the resulting code for
    /// tokens, and stores the refresh token. Call once when the user links a new sheet, or again
    /// if `validAccessToken()` throws `.notSignedIn`.
    func signIn() async throws {
        ConsoleLogger.shared.log("▶️ Sheet Sync: starting \(config.providerId) sign-in…")
        let verifier = Self.randomVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = UUID().uuidString

        // Google deprecated custom-scheme redirects for native apps, so it needs a fresh
        // loopback port per sign-in; Microsoft still uses the fixed custom-scheme redirect.
        var loopbackListener: LoopbackOAuthListener?
        let redirectURI: String
        if config.usesLoopbackRedirect {
            ConsoleLogger.shared.log("▶️ Sheet Sync: \(config.providerId) uses the loopback redirect — starting local listener…")
            let listener = LoopbackOAuthListener()
            let port = try await listener.start()
            loopbackListener = listener
            redirectURI = "http://127.0.0.1:\(port)"
        } else {
            redirectURI = config.redirectURI
            ConsoleLogger.shared.log("▶️ Sheet Sync: \(config.providerId) uses the fixed redirect \(redirectURI)")
        }

        guard var comps = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw OAuthError.tokenExchangeFailed("Invalid authorization endpoint")
        }
        var items = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: config.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        for (key, value) in config.extraAuthParams {
            items.append(URLQueryItem(name: key, value: value))
        }
        comps.queryItems = items
        guard let authURL = comps.url else {
            throw OAuthError.tokenExchangeFailed("Could not build authorization URL")
        }
        ConsoleLogger.shared.log("▶️ Sheet Sync: opening the \(config.providerId) sign-in page…")

        // The two redirect mechanisms hand back the authorization code in different shapes — a
        // full custom-scheme URL from ASWebAuthenticationSession, vs. a bare HTTP request target
        // (e.g. "/?code=...&state=...") from the loopback listener — so each is parsed on its
        // own terms rather than forced into one shared string format.
        let callbackComps: URLComponents?
        if let loopbackListener {
            // Open the system browser rather than an embedded sign-in sheet — there's no URL
            // scheme for ASWebAuthenticationSession to intercept here, since the redirect is a
            // plain loopback HTTP request our own listener catches directly.
            NSWorkspace.shared.open(authURL)
            let requestTarget = try await loopbackListener.waitForCallback()
            callbackComps = URLComponents(string: "http://127.0.0.1" + requestTarget)
        } else {
            let callbackURL = try await presentSignIn(authURL: authURL)
            callbackComps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        }
        ConsoleLogger.shared.log("▶️ Sheet Sync: \(config.providerId) redirected back — reading the response…")

        let queryItems = callbackComps?.queryItems ?? []

        // The provider itself can reject the request outright (bad redirect URI, bad client ID,
        // consent declined, ...) — surface its actual reason instead of a generic "no code",
        // which is what made this failure mode silent and undiagnosable before this fix.
        if let providerError = queryItems.first(where: { $0.name == "error" })?.value {
            let description = queryItems.first(where: { $0.name == "error_description" })?.value
            let detail = [providerError, description].compactMap { $0 }.joined(separator: ": ")
            ConsoleLogger.shared.log("❌ Sheet Sync: \(config.providerId) rejected the sign-in: \(detail)")
            throw OAuthError.tokenExchangeFailed(detail)
        }

        // CSRF protection: the `state` we get back must be the exact one-time value we sent, so a
        // malicious redirect crafted by something other than the provider we just contacted can't
        // trick this app into completing sign-in with an attacker-supplied authorization code.
        guard let returnedState = queryItems.first(where: { $0.name == "state" })?.value, returnedState == state else {
            ConsoleLogger.shared.log("❌ Sheet Sync: \(config.providerId) callback failed the state (CSRF) check.")
            throw OAuthError.tokenExchangeFailed("Sign-in response did not match this request (state mismatch) — please try again.")
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            ConsoleLogger.shared.log("❌ Sheet Sync: \(config.providerId) callback had no authorization code.")
            throw OAuthError.missingCode
        }

        ConsoleLogger.shared.log("▶️ Sheet Sync: exchanging the \(config.providerId) authorization code for tokens…")
        let tokens = try await exchangeCodeForTokens(code: code, verifier: verifier, redirectURI: redirectURI)
        guard let refreshToken = tokens.refreshToken else {
            ConsoleLogger.shared.log("❌ Sheet Sync: \(config.providerId) did not return a refresh token.")
            throw OAuthError.tokenExchangeFailed("Provider did not return a refresh token — try signing in again.")
        }
        try storeRefreshToken(refreshToken)
        cachedAccessToken = tokens.accessToken
        cachedAccessTokenExpiry = Date().addingTimeInterval(tokens.expiresIn)
        ConsoleLogger.shared.log("✅ Sheet Sync: \(config.providerId) sign-in succeeded and was saved.")
    }

    /// A currently-valid access token, refreshing silently if the cached one is near expiry.
    /// Throws `.notSignedIn` if there's no stored refresh token yet (or the provider revoked it) —
    /// callers should catch that and prompt `signIn()`.
    func validAccessToken() async throws -> String {
        if let token = cachedAccessToken, let expiry = cachedAccessTokenExpiry, expiry > Date().addingTimeInterval(60) {
            return token
        }
        guard let refreshToken = try loadRefreshToken() else {
            ConsoleLogger.shared.log("ℹ️ Sheet Sync: no stored \(config.providerId) sign-in yet.")
            throw OAuthError.notSignedIn
        }
        ConsoleLogger.shared.log("▶️ Sheet Sync: refreshing the \(config.providerId) access token…")
        let tokens = try await exchangeRefreshToken(refreshToken)
        if let newRefreshToken = tokens.refreshToken {
            try storeRefreshToken(newRefreshToken)
        }
        cachedAccessToken = tokens.accessToken
        cachedAccessTokenExpiry = Date().addingTimeInterval(tokens.expiresIn)
        ConsoleLogger.shared.log("✅ Sheet Sync: \(config.providerId) access token refreshed.")
        return tokens.accessToken
    }

    // MARK: - Sign-in presentation

    private func presentSignIn(authURL: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: config.redirectScheme) { [providerId = config.providerId] url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    ConsoleLogger.shared.log("ℹ️ Sheet Sync: \(providerId) sign-in was cancelled by the user.")
                    continuation.resume(throwing: OAuthError.cancelled)
                } else {
                    ConsoleLogger.shared.log("❌ Sheet Sync: \(providerId) sign-in window failed: \(error?.localizedDescription ?? "unknown error")")
                    continuation.resume(throwing: error ?? OAuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            // Share the system browser's existing session (if the user is already signed in
            // there) rather than forcing a fresh login every single time.
            session.prefersEphemeralWebBrowserSession = false
            self.webAuthSession = session
            session.start()
        }
    }

    // MARK: - Token exchange

    private struct TokenResponse {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval
    }

    private func exchangeCodeForTokens(code: String, verifier: String, redirectURI: String) async throws -> TokenResponse {
        var params = [
            "client_id": config.clientId,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ]
        if let secret = config.clientSecret { params["client_secret"] = secret }
        return try await postToken(params)
    }

    private func exchangeRefreshToken(_ refreshToken: String) async throws -> TokenResponse {
        var params = [
            "client_id": config.clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        if let secret = config.clientSecret { params["client_secret"] = secret }
        return try await postToken(params)
    }

    private func postToken(_ params: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = params
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
            ConsoleLogger.shared.log("❌ Sheet Sync: \(config.providerId) token endpoint rejected the request: \(body)")
            throw OAuthError.tokenExchangeFailed(body)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            ConsoleLogger.shared.log("❌ Sheet Sync: \(config.providerId) token endpoint returned an unexpected response.")
            throw OAuthError.tokenExchangeFailed("Unexpected token response")
        }
        let refreshToken = json["refresh_token"] as? String
        let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return TokenResponse(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
    }

    private static func formEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "-._~").union(.alphanumerics)
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - PKCE

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    // MARK: - Keychain (refresh token only — the access token is short-lived and kept in memory)

    private var keychainAccount: String { "com.skyks030.Resolver.sheetsync.\(config.providerId)" }
    private let keychainService = "com.skyks030.Resolver.SheetSync"

    private func storeRefreshToken(_ token: String) throws {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        // Strictest practical option: only readable while the Mac is actually unlocked, and
        // never included in an iCloud Keychain sync or a device backup/migration — this token is
        // meaningless on another machine anyway (bound to this app's registration), so keeping it
        // device-local minimizes where it can ever leak to.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw OAuthError.tokenExchangeFailed("Could not save sign-in to Keychain (status \(status))")
        }
    }

    private func loadRefreshToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    private func deleteRefreshToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension OAuthPKCESession {
    // One long-lived session per provider for the app's lifetime, so a valid in-memory access
    // token survives across multiple Sheet Sync actions (Compare Now, then a push) without
    // re-hitting the token endpoint every single time. The Keychain-backed refresh token behind
    // it persists across launches regardless of this cache.
    @MainActor private static var cache: [String: OAuthPKCESession] = [:]
    // Tracks which Client ID each cached session was built with, since OAuthProviderConfig is
    // now backed by user-editable Settings (SheetSyncCredentials) rather than fixed constants —
    // editing the Client ID there must not silently keep using a stale cached session.
    @MainActor private static var cachedClientIds: [String: String] = [:]

    @MainActor
    static func shared(for kind: SheetSyncProviderKind) -> OAuthPKCESession {
        let config = OAuthProviderConfig.forProvider(kind)
        if let existing = cache[config.providerId], cachedClientIds[config.providerId] == config.clientId {
            return existing
        }
        // The Client ID/Secret just changed in Settings (or this is the first call ever). Either
        // way, a refresh token sitting in Keychain under the OLD credentials must never be read
        // back as "signed in" for the new ones — that's exactly the stale-"Configured" bug this
        // was built to prevent. Only wipe it when there WAS a previous, different value cached;
        // don't touch Keychain on the very first lookup of a session that predates this app launch.
        if let previousClientId = cachedClientIds[config.providerId], previousClientId != config.clientId {
            ConsoleLogger.shared.log("🔑 Sheet Sync: \(config.providerId) Client ID changed — forgetting the previous sign-in.")
            cache[config.providerId]?.signOut()
        }
        let session = OAuthPKCESession(config: config)
        cache[config.providerId] = session
        cachedClientIds[config.providerId] = config.clientId
        return session
    }
}

extension OAuthPKCESession: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

private extension Data {
    /// Base64url, no padding — RFC 7636's encoding for the PKCE verifier/challenge.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
