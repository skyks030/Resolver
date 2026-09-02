import SwiftUI

/// Standalone tool window (Tools ▸ Color Group Manager) — lists every Color Group in the
/// currently open DaVinci Resolve project and lets you delete one. Scans automatically as soon as
/// it opens, with a Rescan button for picking up changes made in Resolve since.
struct ColorGroupManagerView: View {
    @State private var groups: [ColorGroupInfo] = []
    @State private var isScanning = false
    @State private var statusMessage = "Ready to scan."
    @State private var deletingName: String? = nil
    @State private var pendingDeleteName: String? = nil

    @State private var showErrorAlert = false
    @State private var alertMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "paintpalette.fill")
                    .foregroundColor(.accentColor)
                Text("Color Group Manager")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await scan() }
                } label: {
                    Label(isScanning ? "Scanning…" : "Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(isScanning)
            }
            .padding()
            .liquidGlassBar()

            Divider()

            if isScanning && groups.isEmpty {
                Spacer()
                ProgressView("Scanning project for Color Groups...")
                Spacer()
            } else if groups.isEmpty {
                Spacer()
                Text(statusMessage)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(groups) { group in
                    HStack {
                        Image(systemName: "paintpalette.fill")
                            .foregroundColor(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name).font(.headline)
                            Text("\(group.clipCount) clip\(group.clipCount == 1 ? "" : "s") in the current timeline")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            pendingDeleteName = group.name
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .controlSize(.small)
                        .disabled(deletingName != nil)
                    }
                    .padding(.vertical, 4)
                    .opacity(deletingName == group.name ? 0.5 : 1)
                }
            }

            Divider()

            HStack {
                Text("\(groups.count) color group\(groups.count == 1 ? "" : "s") found.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .liquidGlassBar()
        }
        .frame(minWidth: 420, minHeight: 340)
        // Scan the moment this window opens — matching every other tool window opening, the user
        // shouldn't have to press Rescan just to see what's already there.
        .task { await scan() }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert("Delete Color Group?", isPresented: Binding(
            get: { pendingDeleteName != nil },
            set: { if !$0 { pendingDeleteName = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDeleteName = nil }
            Button("Delete", role: .destructive) {
                if let name = pendingDeleteName {
                    pendingDeleteName = nil
                    Task { await delete(name) }
                }
            }
        } message: {
            Text("This deletes the color group \"\(pendingDeleteName ?? "")\" in DaVinci Resolve. Clips in it are set to ungrouped — their individual grades aren't affected. This can't be undone from Resolver.")
        }
    }

    // MARK: - Actions

    private func scan() async {
        isScanning = true
        statusMessage = "Scanning..."
        do {
            let result = try await ColorGroupManagerRunner.list()
            groups = result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            statusMessage = groups.isEmpty ? "No Color Groups found in the current project." : "Scan complete."
        } catch {
            statusMessage = "Scan failed."
            alertMessage = error.localizedDescription
            showErrorAlert = true
        }
        isScanning = false
    }

    private func delete(_ name: String) async {
        deletingName = name
        do {
            try await ColorGroupManagerRunner.delete(groupName: name)
            groups.removeAll { $0.name == name }
            statusMessage = "Deleted \"\(name)\"."
        } catch {
            statusMessage = "Delete failed."
            alertMessage = error.localizedDescription
            showErrorAlert = true
        }
        deletingName = nil
    }
}
