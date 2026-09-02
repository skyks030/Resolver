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
    // Bumped whenever this window regains focus (e.g. after the user sets up sign-in in the
    // separate Settings window and switches back here) so `isProviderConfigured` — a live Keychain
    // check, not a cached flag — gets re-evaluated instead of showing a stale "not connected" state.
    @State private var signInRefreshTick = false

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
                    Text(statusMessage).font(.caption).foregroundColor(.secondary).textSelection(.enabled)
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
        .frame(width: 520, height: 440)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            signInRefreshTick.toggle()
        }
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
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(selectedProvider.displayName) isn't connected yet.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                    openSettingsButton
                }
            }

            TextField(selectedProvider.linkPlaceholder, text: $linkText)
                .textFieldStyle(.roundedBorder)
                .disabled(!isProviderConfigured(selectedProvider))

            TextField("Sheet/Worksheet name (optional — defaults to the first)", text: $sheetNameText)
                .textFieldStyle(.roundedBorder)
                .disabled(!isProviderConfigured(selectedProvider))

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

            if !resolvedSheetName.isEmpty {
                Label("Last synced sheet: \(resolvedSheetName)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }

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

    // Whether `kind` is actually ready to sync: a real, verified sign-in on file — not merely a
    // non-empty Client ID field. Client ID alone proves nothing (it could be wrong, or never
    // actually used to sign in yet), so the "Open Settings to Connect…" button below must stay
    // visible, and the link fields disabled, until OAuthPKCESession confirms a genuine sign-in
    // (a Keychain-stored refresh token from a completed OAuth exchange — see Test Sign-In in
    // Settings, which is the normal way to establish this before ever pasting a sheet link here).
    private func isProviderConfigured(_ kind: SheetSyncProviderKind) -> Bool {
        OAuthPKCESession.shared(for: kind).isSignedIn
    }

    // SettingsLink is the public, documented way to open the Settings scene, but it only exists
    // from macOS 14 — Resolver's deployment target is 13.5, so pre-14 falls back to the private
    // `showSettingsWindow:` selector (the only way to do this at all before SettingsLink existed;
    // it works, but macOS logs a "Please use SettingsLink" warning for it on newer systems, which
    // is exactly why the macOS 14+ branch avoids it).
    @ViewBuilder
    private var openSettingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Text("Open Settings to Connect…")
            }
            .liquidGlassButton(prominent: false)
            .controlSize(.small)
        } else {
            Button("Open Settings to Connect…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .liquidGlassButton(prominent: false)
            .controlSize(.small)
        }
    }

    private func unlink() {
        projectManager.updateSheetSyncLink(projectId: project.id, provider: nil, link: nil, sheetName: nil)
        statusMessage = ""
        resolvedSheetName = ""
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
                _ = try await SheetSyncScriptRunner.validToken(for: selectedProvider)
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
                let token = try await SheetSyncScriptRunner.validToken(for: kind)
                let result = try await SheetSyncScriptRunner.run(
                    action: "fetch", provider: kind, token: token, link: link,
                    sheetName: project.sheetSyncSheetName
                )
                resolvedSheetName = result.sheetName

                let remoteClips = result.rows.map { ClipData(dict: $0) }
                let items = MergeManager.smartCompare(master: projectManager.currentMasterList, imported: remoteClips)
                let matchedMasterIds = Set(items.compactMap { $0.masterClip?.id })
                let localOnly = projectManager.currentMasterList.filter { !matchedMasterIds.contains($0.id) }

                reviewMergeItems = items
                reviewPushCandidates = localOnly.map { PushCandidate(clip: $0) }
                isBusy = false
                statusMessage = ""
                ConsoleLogger.shared.log("✅ Sheet Sync: fetched \(result.rows.count) row(s) from '\(result.sheetName)', \(items.filter { $0.state == .new }.count) new, \(items.filter { $0.state == .modified }.count) modified, \(localOnly.count) local-only")
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
                let token = try await SheetSyncScriptRunner.validToken(for: kind)
                let sheetName = resolvedSheetName.isEmpty ? project.sheetSyncSheetName : resolvedSheetName
                _ = try await SheetSyncScriptRunner.run(action: "write", provider: kind, token: token, link: link, sheetName: sheetName, rows: rowsToPush)
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
}
