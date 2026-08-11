import AppKit
import Carbon

/// The system-wide shortcuts Ledge registers with Carbon.
///
/// Kept as data rather than being spelled out at each site that needs them so
/// the registration, the menu-bar item's key equivalent, the Settings list and
/// the README all describe the same combinations -- and so the set can be
/// checked for collisions in tests without touching the global hotkey registry.
enum GlobalShortcut: UInt32, CaseIterable {
    /// Show or hide the panel.
    case togglePanel = 1
    /// Turn edge-hover reveal on or off without opening a menu -- the panel
    /// is usually hidden when this is needed (just before sharing a screen),
    /// so it has to work from wherever the pointer happens to be.
    case toggleEdgeReveal = 2

    /// Carbon virtual key code, as passed to `RegisterEventHotKey`.
    var keyCode: UInt32 {
        switch self {
        case .togglePanel: UInt32(kVK_Space)
        case .toggleEdgeReveal: UInt32(kVK_ANSI_E)
        }
    }

    /// Carbon modifier mask, as passed to `RegisterEventHotKey`.
    ///
    /// `⌥` is part of the edge-reveal combination deliberately: ⇧⌘E is
    /// already spoken for in enough apps that claiming it globally would take
    /// it away from whatever the user is actually working in.
    var carbonModifiers: UInt32 {
        switch self {
        case .togglePanel: UInt32(cmdKey | shiftKey)
        case .toggleEdgeReveal: UInt32(cmdKey | shiftKey | optionKey)
        }
    }

    /// The `NSMenuItem` key equivalent for the same combination, so the
    /// menu-bar item advertises the shortcut instead of hiding it.
    var keyEquivalent: String {
        switch self {
        case .togglePanel: " "
        case .toggleEdgeReveal: "e"
        }
    }

    /// The AppKit spelling of `carbonModifiers`, derived from it so the two
    /// cannot drift apart.
    var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    /// How the combination is written in user-facing prose.
    var displayName: String {
        switch self {
        case .togglePanel: "⇧⌘Space"
        case .toggleEdgeReveal: "⌥⇧⌘E"
        }
    }
}
