import AppKit
import Carbon
import SwiftUI

// MARK: - App entry point

@main
struct LedgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                controller: appDelegate.panelController,
                hotkeyRegistered: appDelegate.isHotkeyRegistered
            )
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Not `private` -- the Settings scene above needs it, and it must exist
    // before that scene's content closure ever reads it, which a plain
    // `let` guarantees.
    let panelController = PanelController()
    private var hotkeyManager: HotkeyManager?
    private var statusItemController: StatusItemController?
    private var keyCommandHandler: KeyCommandHandler?

    private let hasLaunchedBeforeKey = "ledge.hasLaunchedBefore"

    /// Surfaced to Settings so it can warn if ⇧⌘Space could not be
    /// registered (e.g. another app already owns the combination).
    var isHotkeyRegistered: Bool { hotkeyManager?.isRegistered ?? true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory posture: no Dock icon, no app-switcher entry. The panel
        // and the status-bar item are the only user-facing surfaces.
        NSApp.setActivationPolicy(.accessory)

        statusItemController = StatusItemController(panelController: panelController)
        statusItemController?.install()

        // Show the panel on the very first launch so the app is discoverable,
        // but on later launches (especially as a login item) come up armed and
        // hidden instead of flinging the panel open over whatever the user is
        // doing. If auto-hide is off the panel is meant to be persistent, so
        // it is always shown in that case.
        let defaults = UserDefaults.standard
        let isFirstLaunch = !defaults.bool(forKey: hasLaunchedBeforeKey)
        defaults.set(true, forKey: hasLaunchedBeforeKey)

        if isFirstLaunch || !panelController.isAutoHideEnabled {
            panelController.show()
        } else {
            panelController.prepareHidden()
        }

        hotkeyManager = HotkeyManager { [weak self] in
            Task { @MainActor in
                self?.panelController.toggleVisibility()
            }
        }
        hotkeyManager?.register()

        // Replaces the previous ad-hoc Esc-only local monitor: every
        // keyboard shortcut now lives in one place (see `KeyCommandHandler`).
        keyCommandHandler = KeyCommandHandler(controller: panelController)
        keyCommandHandler?.install()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController.show()
        return true
    }
}
