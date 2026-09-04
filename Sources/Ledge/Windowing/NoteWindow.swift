import AppKit

/// The window a note is edited in.
///
/// Deliberately *not* a web surface: there is no `WKWebView` anywhere in
/// here. `KeyCommandHandler` distinguishes note windows from the main panel
/// by type so ⌘W can mean "close this note" without ever touching a session.
final class NoteWindow: NSPanel {
    /// The SwiftUI text editor inside must be able to become the key window
    /// before it can receive keystrokes; `NSPanel` defaults this to `false`.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        // A hotkey-summoned note must appear on the Space the user is
        // actually on, not the one it was last used on.
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        // Off: with a text editor filling the window, background dragging
        // would compete with text selection. The title bar still moves it.
        isMovableByWindowBackground = false
        minSize = NSSize(width: 300, height: 220)
    }
}
