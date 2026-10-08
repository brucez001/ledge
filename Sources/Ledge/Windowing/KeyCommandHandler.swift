import AppKit
import SwiftTerm
import WebKit

/// Every Ledge keyboard shortcut, dispatched from a single local
/// `NSEvent` key-down monitor.
///
/// The app runs as `.accessory` with no reliable application menu bar to
/// hang `.keyboardShortcut` off, so a local monitor is the only way to
/// guarantee these combinations fire regardless of which SwiftUI view
/// currently holds focus. It only ever looks at events destined for our own
/// `LauncherPanel`, so it can never intercept a keystroke meant for the
/// separate Settings window (or any other app).
///
/// Mapped shortcuts (kept in sync with `SettingsView`'s Shortcuts tab):
///   ⌘1 … ⌘9   Select the Nth open item in the rail, counting from the top
///   ⌘0        Reset zoom on a site or terminal, else go home
///   ⇧⌘H       Go home (always)
///   ⌘L        Focus the address field (browser) / search field (home)
///   ⌘R        Reload the current site (browser mode only)
///   ⌘F        Show/hide find-in-page (browser mode only; a no-op on home)
///   ⌘N        Open a new note as a tab in the panel
///   ⌥⌘T       Open a new terminal as a tab in the panel
///   ⇧⌘P       Swap the open note between preview and raw Markdown
///   ⇧⌘L       Turn live Markdown rendering in the note editor on or off
///   ⌘[ / ⌘←   Back (browser mode only)
///   ⌘] / ⌘→   Forward (browser mode only)
///   ⌘+ / ⌘=   Zoom in on a site or terminal
///   ⌘-        Zoom out on a site or terminal
///   ⌘D        Split the focused terminal pane right (terminal only)
///   ⇧⌘D       Split the focused terminal pane down (terminal only)
///   ⌘] / ⌘[   Next / previous terminal pane (forward / back on a site)
///   ⌥⌘arrow   Focus the terminal pane in that direction (terminal only)
///   ⇧⌘C       Copy the current URL (browser mode only)
///   ⇧⌘O       Open the current page in the default browser (browser mode only)
///   Esc       See the ladder in `handleEscape`: close the find bar if
///             open; else blur a focused text field (address/search box)
///             rather than navigating away from it; else, only when a
///             terminal or the web view itself is focused, pass through
///             untouched; else go home from browser mode; else hide the
///             panel from home.
///   ⌘T        Open a new, empty session
///   ⌘W        Close the current session, note tab, or terminal pane (the
///             terminal itself with its last pane). A session's Home
///             favourite stays; a note's file is never deleted; a pane
///             running a command asks first.
///
/// While a terminal is shown, the site-only shortcuts from ⌘R down, and every
/// key not listed here, reach it untouched, except that keypad keys type their
/// characters (see `TerminalKeypad`); ⌘F and ⌘L do nothing there.
@MainActor
final class KeyCommandHandler {
    private let controller: PanelController
    // `Any?` is an opaque, thread-safely-removable monitor token;
    // `nonisolated(unsafe)` lets `deinit` (which cannot itself be
    // MainActor-isolated) remove it during teardown.
    nonisolated(unsafe) private var monitor: Any?

    init(controller: PanelController) {
        self.controller = controller
    }

    func install() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // `handle` returns nil to swallow the key, so the missing-handler
            // fallback must not use `??`, which would replace that nil.
            guard let self else { return event }
            return self.handle(event)
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window = event.window else { return event }

        // Local monitors see every keyDown in the app, including ones aimed
        // at the separate Settings window -- only our own floating panel's
        // shortcuts belong here.
        guard window is LauncherPanel, controller.isPanelVisible else { return event }

        if let terminal = window.firstResponder as? LedgeTerminalView, terminal.typeKeypadKey(event) {
            return nil
        }

        if event.keyCode == 53 {
            return handleEscape(event)
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // Every rail row is a session, note, or terminal tab, so ⌘W and ⇧⌘W
        // close it by the same rule. The event is swallowed on Home too,
        // preventing AppKit from closing the panel or app.
        if flags.contains(.command), chars == "w" {
            controller.performClose(controller.closeAction())
            return nil
        }

        if flags.contains(.command), flags.contains(.option), chars == "t" {
            controller.openNewTerminal()
            return nil
        }

        if flags.contains(.command), chars == "n" {
            controller.openNewNote()
            return nil
        }

        guard flags.contains(.command) else { return event }
        let shift = flags.contains(.shift)

        // Note-only, and checked before the browser shortcuts below so the
        // combination stays free for a site otherwise.
        if shift, chars == "p", controller.isShowingNote {
            controller.toggleNotePreview()
            return nil
        }

        if shift, chars == "l", controller.isShowingNote {
            controller.toggleNoteMarkdownRendering()
            return nil
        }

        let isBrowserMode = controller.showsBrowserContent

        if !shift, let digit = Int(chars), (1...9).contains(digit) {
            controller.selectRailEntry(numbered: digit)
            return nil
        }

        if !shift, chars == "0" {
            if isBrowserMode {
                controller.sessionManager.activeSession()?.resetZoom()
            } else if controller.isShowingTerminal {
                controller.zoomTerminals(.reset)
            } else if controller.showsStartPage {
                controller.goHome()
            } else {
                return nil
            }
            return nil
        }

        // Terminal-only keys, checked before the browser-only cut-off below.
        if controller.isShowingTerminal {
            if chars == "+" || chars == "=" {
                controller.zoomTerminals(.in)
                return nil
            }
            if chars == "-" {
                controller.zoomTerminals(.out)
                return nil
            }
            if chars == "d", !flags.contains(.option) {
                controller.splitTerminal(shift ? .stacked : .sideBySide)
                return nil
            }
            if !shift, chars == "]" || chars == "[" {
                controller.focusTerminalPane(offset: chars == "]" ? 1 : -1)
                return nil
            }
            if flags.contains(.option), let direction = Self.paneDirection(forKeyCode: event.keyCode) {
                controller.focusTerminalPane(toward: direction)
                return nil
            }
        }

        if shift, chars == "h" {
            controller.goHome()
            return nil
        }

        if !shift, chars == "l" {
            guard !controller.isShowingNote else { return nil }
            controller.focusAddressField()
            return nil
        }

        if !shift, chars == "f" {
            guard isBrowserMode else { return nil }
            controller.toggleFindBar()
            return nil
        }

        if !shift, chars == "t" {
            controller.newTab()
            return nil
        }

        // Everything past this point only makes sense while a site is
        // actually showing, so pass the event through unswallowed on home.
        guard isBrowserMode else { return event }

        if !shift, chars == "r" {
            controller.reloadActiveSession()
            return nil
        }

        if event.keyCode == 123 || chars == "[" {
            controller.sessionManager.activeSession()?.goBack()
            return nil
        }
        if event.keyCode == 124 || chars == "]" {
            controller.sessionManager.activeSession()?.goForward()
            return nil
        }

        if chars == "+" || chars == "=" {
            controller.sessionManager.activeSession()?.zoomIn()
            return nil
        }
        if chars == "-" {
            controller.sessionManager.activeSession()?.zoomOut()
            return nil
        }

        if shift, chars == "c" {
            controller.sessionManager.activeSession()?.copyCurrentURL()
            return nil
        }
        if shift, chars == "o" {
            controller.sessionManager.activeSession()?.openInDefaultBrowser()
            return nil
        }

        return event
    }

    private static func paneDirection(forKeyCode keyCode: UInt16) -> TerminalPaneDirection? {
        switch keyCode {
        case 123: .left
        case 124: .right
        case 125: .down
        case 126: .up
        default: nil
        }
    }

    /// The Escape ladder, checked in order:
    ///   1. Find bar open -> close it (our own SwiftUI chrome; always safe).
    ///   2. An active text editor has focus (the shared field editor, or an
    ///      `NSTextField`/`NSSearchField` subtree -- e.g. the browser
    ///      address field or the home search box) -> blur it and swallow
    ///      the key. This has to be checked *before* rule 5 below, or Esc
    ///      while editing the address field would navigate home before the
    ///      field's own `cancelOperation` (revert pending edits) ever runs;
    ///      and on the home screen it must leave the field rather than
    ///      dismissing the whole panel.
    ///   3. A note -> swallow. A terminal -> pass through while it has
    ///      focus, else swallow; the pane never navigates away on Esc.
    ///   4. Browser mode and a live `WKWebView` has focus -> pass the event
    ///      through untouched. Pages legitimately need Esc themselves
    ///      (leaving JS fullscreen video, dismissing an in-page modal), so
    ///      this app must never swallow it there.
    ///   5. Browser mode, anything else focused -> go home.
    ///   6. Home -> hide the panel. (It used to collapse the panel to a bare
    ///      rail; that mode is gone, and sliding out of the way is what the
    ///      user actually wants from Esc on the home screen.)
    private func handleEscape(_ event: NSEvent) -> NSEvent? {
        if controller.isShowingFindBar {
            controller.closeFindBar()
            return nil
        }

        if firstResponderIsActiveTextEditor() {
            NSApp.keyWindow?.makeFirstResponder(nil)
            return nil
        }

        // A note has no Escape-level navigation. Swallow the key so AppKit's
        // default text-view cancellation cannot dismiss the active pane.
        if controller.isShowingNote {
            return nil
        }

        // Programs in a terminal need Esc (vim, less, a shell's own line
        // editing), so it is theirs whenever the terminal has focus.
        if controller.isShowingTerminal {
            return firstResponderIsInside(TerminalView.self) ? event : nil
        }

        if controller.showsBrowserContent {
            guard !firstResponderIsInside(WKWebView.self) else { return event }
            controller.goHome()
            return nil
        }

        controller.hide()
        return nil
    }

    private func firstResponderIsInside(_ type: NSView.Type) -> Bool {
        guard let responderView = NSApp.keyWindow?.firstResponder as? NSView else { return false }
        var view: NSView? = responderView
        while let current = view {
            if current.isKind(of: type) { return true }
            view = current.superview
        }
        return false
    }

    /// True when the first responder is actively editing text: either the
    /// window's shared field editor (the common case -- an `NSTextView`
    /// with `isFieldEditor == true`, installed while any `NSTextField` or
    /// `NSSearchField` is being edited), or, as a fallback, a first
    /// responder that is itself an `NSTextField`/`NSSearchField` or nested
    /// inside one.
    private func firstResponderIsActiveTextEditor() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if let textView = responder as? NSTextView, textView.isFieldEditor {
            return true
        }
        guard let responderView = responder as? NSView else { return false }
        var view: NSView? = responderView
        while let current = view {
            // `NSSearchField` is an `NSTextField` subclass, so this covers both.
            if current is NSTextField { return true }
            view = current.superview
        }
        return false
    }
}
