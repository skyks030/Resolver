import Foundation


// === Benutzer-Modell ===
struct User {
    let name: String
    let url: URL
}

// === Globale Verwaltung (Singleton) ===
class UserManager {
    static let shared = UserManager()

    // Vordefinierte Benutzer
    let users: [User] = [
        User(name: "Simon", url: URL(string: "https://user1.example.com")!),
        User(name: "Sky", url: URL(string: "https://user2.example.com")!)
    ]

    // Aktiver Benutzer
    private(set) var activeUser: User?

    // Setze aktiven Benutzer (z. B. aus Dropdown)
    func setActiveUser(named name: String) {
        if let user = users.first(where: { $0.name == name }) {
            activeUser = user
        }
    }

    // Zugriffshilfen
    var activeUserName: String? {
        activeUser?.name
    }

    var activeUserURL: URL? {
        activeUser?.url
    }
}
