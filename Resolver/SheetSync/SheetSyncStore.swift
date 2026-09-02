import Foundation

// A sheet the user has pinned in Sheet Sync — provider + link + optional worksheet override,
// plus a display title resolved from the sheet itself once fetched at least once.
struct PinnedSheet: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var provider: String   // SheetSyncProviderKind.rawValue
    var link: String
    var sheetName: String? // nil = first sheet/worksheet
    var title: String      // resolved worksheet name — placeholder until the first fetch succeeds
}

// Program-wide store of pinned Sheet Sync links — deliberately NOT tied to any one `Project`
// (unlike the legacy `Project.sheetSyncProvider/Link/SheetName` fields it replaces), so the list
// of linked spreadsheets survives switching between Resolver projects. Same singleton +
// UserDefaults-backed shape as `SheetSyncCredentials` (provider config) — small, simple,
// structured data that's appropriate for UserDefaults rather than a dedicated file on disk.
class SheetSyncStore: ObservableObject {
    static let shared = SheetSyncStore()

    @Published var pinnedSheets: [PinnedSheet] {
        didSet { save() }
    }

    private static let defaultsKey = "sheetSync.pinnedSheets"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([PinnedSheet].self, from: data) {
            self.pinnedSheets = decoded
        } else {
            self.pinnedSheets = []
        }
    }

    func sheets(for provider: SheetSyncProviderKind) -> [PinnedSheet] {
        pinnedSheets.filter { $0.provider == provider.rawValue }
    }

    func add(_ sheet: PinnedSheet) {
        pinnedSheets.append(sheet)
    }

    func remove(id: UUID) {
        pinnedSheets.removeAll { $0.id == id }
    }

    func updateTitle(id: UUID, title: String) {
        guard let idx = pinnedSheets.firstIndex(where: { $0.id == id }), !title.isEmpty else { return }
        pinnedSheets[idx].title = title
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pinnedSheets) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
