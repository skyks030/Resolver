import SwiftUI

// Settings tab for connecting Microsoft Excel / Google Sheets — this is the ONLY place a Client
// ID/Secret is entered; nothing about Sheet Sync requires touching a file on disk. Each provider
// gets its own step-by-step registration walkthrough (with a button straight to the right portal
// page and copyable values), a place to paste the resulting credentials, and a "Test Sign-In"
// that proves the whole chain works — sign-in, token exchange, a real authenticated API call —
// before the user ever tries linking a real spreadsheet in Sheet Sync.
struct SheetSyncSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Connect Resolver to a Microsoft or Google account so Sheet Sync can read and write a shared spreadsheet directly. Each service needs a one-time, free registration — done once here, not per teammate.")
                    .font(.callout)
                    .foregroundColor(.secondary)

                ProviderSetupSection(kind: .microsoft)
                Divider()
                ProviderSetupSection(kind: .google)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ProviderSetupSection: View {
    let kind: SheetSyncProviderKind

    @AppStorage(SheetSyncCredentialsKeys.microsoftClientId) private var microsoftClientId: String = ""
    @AppStorage(SheetSyncCredentialsKeys.googleClientId) private var googleClientId: String = ""
    // Not @AppStorage: the client secret lives in Keychain (see SheetSyncCredentials), not plain
    // UserDefaults, so it's loaded/saved explicitly rather than bound directly to a preferences key.
    @State private var googleClientSecret: String = ""

    @State private var isTesting = false
    @State private var testResult: TestResult? = nil
    // Whether a real, successful OAuth sign-in is currently on file for this provider — backed by
    // a Keychain-stored refresh token, not just non-empty text fields. This is what "Configured"
    // must reflect; entering a Client ID proves nothing on its own until it's actually been used
    // to sign in at least once (see OAuthPKCESession.isSignedIn / .shared(for:) invalidation).
    @State private var isSignedIn = false

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    // Whether enough has been typed in to even attempt a sign-in — gates the Test Sign-In button,
    // NOT the "Configured" badge (that's `isSignedIn`, checked separately below).
    private var hasCredentials: Bool {
        switch kind {
        case .microsoft: return SheetSyncCredentials.isMicrosoftConfigured
        case .google: return SheetSyncCredentials.isGoogleConfigured
        }
    }

    private func refreshSignInState() {
        isSignedIn = OAuthPKCESession.shared(for: kind).isSignedIn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(kind.displayName, systemImage: kind == .microsoft ? "doc.text" : "tablecells")
                    .font(.title3)
                    .bold()
                Spacer()
                statusBadge
            }

            switch kind {
            case .microsoft: microsoftSteps
            case .google: googleSteps
            }

            fieldsSection

            HStack(alignment: .top, spacing: 10) {
                Button(isTesting ? "Testing…" : "Test Sign-In") {
                    testSignIn()
                }
                .liquidGlassButton(prominent: true)
                .disabled(isTesting || !hasCredentials)

                if isSignedIn {
                    Button("Sign Out", role: .destructive) {
                        OAuthPKCESession.shared(for: kind).signOut()
                        testResult = nil
                        refreshSignInState()
                    }
                    .disabled(isTesting)
                }

                switch testResult {
                case .success(let message):
                    resultRow(message, systemImage: "checkmark.circle.fill", color: .green)
                case .failure(let message):
                    resultRow(message, systemImage: "xmark.circle.fill", color: .red)
                case nil:
                    EmptyView()
                }
            }
        }
        .onAppear {
            if kind == .google { googleClientSecret = SheetSyncCredentials.googleClientSecret }
            refreshSignInState()
        }
        .onChange(of: googleClientSecret) { newValue in
            if kind == .google { SheetSyncCredentials.setGoogleClientSecret(newValue) }
            refreshSignInState()
        }
        .onChange(of: microsoftClientId) { _ in refreshSignInState() }
        .onChange(of: googleClientId) { _ in refreshSignInState() }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isSignedIn {
            Label("Configured", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundColor(.green)
        } else {
            Label("Not connected", systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // A plain `Text`, selectable with the mouse and copyable (⌘C) — unlike `Label`, whose internal
    // text SwiftUI doesn't reliably expose to `.textSelection`. Needed so a failed Test Sign-In's
    // exact error (e.g. Azure/Google's raw rejection reason) can be copied out of the window
    // instead of retyped by hand, per the user's request.
    @ViewBuilder
    private func resultRow(_ message: String, systemImage: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: systemImage).foregroundColor(color)
            Text(message)
                .foregroundColor(color)
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    // MARK: - Instructions

    private var microsoftSteps: some View {
        VStack(alignment: .leading, spacing: 8) {
            step(1, "Open Microsoft Entra ID (this is Microsoft's free app-registration portal — a work/school or even a personal Microsoft account can create one; no paid subscription needed for this step itself).")
            portalButton("Open Microsoft Entra Portal", url: "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade")

            step(2, "Click \"New registration\". Give it any name (e.g. \"Resolver\"). Under \"Supported account types\" any option is fine.")
            step(3, "Under \"Redirect URI\", choose platform \"Mobile and desktop applications\" and paste this exact value:")
            copyableValue("resolver-msauth://auth")

            step(4, "Go to \"API permissions\" → \"Add a permission\" → \"Microsoft Graph\" → \"Delegated permissions\" → search for and check \"Files.ReadWrite\" → \"Add permissions\".")
            step(5, "Go back to \"Overview\" and copy the \"Application (client) ID\" shown there — paste it into the field below.")

            Text("Note: the spreadsheet itself must live on OneDrive for Business or SharePoint — personal/consumer OneDrive isn't supported by Excel's workbook API (a Microsoft platform limitation, not a Resolver one).")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var googleSteps: some View {
        VStack(alignment: .leading, spacing: 8) {
            step(1, "Open Google Cloud Console and create a project if you don't already have one (top-left project picker → \"New Project\").")
            portalButton("Open Google Cloud Console", url: "https://console.cloud.google.com/apis/credentials")

            step(2, "Enable the Sheets API for that project:")
            portalButton("Enable Google Sheets API", url: "https://console.cloud.google.com/apis/library/sheets.googleapis.com")

            step(3, "If prompted to configure an \"OAuth consent screen\" first, choose \"External\", fill in an app name and your own email, and add your own Google account under \"Test users\" (while the app is in \"Testing\" mode, only accounts you add there can sign in).")
            step(4, "Back on the Credentials page: \"Create Credentials\" → \"OAuth client ID\" → Application type \"Desktop app\" → give it any name → \"Create\".")
            step(5, "Copy the \"Client ID\" and \"Client Secret\" shown — paste both into the fields below.")

            Text("No redirect URI needs to be registered for Google — Resolver uses the loopback sign-in method Google recommends for desktop apps (a custom URL scheme is no longer supported by Google for security reasons), which works automatically on any port.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n).")
                .bold()
                .foregroundColor(.secondary)
                .frame(width: 18, alignment: .trailing)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func portalButton(_ title: String, url: String) -> some View {
        Button(title) {
            if let url = URL(string: url) { NSWorkspace.shared.open(url) }
        }
        .liquidGlassButton(prominent: false)
        .controlSize(.small)
        .padding(.leading, 26)
    }

    @ViewBuilder
    private func copyableValue(_ value: String) -> some View {
        HStack {
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(value, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help("Copy")
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
        .padding(.leading, 26)
    }

    // MARK: - Fields

    @ViewBuilder
    private var fieldsSection: some View {
        switch kind {
        case .microsoft:
            LabeledContent("Application (Client) ID:") {
                TextField("", text: $microsoftClientId)
                    .textFieldStyle(.roundedBorder)
            }
        case .google:
            LabeledContent("Client ID:") {
                TextField("", text: $googleClientId)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Client Secret:") {
                SecureField("", text: $googleClientSecret)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Test

    private func testSignIn() {
        isTesting = true
        testResult = nil
        ConsoleLogger.shared.log("▶️ Sheet Sync: Test Sign-In pressed for \(kind.rawValue).")
        Task {
            do {
                let token = try await SheetSyncScriptRunner.validToken(for: kind)
                let result = try await SheetSyncScriptRunner.run(action: "whoami", provider: kind, token: token)
                let who = result.name.isEmpty ? result.email : result.name
                let suffix = (!result.email.isEmpty && result.name != result.email) ? " (\(result.email))" : ""
                isTesting = false
                testResult = .success("Connected as \(who)\(suffix)")
                ConsoleLogger.shared.log("✅ Sheet Sync: Test Sign-In succeeded for \(kind.rawValue) as \(who)\(suffix).")
            } catch {
                isTesting = false
                testResult = .failure(error.localizedDescription)
                ConsoleLogger.shared.log("❌ Sheet Sync: Test Sign-In failed for \(kind.rawValue): \(error.localizedDescription)")
            }
            // Whether it succeeded or failed, re-check whether we now actually hold a valid
            // sign-in — a failure can still follow a successful sign-in step (e.g. the whoami
            // call itself failed), and the badge/redirect-button must track that, not the
            // whoami outcome alone.
            refreshSignInState()
        }
    }
}
