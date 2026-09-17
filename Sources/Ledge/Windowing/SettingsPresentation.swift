import AppKit

/// The one route to the Settings window, and the guard against the one nobody
/// asked for.
///
/// SwiftUI presents an app's `Settings` scene during launch when it is the
/// only scene that app declares -- which it is here, because the panel, the
/// rail and the menu bar are all AppKit, leaving `Settings` as the whole
/// SwiftUI scene graph. An accessory app has to come up panel-only, so a
/// Settings window that arrives without a matching request is closed again.
@MainActor
enum SettingsPresentation {
    private static var pendingRequest = false

    /// Records that the presentation about to happen was asked for. Consumed
    /// by `shouldDismissPresentation()`.
    static func willOpenAtUserRequest() {
        pendingRequest = true
    }

    /// Opens Settings at the user's request.
    ///
    /// Returns false when no Settings command could be found, so a caller can
    /// fall back to something visible rather than appearing to do nothing.
    @discardableResult
    static func open() -> Bool {
        willOpenAtUserRequest()
        NSApp.activate(ignoringOtherApps: true)

        // SwiftUI's own Settings command, reached through the application
        // menu. Unlike the private showSettingsWindow: selector, this does not
        // report success and then silently discard the request.
        if let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu,
           let settingsIndex = appMenu.items.firstIndex(where: {
               $0.keyEquivalent == ","
                   && $0.keyEquivalentModifierMask.contains(.command)
           }) {
            appMenu.performActionForItem(at: settingsIndex)
            return true
        }

        // Compatibility fallback if SwiftUI ever stops assigning ⌘, to its
        // Settings command.
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) { return true }
        if NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) { return true }

        // Nothing opened, so this permit must not outlive the attempt and wave
        // through the next unrequested presentation.
        pendingRequest = false
        return false
    }

    /// Whether the Settings window now being presented should be closed again.
    /// Consumes any pending request: one request admits one presentation.
    static func shouldDismissPresentation() -> Bool {
        guard pendingRequest else { return true }
        pendingRequest = false
        return false
    }
}
