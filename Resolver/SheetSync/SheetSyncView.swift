import SwiftUI

// Sheet Sync's tabs (Microsoft Excel / Google Sheets) are always both visible, independent of
// what's linked — each tab lists every sheet pinned under that provider as its own "Compare Now /
// Unlink" widget, with an always-available way to pin another. The list of pinned sheets lives in
// `SheetSyncStore` (program-wide, UserDefaults-backed) rather than on `Project`, so it survives
// switching between Resolver projects — only the master list being compared against is
// project-specific, not which sheets are linked.
struct SheetSyncView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var projectManager: ProjectManager
    @ObservedObject private var store = SheetSyncStore.shared
    let project: Project

    @State private var selectedProvider: SheetSyncProviderKind = .microsoft
    @State private var showAddSheet = false
    @State private var linkText: String = ""
    @State private var sheetNameText: String = ""
    @State private var isBusy = false
    @State private var statusMessage: String = ""
    @State private var showError = false
    @State private var errorMessage = ""

    @State private var showReview = false
    @State private var reviewMergeItems: [MergeItem] = []
    @State private var reviewPushCandidates: [PushCandidate] = []
    // Which pinned sheet Compare Now was last pressed for — drives both the review sheet's
    // labeling and, on Apply, which sheet gets written back to.
    @State private var activeSheetId: UUID? = nil
    // Bumped whenever this window regains focus (e.g. after the user sets up sign-in in the
    // separate Settings window and switches back here) so `isProviderConfigured` — a live Keychain
    // check, not a cached flag — gets re-evaluated instead of showing a stale "not connected" state.
    @State private var signInRefreshTick = false

    private var activeSheet: PinnedSheet? {
        activeSheetId.flatMap { id in store.pinnedSheets.first { $0.id == id } }
    }

    private func kind(of sheet: PinnedSheet) -> SheetSyncProviderKind {
        SheetSyncProviderKind(rawValue: sheet.provider) ?? selectedProvider
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Sheet Sync")
                    .font(.title2)
                    .bold()
                Spacer()
            }

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
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(store.sheets(for: selectedProvider)) { sheet in
                        pinnedSheetWidget(sheet)
                    }
                    addSheetSection
                }
            }

            if !statusMessage.isEmpty {
                HStack {
                    if isBusy { ProgressView().controlSize(.small) }
                    Text(statusMessage).font(.caption).foregroundColor(.secondary).textSelection(.enabled)
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 480)
        .onAppear { migrateLegacyLinkIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            signInRefreshTick.toggle()
        }
        .alert("Sheet Sync Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: { Text(errorMessage) }
        .sheet(isPresented: $showReview) {
            SyncReviewView(
                mergeItems: $reviewMergeItems,
                allMasterClips: projectManager.currentMasterList,
                sourceLabel: activeSheet.map { "\(kind(of: $0).displayName) — \($0.title.isEmpty ? "Untitled Sheet" : $0.title)" } ?? selectedProvider.displayName,
                supportsPush: true,
                pushCandidates: $reviewPushCandidates,
                onApply: {
                    showReview = false
                    applySync()
                },
                onCancel: { showReview = false }
            )
        }
    }

    // MARK: - Pinned sheet widgets

    private func pinnedSheetWidget(_ sheet: PinnedSheet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sheet.title.isEmpty ? "Untitled Sheet" : sheet.title)
                    .font(.headline)
                Text(sheet.link)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack {
                Button {
                    activeSheetId = sheet.id
                    compareNow(sheet)
                } label: {
                    Label("Compare Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .liquidGlassButton(prominent: true)
                .disabled(isBusy)

                Button("Unlink", role: .destructive) { store.remove(id: sheet.id) }
                    .disabled(isBusy)
            }
        }
        .padding()
        .liquidGlassPanel(cornerRadius: 8)
    }

    private var addSheetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showAddSheet.toggle()
            } label: {
                Label(showAddSheet ? "Cancel" : "Add Another Sheet", systemImage: showAddSheet ? "xmark.circle" : "plus.circle")
            }
            .buttonStyle(.plain)
            .disabled(!isProviderConfigured(selectedProvider))

            if showAddSheet {
                TextField(selectedProvider.linkPlaceholder, text: $linkText)
                    .textFieldStyle(.roundedBorder)

                TextField("Sheet/Worksheet name (optional — defaults to the first)", text: $sheetNameText)
                    .textFieldStyle(.roundedBorder)

                Button(action: linkAndPin) {
                    Text(isBusy ? "Linking…" : "Link & Pin")
                }
                .liquidGlassButton(prominent: true)
                .disabled(isBusy || linkText.trimmingCharacters(in: .whitespaces).isEmpty)
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

    // One-time migration from the old per-project single-sheet link (`Project.sheetSyncProvider/
    // Link/SheetName`) into the new global store — only fires while the store is still empty, so
    // opening a second project that also happens to carry a legacy link just pins a second sheet
    // rather than re-migrating. The legacy fields are cleared off the project once migrated so
    // this can't run again for it.
    private func migrateLegacyLinkIfNeeded() {
        guard store.pinnedSheets.isEmpty,
              let providerRaw = project.sheetSyncProvider,
              let link = project.sheetSyncLink else { return }
        let pinned = PinnedSheet(provider: providerRaw, link: link, sheetName: project.sheetSyncSheetName, title: project.sheetSyncSheetName ?? "")
        store.add(pinned)
        projectManager.updateSheetSyncLink(projectId: project.id, provider: nil, link: nil, sheetName: nil)
        if let migratedKind = SheetSyncProviderKind(rawValue: providerRaw) { selectedProvider = migratedKind }
    }

    private func linkAndPin() {
        let link = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else { return }
        let sheetName = sheetNameText.trimmingCharacters(in: .whitespaces)
        let provider = selectedProvider
        isBusy = true
        statusMessage = "Signing in to \(provider.displayName)…"
        ConsoleLogger.shared.log("▶️ Sheet Sync: linking \(provider.rawValue) — \(link)")

        Task {
            do {
                let token = try await SheetSyncScriptRunner.validToken(for: provider)
                statusMessage = "Resolving sheet…"
                let result = try await SheetSyncScriptRunner.run(
                    action: "fetch", provider: provider, token: token, link: link,
                    sheetName: sheetName.isEmpty ? nil : sheetName
                )
                store.add(PinnedSheet(provider: provider.rawValue, link: link, sheetName: sheetName.isEmpty ? nil : sheetName, title: result.sheetName))
                linkText = ""
                sheetNameText = ""
                showAddSheet = false
                isBusy = false
                statusMessage = "Pinned \(result.sheetName.isEmpty ? "sheet" : result.sheetName)."
                ConsoleLogger.shared.log("✅ Sheet Sync: pinned \(provider.rawValue) — \(result.sheetName)")
            } catch {
                isBusy = false
                ConsoleLogger.shared.log("❌ Sheet Sync sign-in failed: \(error)")
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Compare

    private func compareNow(_ sheet: PinnedSheet) {
        guard let providerKind = SheetSyncProviderKind(rawValue: sheet.provider) else { return }
        isBusy = true
        statusMessage = "Connecting to \(providerKind.displayName)…"
        ConsoleLogger.shared.log("▶️ Sheet Sync: comparing against \(providerKind.rawValue) — \(sheet.link)")

        Task {
            do {
                let token = try await SheetSyncScriptRunner.validToken(for: providerKind)
                let result = try await SheetSyncScriptRunner.run(
                    action: "fetch", provider: providerKind, token: token, link: sheet.link,
                    sheetName: sheet.sheetName
                )
                store.updateTitle(id: sheet.id, title: result.sheetName)

                let remoteClips = result.rows.map { ClipData(dict: $0) }
                let master = projectManager.currentMasterList
                let items = MergeManager.compareColumnAware(master: master, imported: remoteClips)
                let localOnly = MergeManager.unclaimedMasterClips(master: master, mergeItems: items)

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
        guard let sheet = activeSheet, let providerKind = SheetSyncProviderKind(rawValue: sheet.provider) else { return }

        // Pull: apply every resolved field decision into the master list — MergeManager.applyMerge
        // takes the incoming value for any field the review resolved that way, and keeps the local
        // value otherwise.
        let oldList = projectManager.currentMasterList
        var newMaster = projectManager.currentMasterList
        MergeManager.applyMerge(master: &newMaster, mergeItems: reviewMergeItems)
        if newMaster != oldList {
            projectManager.updateMasterList(with: newMaster)
            projectManager.registerUndo(\.currentMasterList, actionName: "Sheet Sync", from: oldList) {
                self.projectManager.saveMasterList()
            }
        }

        // Push: local-only rows kept selected, plus any resolved conflict where at least one
        // field kept the local value — that field needs writing back out to the sheet so it
        // converges to the same merged row Resolver now has (per-field, not whole-row-only).
        var rowsToPush: [[String: String]] = []
        for candidate in reviewPushCandidates where candidate.selected {
            rowsToPush.append(sheetRow(for: candidate.clip))
        }
        for item in reviewMergeItems where item.state == .modified {
            guard item.fieldWinners.values.contains(.master), let masterClip = item.masterClip,
                  let merged = newMaster.first(where: { $0.id == masterClip.id }) else { continue }
            rowsToPush.append(sheetRow(for: merged))
        }

        guard !rowsToPush.isEmpty else { return }
        isBusy = true
        statusMessage = "Writing \(rowsToPush.count) row(s) to \(providerKind.displayName)…"
        ConsoleLogger.shared.log("▶️ Sheet Sync: pushing \(rowsToPush.count) row(s) to \(providerKind.rawValue)")

        Task {
            do {
                let token = try await SheetSyncScriptRunner.validToken(for: providerKind)
                let sheetName = sheet.title.isEmpty ? sheet.sheetName : sheet.title
                // Only matters the first time a brand-new/empty sheet gets written to — see
                // sheet_sync.py's build_header — but always safe to pass.
                let columnOrder = MergeManager.orderedColumns(for: projectManager.currentMasterList)
                _ = try await SheetSyncScriptRunner.run(action: "write", provider: providerKind, token: token, link: sheet.link, sheetName: sheetName, rows: rowsToPush, columnOrder: columnOrder)
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
        clip.dict
    }
}
