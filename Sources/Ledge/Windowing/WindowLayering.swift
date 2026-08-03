import AppKit

/// Where each of Ledge's windows sits in the window-server stacking order.
///
/// The panel is deliberately a `.floating` window so a slide-over reveal is
/// drawn over whatever the user is working in. That single decision is also
/// why the Settings window needs a level of its own: a normal-level window
/// opened by an app whose only other window floats is stacked *underneath*
/// the panel, so choosing "Settings…" looked like nothing happened at all.
enum WindowLayering {
    /// The slide-over panel's level.
    static let panel: NSWindow.Level = .floating

    /// The Settings window's level: one step above the panel, for as long as
    /// the window exists.
    ///
    /// Deliberately unconditional. Tying this to whether Ledge is frontmost
    /// looks tidier -- a settings window has no business floating over another
    /// app -- but it reintroduces the original bug in ordinary use: with
    /// auto-hide switched off the panel is permanently visible, so the moment
    /// Ledge stops being frontmost the Settings window drops behind it again
    /// and is once more impossible to find. Being able to see the window you
    /// just opened wins.
    static let settings = NSWindow.Level(rawValue: panel.rawValue + 1)
}
