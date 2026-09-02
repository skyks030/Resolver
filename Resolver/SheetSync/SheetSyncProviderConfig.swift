import Foundation
import Security

// Which remote spreadsheet service a project is linked to. The raw value is what's persisted on
// `Project.sheetSyncProvider` and passed to the Python sync scripts.
enum SheetSyncProviderKind: String, CaseIterable, Identifiable {
    case microsoft
    case google

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .microsoft: return "Microsoft Excel (OneDrive for Business)"
        case .google: return "Google Sheets"
        }
    }

    var linkPlaceholder: String {
        switch self {
        case .microsoft: return "Paste the Excel Online \"Edit\" share link…"
        case .google: return "Paste the Google Sheets share link…"
        }
    }
}

// Fixed redirect values for Microsoft's custom-scheme flow — must exactly match what's entered
// as the Redirect URI in the Entra app registration, and what's registered as a CFBundleURLTypes
// entry in the app's Info.plist (Xcode → target → Info tab → URL Types).
enum SheetSyncRedirect {
    static let microsoftScheme = "resolver-msauth"
    static let microsoftURI = "resolver-msauth://auth"
}

// Client ID/Secret are entered by the user in Settings → Sheet Sync (SheetSyncSettingsView) —
// never hardcoded or edited in a setup file. Client IDs are public, non-secret identifiers by
// design (both providers document this — PKCE is the actual security layer), so plain
// UserDefaults is an appropriate store for those. Google's installed-app "client secret" isn't
// meant to be kept confidential either per Google's own docs, but it's still stored in Keychain
// alongside the actual sign-in tokens (see OAuthPKCESession) as defense in depth rather than a
// plaintext preferences file, at essentially no extra cost.
enum SheetSyncCredentialsKeys {
    static let microsoftClientId = "sheetSync.microsoftClientId"
    static let googleClientId = "sheetSync.googleClientId"
}

// Minimal Keychain get/set for the one credential (Google's client secret) that doesn't belong in
// plain UserDefaults. Same service namespace and accessibility level as OAuthPKCESession's
// refresh-token storage — see that file for why kSecAttrAccessibleWhenUnlockedThisDeviceOnly.
private enum SheetSyncSecretsKeychain {
    private static let service = "com.skyks030.Resolver.SheetSync"

    static func set(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }
}

enum SheetSyncCredentials {
    static var microsoftClientId: String {
        UserDefaults.standard.string(forKey: SheetSyncCredentialsKeys.microsoftClientId) ?? ""
    }
    static var googleClientId: String {
        UserDefaults.standard.string(forKey: SheetSyncCredentialsKeys.googleClientId) ?? ""
    }
    static var googleClientSecret: String {
        get { SheetSyncSecretsKeychain.get(account: "googleClientSecret") }
    }

    static func setGoogleClientSecret(_ value: String) {
        SheetSyncSecretsKeychain.set(value, account: "googleClientSecret")
    }

    static var isMicrosoftConfigured: Bool {
        !microsoftClientId.trimmingCharacters(in: .whitespaces).isEmpty
    }
    static var isGoogleConfigured: Bool {
        !googleClientId.trimmingCharacters(in: .whitespaces).isEmpty
            && !googleClientSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

extension OAuthProviderConfig {
    static var microsoft: OAuthProviderConfig {
        OAuthProviderConfig(
            providerId: "microsoft",
            authorizationEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
            tokenEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
            clientId: SheetSyncCredentials.microsoftClientId,
            clientSecret: nil,
            // Files.ReadWrite (without .All) only covers files the signed-in user owns — a
            // pasted share link almost always points at a file OWNED by a teammate and merely
            // shared with this account, which Graph rejects under the narrower scope with a 403
            // accessDenied on /shares/{shareId}/driveItem even though the sign-in itself succeeds.
            // See https://learn.microsoft.com/en-us/onedrive/developer/rest-api/concepts/permissions_reference
            scope: "offline_access openid profile Files.ReadWrite.All",
            redirectURI: SheetSyncRedirect.microsoftURI,
            redirectScheme: SheetSyncRedirect.microsoftScheme,
            usesLoopbackRedirect: false,
            extraAuthParams: [:]
        )
    }

    static var google: OAuthProviderConfig {
        OAuthProviderConfig(
            providerId: "google",
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
            clientId: SheetSyncCredentials.googleClientId,
            clientSecret: SheetSyncCredentials.googleClientSecret,
            scope: "https://www.googleapis.com/auth/spreadsheets https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile",
            redirectURI: "", // unused — see usesLoopbackRedirect
            redirectScheme: "",
            // Google deprecated custom URL scheme redirects for native apps; the loopback flow
            // needs no redirect URI to be registered in Google Cloud Console at all.
            usesLoopbackRedirect: true,
            // access_type=offline + prompt=consent: without these Google often omits the
            // refresh_token on anything but the very first consent for a given account.
            extraAuthParams: ["access_type": "offline", "prompt": "consent"]
        )
    }

    static func forProvider(_ kind: SheetSyncProviderKind) -> OAuthProviderConfig {
        switch kind {
        case .microsoft: return .microsoft
        case .google: return .google
        }
    }
}
