import Foundation
import ServiceManagement
import SwiftUI

/// How aggressively the panel animates when it slides or
/// re-docks.
enum AnimationSpeed: String, CaseIterable, Identifiable, Sendable {
    case snappy
    case standard
    case relaxed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .snappy: "Snappy"
        case .standard: "Standard"
        case .relaxed: "Relaxed"
        }
    }

    /// Duration used for the AppKit slide animations.
    var slideDuration: Double {
        switch self {
        case .snappy: 0.16
        case .standard: 0.26
        case .relaxed: 0.40
        }
    }

    /// Matching SwiftUI spring for in-panel transitions so window and
    /// content motion stay in step.
    var contentAnimation: Animation {
        switch self {
        case .snappy: .spring(response: 0.26, dampingFraction: 0.9)
        case .standard: .spring(response: 0.40, dampingFraction: 0.9)
        case .relaxed: .spring(response: 0.58, dampingFraction: 0.92)
        }
    }
}

/// Light/dark handling for the panel chrome.
enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Match system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Where favicons may be fetched from. The default keeps the app's
/// "local-only" promise as far as practical by asking the site itself
/// first and only falling back to a third-party service when that fails.
enum FaviconSource: String, CaseIterable, Identifiable, Sendable {
    case siteThenService
    case siteOnly
    case monogramOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .siteThenService: "Site, then Google fallback"
        case .siteOnly: "Site only (no third party)"
        case .monogramOnly: "Letter tiles only (offline)"
        }
    }

    var allowsSiteFetch: Bool { self != .monogramOnly }
    var allowsServiceFallback: Bool { self == .siteThenService }
}

/// User-visible preferences that are *not* window geometry. Panel size,
/// vertical offset and dock side stay owned by
/// `PanelController` because window interactions mutate them directly;
/// everything here is only ever changed from Settings or a menu.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    /// Whether moving the pointer to the docked screen edge reveals the
    /// panel. Turning this off makes the hotkey/menu bar the only way in.
    @Published var edgeTriggerEnabled: Bool {
        didSet { store(edgeTriggerEnabled, .edgeTriggerEnabled) }
    }

    /// How long the pointer must dwell at the edge before the panel slides
    /// in. Prevents accidental reveals while dragging across the screen.
    @Published var edgeTriggerDelay: Double {
        didSet { store(Self.clampDelay(edgeTriggerDelay), .edgeTriggerDelay) }
    }

    /// When on, an edge reveal happens on whichever display holds the
    /// pointer. When off the panel stays on the display it was last docked
    /// to.
    @Published var followsMouseDisplay: Bool {
        didSet { store(followsMouseDisplay, .followsMouseDisplay) }
    }

    @Published var animationSpeed: AnimationSpeed {
        didSet { store(animationSpeed.rawValue, .animationSpeed) }
    }

    @Published var appearance: AppearanceMode {
        didSet { store(appearance.rawValue, .appearance) }
    }

    @Published var searchEngine: SearchEngine {
        didSet { store(searchEngine.rawValue, .searchEngine) }
    }

    @Published var faviconSource: FaviconSource {
        didSet { store(faviconSource.rawValue, .faviconSource) }
    }

    /// Reveals the panel without stealing keyboard focus from the frontmost
    /// app until the user actually clicks into it.
    @Published var edgeRevealTakesFocus: Bool {
        didSet { store(edgeRevealTakesFocus, .edgeRevealTakesFocus) }
    }

    /// When off (the default) the browser toolbar floats over the page and
    /// only appears on hover near the top, on ⌘L, or while the address field
    /// is being edited -- a permanently docked bar costs ~52pt of height in a
    /// panel that is already narrow.
    @Published var pinsBrowserToolbar: Bool {
        didSet { store(pinsBrowserToolbar, .pinsBrowserToolbar) }
    }

    /// When on (the default) a note editor renders its Markdown as it is
    /// typed: `- ` becomes a bullet dot point, `# ` a heading, `**bold**`
    /// bold. The file on disk is still plain Markdown -- only the drawing
    /// changes -- so this is a view preference rather than a document
    /// format, and it is shared by every open note instead of being set per
    /// tab: "how I write notes" is a habit, not a property of one file.
    @Published var notesRenderMarkdown: Bool {
        didSet { store(notesRenderMarkdown, .notesRenderMarkdown) }
    }

    private let defaults: UserDefaults

    private enum Key: String {
        case edgeTriggerEnabled = "ledge.edgeTriggerEnabled"
        case edgeTriggerDelay = "ledge.edgeTriggerDelay"
        case followsMouseDisplay = "ledge.followsMouseDisplay"
        case animationSpeed = "ledge.animationSpeed"
        case appearance = "ledge.appearance"
        case searchEngine = "ledge.searchEngine"
        case faviconSource = "ledge.faviconSource"
        case edgeRevealTakesFocus = "ledge.edgeRevealTakesFocus"
        case pinsBrowserToolbar = "ledge.pinsBrowserToolbar"
        case notesRenderMarkdown = "ledge.notes.renderMarkdown"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        edgeTriggerEnabled = defaults.object(forKey: Key.edgeTriggerEnabled.rawValue) as? Bool ?? true
        edgeTriggerDelay = Self.clampDelay(
            defaults.object(forKey: Key.edgeTriggerDelay.rawValue) as? Double ?? 0.12
        )
        followsMouseDisplay = defaults.object(forKey: Key.followsMouseDisplay.rawValue) as? Bool ?? true
        animationSpeed = AnimationSpeed(
            rawValue: defaults.string(forKey: Key.animationSpeed.rawValue) ?? ""
        ) ?? .standard
        appearance = AppearanceMode(
            rawValue: defaults.string(forKey: Key.appearance.rawValue) ?? ""
        ) ?? .system
        searchEngine = SearchEngine(
            rawValue: defaults.string(forKey: Key.searchEngine.rawValue) ?? ""
        ) ?? .google
        faviconSource = FaviconSource(
            rawValue: defaults.string(forKey: Key.faviconSource.rawValue) ?? ""
        ) ?? .siteThenService
        edgeRevealTakesFocus = defaults.object(forKey: Key.edgeRevealTakesFocus.rawValue) as? Bool ?? false
        pinsBrowserToolbar = defaults.object(forKey: Key.pinsBrowserToolbar.rawValue) as? Bool ?? false
        notesRenderMarkdown = defaults.object(forKey: Key.notesRenderMarkdown.rawValue) as? Bool ?? true
    }

    /// Delay is clamped so a mis-typed value can never make the trigger feel
    /// broken (instant reveals) or unusable (multi-second waits).
    static func clampDelay(_ value: Double) -> Double {
        min(max(value, 0), 1.0)
    }

    private func store(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
}

// MARK: - Launch at login

/// Thin wrapper over `SMAppService` so the Settings UI does not have to know
/// that login items only work for a real `.app` bundle (they are a no-op for
/// `swift run` builds).
@MainActor
enum LoginItem {
    /// Login items require a bundle identifier; a bare SwiftPM executable
    /// has none, so the control is hidden rather than silently failing.
    static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Returns `true` when the requested state was reached.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard isSupported else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
