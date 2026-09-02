import Foundation

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

enum SheetSyncCredentials {
    // ⚠️ SETUP REQUIRED — these are placeholders. Sheet Sync cannot sign in until you fill these
    // in with your own one-time app registrations (this is a one-time setup for Resolver as a
    // whole, not something each user does):
    //
    // Microsoft: https://entra.microsoft.com → Entra ID → App registrations → New registration.
    //   - Platform: "Mobile and desktop applications", redirect URI: resolver-msauth://auth
    //   - API permissions → Microsoft Graph → Delegated → Files.ReadWrite (+ offline_access,
    //     openid, profile, which are usually pre-granted)
    //   - Copy the "Application (client) ID" into microsoftClientId below.
    //
    // Google: https://console.cloud.google.com/apis/credentials → Create Credentials →
    //   OAuth client ID → Application type: "Desktop app".
    //   - Enable the "Google Sheets API" for the project (APIs & Services → Library).
    //   - Copy the Client ID into googleClientId below. The "client secret" Google issues
    //     alongside it is not sensitive for this client type — copy it into googleClientSecret too.
    static let microsoftClientId = "REPLACE_WITH_YOUR_AZURE_APPLICATION_CLIENT_ID"
    static let googleClientId = "REPLACE_WITH_YOUR_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com"
    static let googleClientSecret = "REPLACE_WITH_YOUR_GOOGLE_OAUTH_CLIENT_SECRET"

    static var isMicrosoftConfigured: Bool { !microsoftClientId.hasPrefix("REPLACE_WITH_") }
    static var isGoogleConfigured: Bool { !googleClientId.hasPrefix("REPLACE_WITH_") }
}

extension OAuthProviderConfig {
    static let microsoft = OAuthProviderConfig(
        providerId: "microsoft",
        authorizationEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
        tokenEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
        clientId: SheetSyncCredentials.microsoftClientId,
        clientSecret: nil,
        scope: "offline_access openid profile Files.ReadWrite",
        redirectURI: "resolver-msauth://auth",
        redirectScheme: "resolver-msauth",
        extraAuthParams: [:]
    )

    static let google = OAuthProviderConfig(
        providerId: "google",
        authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
        clientId: SheetSyncCredentials.googleClientId,
        clientSecret: SheetSyncCredentials.googleClientSecret,
        scope: "https://www.googleapis.com/auth/spreadsheets",
        redirectURI: "resolver-googleauth://auth",
        redirectScheme: "resolver-googleauth",
        // access_type=offline + prompt=consent: without these Google often omits the
        // refresh_token on anything but the very first consent for a given account.
        extraAuthParams: ["access_type": "offline", "prompt": "consent"]
    )

    static func forProvider(_ kind: SheetSyncProviderKind) -> OAuthProviderConfig {
        switch kind {
        case .microsoft: return .microsoft
        case .google: return .google
        }
    }
}
