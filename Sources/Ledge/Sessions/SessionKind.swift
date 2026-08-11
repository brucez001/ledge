import Foundation

/// Identifies an open `WebSession` owned by the `SessionManager`.
///
/// A favourite id records which Home shortcut opened or adopted the session;
/// it does not give that rail row different behaviour. Tabs have only their
/// in-memory id. Neither kind is restored across app launches.
enum SessionKind: Hashable {
    case favourite(UUID)
    case tab(UUID)

    var tabID: UUID? {
        guard case .tab(let id) = self else { return nil }
        return id
    }

    var favouriteID: UUID? {
        guard case .favourite(let id) = self else { return nil }
        return id
    }
}

/// Which live session to select after closing one.
enum SessionSelection {
    /// Mirrors a browser: the row that slides into the closed one's place, or
    /// the row before it when the last one is closed.
    static func successor(after id: SessionKind, in sessions: [SessionKind]) -> SessionKind? {
        guard let index = sessions.firstIndex(of: id) else { return nil }
        var remaining = sessions
        remaining.remove(at: index)
        guard !remaining.isEmpty else { return nil }
        return remaining[min(index, remaining.count - 1)]
    }
}
