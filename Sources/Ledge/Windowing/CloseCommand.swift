import Foundation

/// What "close" means for whatever the panel is currently showing.
///
/// Every rail row is an open session, so the rule is deliberately uniform:
/// closing removes that session and row. If it was opened from a Home
/// favourite, the shortcut remains untouched.
enum CloseAction: Equatable {
    case closeSession(SessionKind)
    case nothing
}

enum CloseCommand {
    /// Resolves both ⌘W and ⇧⌘W. Shift no longer changes the meaning.
    static func resolve(destination: LauncherDestination) -> CloseAction {
        switch destination {
        case .favourite(let id):
            .closeSession(.favourite(id))
        case .tab(let id):
            .closeSession(.tab(id))
        case .home:
            .nothing
        }
    }
}
