import AppKit

/// What a numeric keypad key types in a terminal.
///
/// A Mac keypad has no Num Lock, so it behaves like xterm's with Num Lock on:
/// digits and operators type themselves even while a program has asked for
/// application keypad mode. zsh setups such as oh-my-zsh ask for that mode at
/// every prompt, and the escape sequences it produces are ones zsh ignores.
enum TerminalKeypad {
    private static let keyCodes: Set<UInt16> = [
        65, // decimal
        67, // multiply
        69, // plus
        75, // divide
        78, // minus
        81, // equals
        82, 83, 84, 85, 86, 87, 88, 89, 91, 92, // 0-9
    ]
    private static let enter: UInt16 = 76

    /// `nil` leaves the key to SwiftTerm: modified keys, keys that are not on
    /// the keypad (the arrow keys also carry `.numericPad`), and programs
    /// using the kitty keyboard protocol, which reports keypad keys itself.
    static func text(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String?,
        kittyKeyboard: Bool
    ) -> String? {
        guard !kittyKeyboard, modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        if keyCode == enter { return "\r" }
        guard keyCodes.contains(keyCode), let characters, !characters.isEmpty else { return nil }
        return characters
    }
}
