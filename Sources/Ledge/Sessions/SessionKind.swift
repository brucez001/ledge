import Foundation

/// Identifies a `WebSession` owned by the `SessionManager`.
enum SessionKind: Hashable {
    /// A session tracking a saved site, keyed by the favourite's id.
    case favourite(UUID)
    /// A transient tab, not tied to any saved site. There can be several;
    /// they appear in the rail after the saved sites and are not restored on
    /// the next launch.
    case tab(UUID)

    var tabID: UUID? {
        guard case .tab(let id) = self else { return nil }
        return id
    }
}

/// Which tab to select after closing one.
enum TabSelection {
    /// Mirrors a browser: the tab that slides into the closed one's place,
    /// or the one before it when the last tab is closed. `nil` means nothing
    /// is left, and the caller should fall back to the start page.
    static func successor(after id: UUID, in tabs: [UUID]) -> UUID? {
        guard let index = tabs.firstIndex(of: id) else { return nil }
        var remaining = tabs
        remaining.remove(at: index)
        guard !remaining.isEmpty else { return nil }
        return remaining[min(index, remaining.count - 1)]
    }
}
