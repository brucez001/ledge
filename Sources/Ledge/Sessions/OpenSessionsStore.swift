import Foundation

/// What the rail looked like when Ledge last quit.
///
/// Sessions are restored as rows only: the page a row points at is fetched
/// when the user selects it, never at launch. Ledge starts at login, so
/// reopening the rail must not also mean fetching every site in it.
@MainActor
final class OpenSessionsStore {
    /// One rail row, as it survives a quit.
    struct OpenSession: Codable, Equatable {
        /// The Home shortcut that opened this session, if any. A session with
        /// no favourite is an ordinary tab.
        var favouriteID: UUID?
        var url: URL
        var title: String
        var iconHost: String?
    }

    private let sessionsKey = "ledge.openSessions"
    private let noteTabsKey = "ledge.openNoteTabs"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Sessions

    func loadSessions() -> [OpenSession] {
        guard let data = defaults.data(forKey: sessionsKey) else { return [] }
        return (try? JSONDecoder().decode([OpenSession].self, from: data)) ?? []
    }

    func saveSessions(_ sessions: [OpenSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: sessionsKey)
    }

    // MARK: - Note tabs

    func loadNoteTabs() -> [UUID] {
        (defaults.array(forKey: noteTabsKey) as? [String] ?? []).compactMap(UUID.init(uuidString:))
    }

    func saveNoteTabs(_ ids: [UUID]) {
        defaults.set(ids.map(\.uuidString), forKey: noteTabsKey)
    }

    // MARK: - Reconciliation

    /// Drops rows that can no longer be opened, and demotes rows whose Home
    /// shortcut has been deleted since the last launch to ordinary tabs, so a
    /// restored row never points at a favourite that is not there.
    static func reconciled(
        _ sessions: [OpenSession],
        against favouriteIDs: Set<UUID>
    ) -> [OpenSession] {
        sessions.map { session in
            guard let favouriteID = session.favouriteID, !favouriteIDs.contains(favouriteID) else {
                return session
            }
            var demoted = session
            demoted.favouriteID = nil
            return demoted
        }
    }

    /// Keeps only note tabs whose file still exists. A note deleted between
    /// launches must not come back as an empty tab.
    static func reconciledNoteTabs(_ ids: [UUID], against existing: Set<UUID>) -> [UUID] {
        ids.filter(existing.contains)
    }
}
