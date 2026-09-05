import SwiftUI

/// The app's `Settings { }` scene content: General, Shortcuts, and Privacy
/// tabs, all driven by the shared `Preferences` object and the single
/// `PanelController` instance the rest of the app already uses.
struct SettingsView: View {
    @ObservedObject var controller: PanelController
    @ObservedObject private var preferences: Preferences
    let unavailableShortcuts: [GlobalShortcut]

    init(controller: PanelController, unavailableShortcuts: [GlobalShortcut]) {
        self.controller = controller
        self.preferences = controller.preferences
        self.unavailableShortcuts = unavailableShortcuts
    }

    var body: some View {
        TabView {
            GeneralSettingsTab(
                controller: controller,
                preferences: preferences,
                unavailableShortcuts: unavailableShortcuts
            )
                .tabItem { Label("General", systemImage: "gearshape") }

            ShortcutsSettingsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            PrivacySettingsTab(controller: controller, preferences: preferences)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 520, height: 480)
        // Lifts the window above the floating panel; without it, Settings
        // opens underneath the panel and appears not to have opened at all.
        .background(SettingsWindowConfigurator().frame(width: 0, height: 0))
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @ObservedObject var controller: PanelController
    @ObservedObject var preferences: Preferences
    let unavailableShortcuts: [GlobalShortcut]
    @State private var launchAtLoginEnabled = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("Login") {
                if LoginItem.isSupported {
                    Toggle(
                        "Launch Ledge at login",
                        isOn: Binding(
                            get: { launchAtLoginEnabled },
                            set: { newValue in
                                launchAtLoginEnabled = LoginItem.setEnabled(newValue) ? newValue : launchAtLoginEnabled
                            }
                        )
                    )
                } else {
                    Text("Launch at login is only available when Ledge is installed as an app bundle (not while running from source with `swift run`).")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Panel") {
                Picker(
                    "Dock side",
                    selection: Binding(get: { controller.dockSide }, set: { controller.setDockSide($0) })
                ) {
                    Text("Left").tag(DockSide.left)
                    Text("Right").tag(DockSide.right)
                }
                Toggle(
                    "Keep panel open",
                    isOn: Binding(
                        get: { !controller.isAutoHideEnabled },
                        set: { controller.setAutoHide(!$0) }
                    )
                )
            }

            Section("Edge reveal") {
                Toggle("Reveal on hover at the screen edge", isOn: $preferences.edgeTriggerEnabled)
                Text("\(GlobalShortcut.toggleEdgeReveal.displayName) turns this on or off from anywhere, without opening a menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(unavailableShortcuts, id: \.self) { shortcut in
                    Label(
                        "\(shortcut.displayName) could not be registered as a global shortcut -- another app may already use it.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $preferences.edgeTriggerDelay, in: 0...1, step: 0.02)
                    Text("Dwell time before revealing: \(Int((preferences.edgeTriggerDelay * 1000).rounded())) ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!preferences.edgeTriggerEnabled)

                Toggle("Reveal on the display under the pointer", isOn: $preferences.followsMouseDisplay)
                    .disabled(!preferences.edgeTriggerEnabled)
                Toggle("Reveal takes keyboard focus", isOn: $preferences.edgeRevealTakesFocus)
                    .disabled(!preferences.edgeTriggerEnabled)
            }

            Section("Appearance") {
                Picker("Animation speed", selection: $preferences.animationSpeed) {
                    ForEach(AnimationSpeed.allCases) { speed in
                        Text(speed.title).tag(speed)
                    }
                }
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section("Browsing") {
                Toggle("Always show the browser toolbar", isOn: $preferences.pinsBrowserToolbar)
                Text("When off, the toolbar floats over the page and appears when you move the pointer to the top of it, press ⌘L, or open find-in-page — giving the site the full height of the panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Search") {
                Picker("Search engine", selection: $preferences.searchEngine) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(engine.title).tag(engine)
                    }
                }
            }

            Section("Notes") {
                Toggle("Render Markdown while typing", isOn: $preferences.notesRenderMarkdown)
                Text("Formats a note as you write it: “- ” becomes a bullet dot point, “# ” a heading, “**bold**” bold. Notes are still saved as plain Markdown text — only the drawing changes. ⇧⌘L switches it while a note is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

private struct ShortcutsSettingsTab: View {
    private struct Shortcut: Identifiable {
        let id = UUID()
        let keys: String
        let action: String
    }

    // Kept in sync by hand with `KeyCommandHandler`'s mapping.
    private let shortcuts: [Shortcut] = [
        .init(keys: GlobalShortcut.togglePanel.displayName, action: "Show or hide the panel"),
        .init(keys: GlobalShortcut.toggleEdgeReveal.displayName, action: "Turn reveal on edge hover on or off"),
        .init(keys: "⌘1 – ⌘9", action: "Select the Nth open session or note in the sidebar, counting from the top"),
        .init(keys: "⌘0", action: "Reset zoom while browsing a site, else go home"),
        .init(keys: "⇧⌘H", action: "Go home"),
        .init(keys: "⌘L", action: "Focus the address or search field"),
        .init(keys: "⌘R", action: "Reload the current site"),
        .init(keys: "⌘F", action: "Show or hide find-in-page"),
        .init(keys: "⌘T", action: "Open a new session"),
        .init(keys: "⌘N", action: "Open a new note as a tab"),
        .init(keys: "⇧⌘P", action: "Swap the open note between preview and raw Markdown"),
        .init(keys: "⇧⌘L", action: "Turn Markdown rendering in the note editor on or off"),
        .init(keys: "⌘[  /  ⌘←", action: "Back"),
        .init(keys: "⌘]  /  ⌘→", action: "Forward"),
        .init(keys: "⌘+  /  ⌘=", action: "Zoom in"),
        .init(keys: "⌘-", action: "Zoom out"),
        .init(keys: "⇧⌘C", action: "Copy the current page's URL"),
        .init(keys: "⇧⌘O", action: "Open the current page in your default browser"),
        .init(keys: "Esc", action: "Close find-in-page, else leave a focused text field, else pass through to the page, else go home, else hide the panel"),
        .init(keys: "⌘W", action: "Close the current session or note tab; a note is saved, not deleted, and the panel stays")
    ]

    var body: some View {
        Form {
            Section("Keyboard shortcuts") {
                ForEach(shortcuts) { shortcut in
                    LabeledContent(shortcut.keys) {
                        Text(shortcut.action)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Privacy

private struct PrivacySettingsTab: View {
    let controller: PanelController
    @ObservedObject var preferences: Preferences
    @ObservedObject private var sessionManager: SessionManager
    @State private var isShowingClearAllAlert = false

    init(controller: PanelController, preferences: Preferences) {
        self.controller = controller
        self.preferences = preferences
        self.sessionManager = controller.sessionManager
    }

    var body: some View {
        Form {
            Section("Favicons") {
                Picker("Favicon source", selection: $preferences.faviconSource) {
                    ForEach(FaviconSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                Text("\"Site, then Google fallback\" asks each site for its own icon first, and only falls back to a third-party service if that fails. Choose \"Site only\" or \"Letter tiles only\" to avoid any third-party request.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Memory") {
                LabeledContent("Open sessions") {
                    Text("\(sessionManager.liveSessionCount)")
                }
                Button("Close All Sessions") {
                    // Routes through the controller (not the session
                    // manager directly) so a browser-mode destination
                    // doesn't end up pointing at a session that no longer
                    // exists -- see `PanelController.closeAllSessions`.
                    // `sessionManager` is `@ObservedObject`, so this label
                    // keeps reflecting the live count afterwards too.
                    controller.closeAllSessions()
                }
            }

            Section("Website data") {
                Button("Clear Caches") {
                    controller.clearCaches()
                }
                Button("Clear All Website Data…", role: .destructive) {
                    isShowingClearAllAlert = true
                }
            }

            Section {
                Text("Ledge makes no analytics, account, or licensing calls of its own. Network traffic is limited to the websites you open and, depending on the favicon source above, fetching each site's icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Clear all website data?", isPresented: $isShowingClearAllAlert) {
            Button("Clear", role: .destructive) {
                controller.clearAllWebsiteData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This signs you out of every site in Ledge and cannot be undone.")
        }
    }
}
