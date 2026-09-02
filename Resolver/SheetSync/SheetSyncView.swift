import SwiftUI

struct SheetSyncView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var projectManager: ProjectManager
    let project: Project

    @State private var selectedProvider: SheetSyncProviderKind = .microsoft
    @State private var linkText: String = ""
    @State private var sheetNameText: String = ""
    @State private var isBusy = false
    @State private var statusMessage: String = ""
    @State private var showError = false
    @State private var errorMessage = ""

    @State private var showReview = false
    @State private var reviewMergeItems: [MergeItem] = []
    @State private var reviewPushCandidates: [PushCandidate] = []
    @State private var resolvedSheetName: String = ""

    private var linkedProviderKind: SheetSyncProviderKind? {
        project.sheetSyncProvider.flatMap { SheetSyncProviderKind(rawValue: $0) }
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Sheet Sync")
                    .font(.title2)
                    .bold()
                Spacer()
            }

            if let linkedKind = linkedProviderKind, let link = project.sheetSyncLink {
                linkedView(kind: linkedKind, link: link)
            } else {
                linkNewView
            }

            if !statusMessage.isEmpty {
                HStack {
                    if isBusy { ProgressView().controlSize(.small) }
                    Text(statusMessage).font(.caption).foregroundColor(.secondary)
                }
            }

            Spacer()
            Divider()
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding()
        .frame(width: 520, height: 420)
        .alert("Sheet Sync Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: { Text(errorMessage) }
        .sheet(isPresented: $showReview) {
            SheetSyncReviewView(
                mergeItems: $reviewMergeItems,
                pushCandidates: $reviewPushCandidates,
                providerName: (linkedProviderKind ?? selectedProvider).displayName,
                onApply: {
                    showReview = false
                    applySync()
                },
                onCancel: { showReview = false }
            )
        }
    }

    // MARK: - Linking

    private var linkNewView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Service:", selection: $selectedProvider) {
                ForEach(SheetSyncProviderKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if !isProviderConfigured(selectedProvider) {
                Label("This provider isn't configured yet — see SheetSyncProviderConfig.swift for the one-time setup.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            TextField(selectedProvider.linkPlaceholder, text: $linkText)
                .textFieldStyle(.roundedBorder)

            TextField("Sheet/Worksheet name (optional — defaults to the first)", text: $sheetNameText)
                .textFieldStyle(.roundedBorder)

            Button(action: linkAndSignIn) {
                Text("Link & Sign In")
            }
            .liquidGlassButton(prominent: true)
            .disabled(isBusy || linkText.trimmingCharacters(in: .whitespaces).isEmpty || !isProviderConfigured(selectedProvider))
        }
        .padding()
        .liquidGlassPanel(cornerRadius: 8)
    }

    private func linkedView(kind: SheetSyncProviderKind, link: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(kind.displayName, systemImage: "link")
                .font(.headline)
            Text(link)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            HStack {
                Button(action: compareNow) {
                    Label("Compare Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .liquidGlassButton(prominent: true)
                .disabled(isBusy)

                Button("Unlink", role: .destructive) { unlink() }
                    .disabled(isBusy)
            }
        }
        .padding()
        .liquidGlassPanel(cornerRadius: 8)
    }

    private func isProviderConfigured(_ kind: SheetSyncProviderKind) -> Bool {
        switch kind {
        case .microsoft: return SheetSyncCredentials.isMicrosoftConfigured
        case .google: return SheetSyncCredentials.isGoogleConfigured
        }
    }

    private func unlink() {
        projectManager.updateSheetSyncLink(projectId: project.id, provider: nil, link: nil, sheetName: nil)
        statusMessage = ""
    }

    private func linkAndSignIn() {
        let link = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else { return }
        let sheetName = sheetNameText.trimmingCharacters(in: .whitespaces)
        isBusy = true
        statusMessage = "Signing in to \(selectedProvider.displayName)…"
        ConsoleLogger.shared.log("▶️ Sheet Sync: linking \(selectedProvider.rawValue) — \(link)")

        Task {
            do {
                let session = OAuthPKCESession.shared(for: selectedProvider)
                if session.isSignedIn {
                    _ = try? await session.validAccessToken()
                }
                if !session.isSignedIn {
                    try await session.signIn()
                }
                projectManager.updateSheetSyncLink(
                    projectId: project.id,
                    provider: selectedProvider.rawValue,
                    link: link,
                    sheetName: sheetName.isEmpty ? nil : sheetName
                )
                isBusy = false
                statusMessage = "Linked. Ready to compare."
                ConsoleLogger.shared.log("✅ Sheet Sync: linked and signed in to \(selectedProvider.rawValue)")
            } catch {
                isBusy = false
                ConsoleLogger.shared.log("❌ Sheet Sync sign-in failed: \(error)")
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Compare

    private func compareNow() {
        guard let kind = linkedProviderKind, let link = project.sheetSyncLink else { return }
        isBusy = true
        statusMessage = "Connecting to \(kind.displayName)…"
        ConsoleLogger.shared.log("▶️ Sheet Sync: comparing against \(kind.rawValue) — \(link)")

        Task {
            do {
                let token = try await validToken(for: kind)
                let (rows, sheetName) = try await runSheetScript(
                    action: "fetch", provider: kind, token: token, link: link,
                    sheetName: project.sheetSyncSheetName, rows: nil
                )
                resolvedSheetName = sheetName

                let remoteClips = rows.map { ClipData(dict: $0) }
                let items = MergeManager.smartCompare(master: projectManager.currentMasterList, imported: remoteClips)
                let matchedMasterIds = Set(items.compactMap { $0.masterClip?.id })
                let localOnly = projectManager.currentMasterList.filter { !matchedMasterIds.contains($0.id) }

                reviewMergeItems = items
                reviewPushCandidates = localOnly.map { PushCandidate(clip: $0) }
                isBusy = false
                statusMessage = ""
                ConsoleLogger.shared.log("✅ Sheet Sync: fetched \(rows.count) row(s) from '\(sheetName)', \(items.filter { $0.state == .new }.count) new, \(items.filter { $0.state == .modified }.count) modified, \(localOnly.count) local-only")
                showReview = true
            } catch {
                isBusy = false
                ConsoleLogger.shared.log("❌ Sheet Sync compare failed: \(error)")
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Apply

    private func applySync() {
        // Pull: everything marked "use remote" — MergeManager.applyMerge only touches
        // selected==true items, exactly matching the review's "Use <Provider>" choice.
        let oldList = projectManager.currentMasterList
        var newMaster = projectManager.currentMasterList
        MergeManager.applyMerge(master: &newMaster, mergeItems: reviewMergeItems)
        if newMaster != oldList {
            projectManager.updateMasterList(with: newMaster)
            projectManager.registerUndo(\.currentMasterList, actionName: "Sheet Sync", from: oldList) {
                self.projectManager.saveMasterList()
            }
        }

        // Push: local-only rows kept selected, plus "modified" rows where the user chose to keep
        // the local value (selected == false here means "don't take remote's value" — so the
        // local value needs to be written back out to the sheet instead).
        var rowsToPush: [[String: String]] = []
        for candidate in reviewPushCandidates where candidate.selected {
            rowsToPush.append(sheetRow(for: candidate.clip))
        }
        for item in reviewMergeItems where item.state == .modified && !item.selected {
            if let master = item.masterClip { rowsToPush.append(sheetRow(for: master)) }
        }

        guard !rowsToPush.isEmpty, let kind = linkedProviderKind, let link = project.sheetSyncLink else { return }
        isBusy = true
        statusMessage = "Writing \(rowsToPush.count) row(s) to \(kind.displayName)…"
        ConsoleLogger.shared.log("▶️ Sheet Sync: pushing \(rowsToPush.count) row(s) to \(kind.rawValue)")

        Task {
            do {
                let token = try await validToken(for: kind)
                let sheetName = resolvedSheetName.isEmpty ? project.sheetSyncSheetName : resolvedSheetName
                _ = try await runSheetScript(action: "write", provider: kind, token: token, link: link, sheetName: sheetName, rows: rowsToPush)
                isBusy = false
                statusMessage = "Sync complete."
                ConsoleLogger.shared.log("✅ Sheet Sync: push complete")
            } catch {
                isBusy = false
                ConsoleLogger.shared.log("❌ Sheet Sync push failed: \(error)")
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func sheetRow(for clip: ClipData) -> [String: String] {
        var row = clip.dict
        if (row["Resolve Unique ID"] ?? "").isEmpty {
            // No Resolve-native ID (e.g. a manually-added local shot) — fall back to Resolver's
            // own stable local ID so this row can still be matched back up on the next sync.
            row["Resolve Unique ID"] = clip.id.uuidString
        }
        return row
    }

    // MARK: - Auth + script plumbing

    private func validToken(for kind: SheetSyncProviderKind) async throws -> String {
        let session = OAuthPKCESession.shared(for: kind)
        do {
            return try await session.validAccessToken()
        } catch OAuthError.notSignedIn {
            try await session.signIn()
            return try await session.validAccessToken()
        }
    }

    // Wraps PyScriptRunner's completion-handler API (see Resolve/Tools/sheet_sync.py) as async.
    // Returns (rows, resolvedSheetName) for "fetch"; rows is empty for "write".
    private func runSheetScript(
        action: String, provider: SheetSyncProviderKind, token: String, link: String,
        sheetName: String?, rows: [[String: String]]?
    ) async throws -> ([[String: String]], String) {
        var payload: [String: Any] = [
            "action": action,
            "provider": provider.rawValue,
            "accessToken": token,
            "link": link,
        ]
        if let sheetName, !sheetName.isEmpty { payload["sheetName"] = sheetName }
        if let rows { payload["rows"] = rows }

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: tmpURL)

        return try await withCheckedThrowingContinuation { continuation in
            PyScriptRunner.run(scriptName: "Resolve/Tools/sheet_sync", args: [tmpURL.path], showOutput: false) { output in
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
                let rows = (json["rows"] as? [[String: String]]) ?? []
                let sheetName = (json["sheetName"] as? String) ?? ""
                continuation.resume(returning: (rows, sheetName))
            }
        }
    }
}
