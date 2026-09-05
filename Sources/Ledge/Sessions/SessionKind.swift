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
