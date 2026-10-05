import Foundation

/// What "close" means for whatever the panel is currently showing.
///
/// Every rail row is an open session, note tab, or terminal tab, so the rule
/// is deliberately uniform: closing removes the row. A session's Home
/// shortcut is never touched and a note's file is never deleted -- closing
/// only ends the editor, exactly like a browser closing a tab. Closing a
/// terminal ends its shell, so it is confirmed first while a command runs.
enum CloseAction: Equatable {
    case closeSession(SessionKind)
    case closeNote(UUID)
    case closeTerminal(UUID)
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
        case .note(let id):
            .closeNote(id)
        case .terminal(let id):
            .closeTerminal(id)
        case .home:
            .nothing
        }
    }
}
