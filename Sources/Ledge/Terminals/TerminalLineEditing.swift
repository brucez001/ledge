import AppKit

/// What the Mac's text-editing shortcuts type at a command line: Option moves
/// or deletes by word, Command to the start or end of the line.
///
/// SwiftTerm leaves most of these keys to AppKit's text-editing commands,
/// which it does not implement. They become the bytes that zsh, bash, fish,
/// and most REPLs bind to the same edits. Command-Delete is Control-U, which
/// zsh reads as deleting the whole line rather than only the text before the
/// cursor.
enum TerminalLineEditing {
    private static let left: UInt16 = 123
    private static let right: UInt16 = 124
    private static let delete: UInt16 = 51
    private static let forwardDelete: UInt16 = 117

    private static let escape: UInt8 = 0x1B

    /// `nil` leaves the key to SwiftTerm: other keys and modifier
    /// combinations, full-screen programs on the alternate screen, which read
    /// these bytes as their own commands (Control-A increments a number in
    /// Vim), and programs using the kitty keyboard protocol, which asked for
    /// key reports instead.
    static func bytes(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        kittyKeyboard: Bool,
        alternateScreen: Bool
    ) -> [UInt8]? {
        guard !kittyKeyboard, !alternateScreen else { return nil }
        switch modifiers.intersection([.command, .option, .control, .shift]) {
        case .option:
            switch keyCode {
            case left: return [escape, UInt8(ascii: "b")]
            case right: return [escape, UInt8(ascii: "f")]
            case delete: return [escape, 0x7F]
            case forwardDelete: return [escape, UInt8(ascii: "d")]
            default: return nil
            }
        case .command:
            switch keyCode {
            case left: return [0x01]
            case right: return [0x05]
            case delete: return [0x15]
            case forwardDelete: return [0x0B]
            default: return nil
            }
        default:
            return nil
        }
    }
}
