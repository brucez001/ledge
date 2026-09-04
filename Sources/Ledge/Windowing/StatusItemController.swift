import AppKit
import Combine

/// Owns the menu-bar (`NSStatusItem`) affordance required by the app's
/// `.accessory` activation policy -- once the panel itself is hidden, this
/// is the *only* persistent, discoverable entry point.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let panelController: PanelController
    private var statusItem: NSStatusItem?
    private var dockSideObservation: AnyCancellable?
    private var edgeRevealObservation: AnyCancellable?

    init(panelController: PanelController) {
        self.panelController = panelController
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        updateStatusItemImage(for: panelController.dockSide)

        // The panel can change sides from a menu command or by being dragged
        // across the display midpoint. Keep the menu-bar mark in step with
        // either path instead of waiting for the next menu open.
        dockSideObservation = panelController.$dockSide.sink { [weak self] dockSide in
            self?.updateStatusItemImage(for: dockSide)
        }

        // ⌥⇧⌘E can be pressed while the panel is hidden and no menu is open,
        // so the status item is the only place the change can be confirmed:
        // dim the mark whenever edge reveal is turned off.
        edgeRevealObservation = panelController.preferences.$edgeTriggerEnabled.sink { [weak self] enabled in
            self?.updateEdgeRevealIndicator(enabled: enabled)
        }

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    private func updateStatusItemImage(for dockSide: DockSide) {
        statusItem?.button?.image = LedgeMarkImage.make(dockSide: dockSide)
    }

    private func updateEdgeRevealIndicator(enabled: Bool) {
        guard let button = statusItem?.button else { return }
        let shortcut = GlobalShortcut.toggleEdgeReveal.displayName
        button.appearsDisabled = !enabled
        button.toolTip = enabled
            ? "Ledge — edge hover on (\(shortcut) to turn off)"
            : "Ledge — edge hover off (\(shortcut) to turn on)"
    }

    /// Rebuilt every time the menu is about to open (`NSMenuDelegate`), so
    /// the dock-side, auto-hide and edge-reveal checkmarks and the Sites list
    /// can never go stale between edits made elsewhere (Settings, the
    /// favourites sheet).
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(makeItem("Show/Hide Ledge", #selector(toggleVisibility), shortcut: .togglePanel))

        menu.addItem(.separator())

        let dockLeftItem = makeItem("Dock Left", #selector(dockLeft), key: "")
        dockLeftItem.state = panelController.dockSide == .left ? .on : .off
        menu.addItem(dockLeftItem)

        let dockRightItem = makeItem("Dock Right", #selector(dockRight), key: "")
        dockRightItem.state = panelController.dockSide == .right ? .on : .off
        menu.addItem(dockRightItem)

        menu.addItem(.separator())

        let keepOpenItem = makeItem("Keep Panel Open", #selector(toggleKeepOpen), key: "")
        keepOpenItem.state = panelController.isAutoHideEnabled ? .off : .on
        menu.addItem(keepOpenItem)

        // Mirrors the Settings toggle because this is the one setting people
        // need in a hurry -- before sharing a screen, an accidental edge
        // reveal shows whatever is loaded in the panel to everyone watching.
        let edgeRevealItem = makeItem("Reveal on Edge Hover", #selector(toggleEdgeReveal), shortcut: .toggleEdgeReveal)
        edgeRevealItem.state = panelController.preferences.edgeTriggerEnabled ? .on : .off
        menu.addItem(edgeRevealItem)

        // Surfaced here as well as in Settings: "I have to open the app every
        // time" is the first thing anyone hits, and the menu bar is where
        // they will look before they find a preferences window.
        if LoginItem.isSupported {
            let loginItem = makeItem("Launch at Login", #selector(toggleLaunchAtLogin), key: "")
            loginItem.state = LoginItem.isEnabled ? .on : .off
            menu.addItem(loginItem)
        }

        menu.addItem(.separator())
        menu.addItem(makeSitesItem())
        menu.addItem(makeNotesItem())
        menu.addItem(.separator())

        let settingsItem = makeItem("Settings…", #selector(openSettings), key: ",")
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(makeItem("Clear Caches", #selector(clearCaches), key: ""))
        menu.addItem(makeItem("Clear All Website Data…", #selector(clearAllWebsiteData), key: ""))

        let liveCount = panelController.sessionManager.liveSessionCount
        let sessionsWord = liveCount == 1 ? "session" : "sessions"
        menu.addItem(makeItem("Free Memory (\(liveCount) live \(sessionsWord))", #selector(closeLiveSessions), key: ""))

        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Ledge", #selector(quit), key: "q"))
    }

    private func makeItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty {
            item.keyEquivalentModifierMask = [.command]
        }
        item.target = self
        return item
    }

    /// Menu items whose action also has a global shortcut advertise that exact
    /// combination, so the menu and the hotkey can never disagree.
    private func makeItem(_ title: String, _ action: Selector, shortcut: GlobalShortcut) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut.keyEquivalent)
        item.keyEquivalentModifierMask = shortcut.keyEquivalentModifierMask
        item.target = self
        return item
    }

    private func makeSitesItem() -> NSMenuItem {
        let sitesItem = NSMenuItem(title: "Sites", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Sites")
        let favourites = panelController.favourites.items
        for favourite in favourites {
            let item = NSMenuItem(title: favourite.name, action: #selector(openSite(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = favourite.id
            // No ⌘-digit equivalents here: those digits name rail rows -- open
            // sessions -- not Home favourites, so advertising them on this menu
            // would promise something the shortcut does not do.
            submenu.addItem(item)
        }
        if favourites.isEmpty {
            let placeholder = NSMenuItem(title: "No Favourites Yet", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            submenu.addItem(placeholder)
        }
        sitesItem.submenu = submenu
        return sitesItem
    }

    /// Notes are surfaced here as well as on Home because the menu bar is
    /// the only always-visible surface of an accessory app: with the panel
    /// hidden, this is how a saved note is reached without the hotkey.
    private func makeNotesItem() -> NSMenuItem {
        let notesItem = NSMenuItem(title: "Notes", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Notes")

        let newItem = NSMenuItem(title: "New Note…", action: #selector(openNewNote), keyEquivalent: "n")
        newItem.keyEquivalentModifierMask = [.command]
        newItem.target = self
        submenu.addItem(newItem)

        let notes = panelController.noteController.store.notes
        if !notes.isEmpty {
            submenu.addItem(.separator())
            for note in notes {
                let item = NSMenuItem(title: note.title, action: #selector(openSavedNote(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = note.id
                submenu.addItem(item)
            }
        }
        notesItem.submenu = submenu
        return notesItem
    }

    @objc private func toggleVisibility() {
        panelController.toggleVisibility()
    }

    @objc private func dockLeft() {
        panelController.setDockSide(.left)
    }

    @objc private func dockRight() {
        panelController.setDockSide(.right)
    }

    @objc private func toggleKeepOpen() {
        panelController.toggleAutoHide()
    }

    @objc private func toggleEdgeReveal() {
        panelController.preferences.edgeTriggerEnabled.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func openSite(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let favourite = panelController.favourites.favourite(withID: id) else { return }
        // Unlike the home grid (where the panel is already showing),
        // choosing a site from this menu has to also reveal the panel --
        // otherwise, while hidden, the site loads invisibly and the click
        // looks like it did nothing.
        panelController.revealAndOpen(favourite)
    }

    @objc private func openNewNote() {
        // Opening a key window from inside a tracking menu needs the same
        // tick-delay the Settings button uses.
        DispatchQueue.main.async { [weak self] in
            self?.panelController.openNewNote()
        }
    }

    @objc private func openSavedNote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let note = panelController.noteController.store.note(withID: id) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.panelController.openNote(note)
        }
    }

    @objc private func openSettings() {
        // Wait until the status-bar menu has finished tracking before asking
        // SwiftUI to present another window.
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)

            // Use SwiftUI's own Settings command from the application menu.
            // Unlike the private showSettingsWindow: selector, this does not
            // report success and then silently discard the request.
            if let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu,
               let settingsIndex = appMenu.items.firstIndex(where: {
                   $0.keyEquivalent == ","
                       && $0.keyEquivalentModifierMask.contains(.command)
               }) {
                appMenu.performActionForItem(at: settingsIndex)
                return
            }

            // Compatibility fallback if SwiftUI ever stops assigning ⌘, to
            // its Settings command.
            if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) { return }
            if NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) { return }
            self?.panelController.show()
        }
    }

    @objc private func clearCaches() {
        panelController.clearCaches()
    }

    @objc private func clearAllWebsiteData() {
        // Signs the user out of every site, so it is confirmed like any
        // other irreversible, wide-blast-radius action.
        let alert = NSAlert()
        alert.messageText = "Clear all website data?"
        alert.informativeText = "This signs you out of every site in Ledge and cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        panelController.clearAllWebsiteData()
    }

    @objc private func closeLiveSessions() {
        // Routes through the controller (not the session manager directly)
        // so a browser-mode destination doesn't end up pointing at a
        // session that no longer exists -- see `PanelController.closeAllSessions`.
        panelController.closeAllSessions()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
