import AppKit
import Combine
import SwiftUI

/// What the main pane is currently showing.
enum LauncherDestination: Hashable {
    case home
    case favourite(UUID)
    /// A transient tab. It shows the start page until something is loaded
    /// into it (see `blankTabIDs`), then the web view.
    case tab(UUID)
}

/// Which screen edge the panel is currently pinned to.
enum DockSide: String {
    case left
    case right
}

/// The panel's own reveal/hide state machine, tracked independently of
/// `NSWindow.isVisible` -- AppKit reports a panel as visible from the
/// moment it is ordered front until `orderOut(nil)` actually runs, which
/// spans the *entire* slide animation in both directions. That collapses
/// "fully hidden", "sliding in", "fully shown", and "sliding out" into a
/// single boolean, which is exactly why a `show()` requested mid-`hide()`
/// used to look like a no-op: `reveal(activating:)` saw `isVisible == true`
/// and assumed there was nothing left to animate. See `animationGeneration`
/// for how in-flight animations are superseded when the phase changes.
enum PanelPhase {
    case hidden
    case revealing
    case visible
    case hiding
}

@MainActor
final class PanelController: NSObject, ObservableObject {
    static let expandedWidth: CGFloat = 880
    static let expandedHeight: CGFloat = 620
    /// How far the panel travels when sliding in or out. Short on purpose:
    /// on a multi-display desktop the space just beyond the docked edge
    /// belongs to the next monitor, so a long slide is a long trip across
    /// someone else's screen.
    static let slideTravel: CGFloat = 120

    @Published var destination: LauncherDestination = .home
    @Published var isShowingAddFavourite = false
    /// Which edge the panel is docked to. Settable via `setDockSide`, and
    /// also updated automatically when the user drags the panel past the
    /// screen midpoint (see `windowDidMove`).
    @Published private(set) var dockSide: DockSide
    /// When enabled, the panel hides itself ~0.5s after the pointer leaves
    /// it or the app loses focus, and can be brought back by hovering the
    /// docked screen edge (see `EdgeTriggerController`).
    @Published private(set) var isAutoHideEnabled: Bool
    /// Bumped whenever the search field should (re)claim focus. Views watch
    /// this instead of using a blind delayed-autofocus timer, so focus is
    /// only stolen when the panel is actually shown in the home state.
    @Published private(set) var homeFocusToken = 0
    /// Bumped whenever the address field (browser mode) should (re)claim
    /// focus and select all -- mirrors `homeFocusToken` for the omnibox.
    @Published private(set) var addressFocusToken = 0
    /// Bumped whenever the find-in-page field should claim focus.
    @Published private(set) var findFocusToken = 0
    /// Whether the find-in-page bar is showing. Browser-mode only -- the
    /// home screen has nothing to search inside.
    @Published var isShowingFindBar = false
    /// Tracks `panel?.isVisible` so other components (keyboard shortcuts,
    /// Settings) can query visibility without reaching into AppKit.
    @Published private(set) var isPanelVisible = false
    /// `true` while the pointer is near the top of the panel. `BrowserPanel`
    /// uses it to reveal the floating browser toolbar.
    ///
    /// Computed from the same poll that drives the edge reveal rather than
    /// from a tracking area alone: the web content is a real `NSView` that
    /// covers the pane, and rather than depend on tracking areas firing
    /// beneath it, this is measured directly.
    @Published private(set) var isPointerNearPanelTop = false
    /// Transient tabs that have not been navigated anywhere yet, and so show
    /// the start page.
    ///
    /// Tracked here rather than inferred from `WebSession.currentURL` so the
    /// view layer re-renders on the change: the shell observes the controller
    /// and the session *manager*, not every individual session.
    @Published private(set) var blankTabIDs: Set<UUID> = []

    let sessionManager = SessionManager()
    let favourites = FavouritesStore()
    let preferences = Preferences.shared

    private var panel: NSPanel?
    private var hostView: PanelHostView?
    private var expandedSize: NSSize
    /// The last display on which the panel was visibly docked. AppKit may
    /// report a different `window.screen` after a panel is moved off-screen.
    private var dockedScreen: NSScreen?
    private lazy var edgeTrigger = EdgeTriggerController(
        onEnter: { [weak self] screen in self?.handleEdgeApproach(on: screen) },
        onExit: { [weak self] _ in self?.cancelPendingEdgeReveal() }
    )
    // `Any?` monitor tokens are opaque, thread-safely-removable handles;
    // `nonisolated(unsafe)` lets `deinit` (which cannot itself be
    // MainActor-isolated) remove them during teardown.
    nonisolated(unsafe) private var outsideClickMonitor: Any?
    nonisolated(unsafe) private var edgeMouseMonitor: Any?
    private var storedFrameY: CGFloat?
    private var isRepinning = false
    /// Stops the window delegate from treating our own edge-slide and
    /// re-dock animations as user drags and snapping them to the edge.
    private var isAnimatingPanel = false
    private var isLiveResizing = false
    private var autoHideWorkItem: DispatchWorkItem?
    private var isMenuTracking = false
    /// Current reveal/hide state (see `PanelPhase`) and a monotonically
    /// increasing token bumped every time a new reveal or hide animation
    /// starts. Animation completion handlers capture the generation that
    /// was current when they were scheduled and become a no-op if it no
    /// longer matches `animationGeneration` by the time they run, so an
    /// interrupted reveal's stale completion can't undo a hide that
    /// started after it (or vice versa).
    private var panelPhase: PanelPhase = .hidden
    private var animationGeneration = 0
    /// Debounces the horizontal re-dock snap in `windowDidMove` so it
    /// doesn't fight an active drag -- re-armed on every move event
    /// received while a mouse button is held, and only actually snaps once
    /// movement has settled (see `windowDidMove`).
    private var pendingEdgeSnap: DispatchWorkItem?
    /// The pending dwell timer for an in-progress edge reveal, plus the
    /// screen it was armed for -- moving away before it fires cancels it,
    /// and re-arming for the same screen is a no-op so continuous mouse
    /// movement while dwelling does not keep pushing the reveal back.
    private var pendingEdgeReveal: DispatchWorkItem?
    private var pendingEdgeRevealScreen: NSScreen?
    /// Pointer poll used while the panel is hidden; see `startEdgePolling`.
    private var edgePollTimer: Timer?
    /// Countdown to a hide caused by the pointer leaving the panel; kept
    /// separate from `autoHideWorkItem` so the poll can tell "already
    /// counting down" from "not armed".
    private var pointerExitHide: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private let activeFavouriteKey = "ledge.activeFavouriteID"
    private let frameYKey = "ledge.frameY"
    private let dockSideKey = "ledge.dockSide"
    private let autoHideKey = "ledge.autoHideEnabled"
    private let edgeBehaviourVersionKey = "ledge.edgeBehaviourVersion"
    private let panelWidthKey = "ledge.panelWidth"
    private let panelHeightKey = "ledge.panelHeight"

    override init() {
        let defaults = UserDefaults.standard
        if let storedY = defaults.object(forKey: "ledge.frameY") as? Double {
            storedFrameY = CGFloat(storedY)
        }
        dockSide = DockSide(
            rawValue: defaults.string(forKey: "ledge.dockSide") ?? DockSide.left.rawValue
        ) ?? .left
        // Edge reveal is the primary interaction model, not an optional
        // hidden feature. Migrate prior builds (which defaulted to false)
        // to auto-hide on once; users can still turn it off from the …
        // menu afterwards.
        if defaults.integer(forKey: edgeBehaviourVersionKey) < 2 {
            // Only default to auto-hide *on* when the user has never
            // actually touched the setting -- if `autoHideKey` already has
            // a stored value, that was a deliberate choice (most likely
            // turning it off), and this migration must not silently
            // overwrite it.
            if defaults.object(forKey: autoHideKey) == nil {
                isAutoHideEnabled = true
                defaults.set(true, forKey: autoHideKey)
            } else {
                isAutoHideEnabled = defaults.bool(forKey: autoHideKey)
            }
            defaults.set(2, forKey: edgeBehaviourVersionKey)
        } else {
            isAutoHideEnabled = defaults.bool(forKey: autoHideKey)
        }
        expandedSize = NSSize(
            width: max(520, CGFloat(defaults.object(forKey: "ledge.panelWidth") as? Double ?? Self.expandedWidth)),
            height: max(400, CGFloat(defaults.object(forKey: "ledge.panelHeight") as? Double ?? Self.expandedHeight))
        )
        super.init()
        restoreActiveDestination()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidBeginTracking),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidEndTracking),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )
        installOutsideClickMonitor()
        if preferences.edgeTriggerEnabled {
            installEdgeMouseMonitor()
        }
        // Startup default; the subscription below only fires on *future*
        // changes so this does not depend on Combine's initial-value timing.
        FaviconStore.shared.source = preferences.faviconSource
        observePreferences()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let edgeMouseMonitor { NSEvent.removeMonitor(edgeMouseMonitor) }
    }

    private func restoreActiveDestination() {
        guard let idString = UserDefaults.standard.string(forKey: activeFavouriteKey),
              let id = UUID(uuidString: idString),
              let favourite = favourites.items.first(where: { $0.id == id }) else { return }
        let session = sessionManager.session(forFavourite: favourite)
        sessionManager.setActiveSession(session.id)
        destination = .favourite(favourite.id)
    }

    // MARK: - Preferences wiring

    /// Reacts to user-facing preference changes. Each property is observed
    /// individually (rather than a single `objectWillChange` sink) so each
    /// handler gets the already-updated value instead of the pre-change one.
    private func observePreferences() {
        preferences.$edgeTriggerEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.installEdgeMouseMonitor()
                    self.updateEdgeTrigger()
                } else {
                    self.removeEdgeMouseMonitor()
                    self.cancelPendingEdgeReveal()
                    self.edgeTrigger.hide()
                }
            }
            .store(in: &cancellables)

        preferences.$followsMouseDisplay
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateEdgeTrigger()
            }
            .store(in: &cancellables)

        preferences.$appearance
            .dropFirst()
            .sink { [weak self] mode in
                self?.panel?.appearance = mode.nsAppearance
            }
            .store(in: &cancellables)

        preferences.$faviconSource
            .dropFirst()
            .sink { source in
                FaviconStore.shared.source = source
                FaviconStore.shared.invalidate()
            }
            .store(in: &cancellables)
    }

    // MARK: - Dock side / auto-hide settings

    /// Explicitly pins the panel to `side` (e.g. from a "Dock Left/Right"
    /// menu command), persists the choice, and re-lays-out the panel.
    func setDockSide(_ side: DockSide) {
        guard side != dockSide else { return }
        dockSide = side
        UserDefaults.standard.set(side.rawValue, forKey: dockSideKey)
        placePanel(animated: true)
        updateEdgeTrigger()
    }

    func setAutoHide(_ enabled: Bool) {
        guard enabled != isAutoHideEnabled else { return }
        isAutoHideEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: autoHideKey)
        if !enabled {
            cancelAutoHide()
        }
    }

    func toggleAutoHide() {
        setAutoHide(!isAutoHideEnabled)
    }

    // MARK: - Focus-loss hide / edge-trigger reveal

    /// Single source of truth for whether an unattended (timer-driven) hide
    /// may proceed right now. Checked both when the timer is *scheduled*
    /// and again right before it actually *fires* -- the world can change
    /// in that ~80ms window (a menu can start tracking, a sheet can pop
    /// up), so scheduling-time eligibility alone isn't enough. `attachedSheet`
    /// matters because a SwiftUI `.sheet` on the panel (Add Favourite,
    /// Manage Favourites) is not necessarily `NSApp.modalWindow`.
    private var canAutoHide: Bool {
        isAutoHideEnabled && !isMenuTracking && NSApp.modalWindow == nil && panel?.attachedSheet == nil
    }

    private func scheduleAutoHide() {
        guard canAutoHide else { return }
        autoHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.canAutoHide else { return }
            self.hide()
        }
        autoHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    /// The other half of a slide-over: a panel revealed by *hovering* has to
    /// leave again when the pointer wanders off, otherwise it parks itself
    /// over the user's work until they think to click somewhere else.
    ///
    /// It deliberately does nothing once the app is active: at that point the
    /// user has clicked into the panel and may be reading or typing with the
    /// pointer parked anywhere, and yanking the panel away would be hostile.
    /// Those sessions end via `appDidResignActive` or an outside click
    /// instead. The grace period is long enough that clipping a corner of the
    /// panel on the way past does not dismiss it.
    ///
    /// Armed from both the tracking-area exit event and the pointer poll,
    /// because the exit event is not guaranteed to arrive -- so it keeps its
    /// own work item and refuses to re-arm while one is already counting
    /// down, otherwise the poll would push the deadline back forever.
    private func scheduleHideAfterPointerExit() {
        guard pointerExitHide == nil, canAutoHide, !NSApp.isActive, panel?.isKeyWindow != true else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pointerExitHide = nil
            guard self.canAutoHide, !NSApp.isActive, let panel = self.panel, panel.isVisible else { return }
            // Re-check the pointer: it may have come back over the panel
            // between arming this and it firing.
            guard !panel.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) else { return }
            self.hide()
        }
        pointerExitHide = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func cancelPointerExitHide() {
        pointerExitHide?.cancel()
        pointerExitHide = nil
    }

    private func cancelAutoHide() {
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil
        cancelPointerExitHide()
    }

    @objc private func appDidResignActive() {
        scheduleAutoHide()
    }

    @objc private func appDidBecomeActive() {
        cancelAutoHide()
    }

    @objc private func menuDidBeginTracking() {
        isMenuTracking = true
        cancelAutoHide()
    }

    @objc private func menuDidEndTracking() {
        isMenuTracking = false
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let panel = self.panel,
                  panel.isVisible,
                  !panel.frame.contains(NSEvent.mouseLocation) else { return }
            self.scheduleAutoHide()
        }
    }

    @objc private func screenParametersChanged() {
        guard panel != nil else { return }
        // A display can be unplugged (or otherwise invalidate
        // `dockedScreen`) while the panel just sits there quietly -- always
        // re-resolve before repositioning so the panel and its edge-trigger
        // strip don't end up parked over a screen that no longer exists.
        dockedScreen = resolvedDockedScreen()
        placePanel(animated: false)
        updateEdgeTrigger()
    }

    // MARK: - Show / hide (edge-slide)

    /// Explicit summon path (launch, menu-bar item, hotkey). It activates
    /// the app so keyboard input can immediately go to the search field.
    func show() {
        // With "reveal on the display under the pointer" on, an explicit
        // summon should honour it too: otherwise the panel appears on
        // whichever display it was last used on, which on an extended desktop
        // is routinely not the one being worked on. This also gives a way to
        // put the panel on a display whose docked edge is an interior seam
        // and therefore cannot be hovered at all.
        if preferences.followsMouseDisplay,
           panelPhase == .hidden || panelPhase == .hiding,
           let pointerScreen = ScreenEdge.screen(containing: NSEvent.mouseLocation) {
            dockedScreen = pointerScreen
        }
        reveal(activating: true)
    }

    /// Edge-hover path. Whether it steals keyboard focus is governed by
    /// `preferences.edgeRevealTakesFocus` (default off, so the frontmost
    /// app keeps typing focus until the user actually clicks into the panel).
    func showFromEdgeHover() {
        reveal(activating: preferences.edgeRevealTakesFocus)
    }

    private func reveal(activating: Bool) {
        if panel == nil {
            createPanel()
        }
        guard let panel else { return }
        cancelAutoHide()
        cancelPendingEdgeReveal()
        edgeTrigger.hide()
        let visibleFrame = screenFrame()
        let target = frame(in: visibleFrame)

        switch panelPhase {
        case .visible, .revealing:
            // Already showing, or already on its way in -- nothing left to
            // (re)animate, just take focus if asked.
            if activating {
                panel.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        case .hidden, .hiding:
            // Keying off `panelPhase` here (rather than `panel.isVisible`,
            // which AppKit keeps `true` for the entire slide-out) is what
            // lets a `show()` requested mid-`hide()` actually reverse the
            // animation instead of looking like a no-op.
            let wasFullyHidden = panelPhase == .hidden
            let generation = beginAnimation(phase: .revealing)
            if wasFullyHidden {
                var startFrame = target
                startFrame.origin.x = offscreenX(for: target.width, in: visibleFrame)
                panel.setFrame(startFrame, display: false)
                // Fade in over the slide: the leading part of the travel sits
                // beyond the docked edge, which on an extended desktop is the
                // next monitor. Starting at zero alpha means nothing is ever
                // painted onto the neighbouring screen.
                panel.alphaValue = 0
            } else if let currentScreen = resolvedDockedScreen(),
                      panel.screen !== currentScreen {
                // Interrupting a slide-out that was heading off a *different*
                // display: restart from this display's edge instead of
                // dragging the panel across the gap between them.
                var startFrame = target
                startFrame.origin.x = offscreenX(for: target.width, in: visibleFrame)
                panel.setFrame(startFrame, display: false)
            }
            // When interrupting an in-flight `hide()` (`.hiding`), leave the
            // panel wherever its own slide-out had already carried it to and
            // simply retarget towards `target` -- Core Animation redirects
            // the in-flight transform smoothly rather than jump-cutting back
            // to the edge first.
            if activating {
                panel.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                panel.orderFrontRegardless()
            }
            // AppKit reports `isVisible == true` as soon as the panel is
            // ordered front, even though the slide-in animation is still
            // running -- so the session lifecycle hook fires immediately
            // rather than waiting on the cosmetic animation to finish. Only
            // do this when coming up from fully hidden: interrupting a
            // `hide()` means the session was never actually reported hidden
            // in the first place (that only happens in `hide()`'s own,
            // now-superseded, completion), so there is nothing to re-reveal.
            if wasFullyHidden {
                isPanelVisible = true
                sessionManager.panelDidReveal()
            }
            animateReveal(to: target, generation: generation)
        }

        if activating, showsStartPage {
            DispatchQueue.main.async { [weak self] in
                self?.bumpHomeFocus()
            }
        }
    }

    /// Bumps the animation generation and updates the phase immediately, so
    /// anything checking `panelPhase` right after calling `show()`/`hide()`
    /// sees the new state rather than a stale one. Returns the generation
    /// token the corresponding animation's completion handler must check
    /// before touching any shared state.
    @discardableResult
    private func beginAnimation(phase: PanelPhase) -> Int {
        animationGeneration += 1
        panelPhase = phase
        isAnimatingPanel = true
        return animationGeneration
    }

    /// The slide-in half of `reveal(activating:)`'s animation. A no-op
    /// completion if a newer reveal/hide has since superseded `generation`.
    private func animateReveal(to target: NSRect, generation: Int) {
        guard let panel else { return }
        animateAlpha(to: 1, revealing: true)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = preferences.animationSpeed.slideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.animationGeneration == generation else { return }
                self.isAnimatingPanel = false
                self.panelPhase = .visible
                panel.alphaValue = 1
            }
        })
    }

    /// Opacity is animated separately from the frame so its curve can differ.
    ///
    /// The leading portion of the travel overhangs the docked edge, which on
    /// an extended desktop is the neighbouring monitor. Fading *in* slowly
    /// (`easeIn`) keeps the panel near-transparent while it is still out
    /// there, and fading *out* quickly (a fraction of the slide, `easeOut`)
    /// means it is already invisible before it travels past the edge.
    private func animateAlpha(to value: CGFloat, revealing: Bool) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = preferences.animationSpeed.slideDuration * (revealing ? 1.0 : 0.4)
            context.timingFunction = CAMediaTimingFunction(name: revealing ? .easeIn : .easeOut)
            panel.animator().alphaValue = value
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        // An explicit hide (hotkey, menu, auto-hide) must never yank the
        // panel out from under a SwiftUI `.sheet` (Add Favourite, Manage
        // Favourites): a sheet's window isn't necessarily
        // `NSApp.modalWindow`, so without this guard the panel could slide
        // away while its sheet is still open, stranding the sheet with no
        // parent visible on screen. The sheet has to be dismissed first.
        guard panel.attachedSheet == nil else { return }
        // Already on its way out -- avoid restarting the same animation
        // (and bumping the generation) for no reason.
        guard panelPhase != .hiding else { return }
        cancelAutoHide()
        cancelPendingEdgeReveal()
        dockedScreen = resolvedDockedScreen()
        let visibleFrame = screenFrame()
        var offFrame = panel.frame
        offFrame.origin.x = offscreenX(for: offFrame.width, in: visibleFrame)
        let generation = beginAnimation(phase: .hiding)
        animateAlpha(to: 0, revealing: false)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = preferences.animationSpeed.slideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(offFrame, display: true)
        }, completionHandler: { [weak self, panel] in
            MainActor.assumeIsolated {
                guard let self, self.animationGeneration == generation else { return }
                panel.orderOut(nil)
                panel.alphaValue = 0
                self.isAnimatingPanel = false
                self.isPanelVisible = false
                self.panelPhase = .hidden
                self.sessionManager.panelDidHide()
                self.updateEdgeTrigger()
            }
        })
    }

    func toggleVisibility() {
        guard let panel else {
            show()
            return
        }
        // Keyed off `panelPhase`, not `panel.isVisible`: AppKit keeps
        // `isVisible` true for the whole slide-out, so pressing the hotkey
        // twice quickly used to hide and then "hide" again instead of
        // reversing the animation.
        _ = panel
        switch panelPhase {
        case .visible, .revealing:
            hide()
        case .hidden, .hiding:
            show()
        }
    }

    func bumpHomeFocus() {
        homeFocusToken += 1
    }

    /// Brings the panel into existence and arms the edge reveal *without*
    /// showing it. Used at launch when the app is already a login item: a
    /// slide-over that flings itself open every time you log in is not what
    /// anyone wants, but it does have to be ready to reveal on hover.
    func prepareHidden() {
        if panel == nil {
            createPanel()
        }
        panel?.alphaValue = 0
        panelPhase = .hidden
        isPanelVisible = false
        updateEdgeTrigger()
    }

    // MARK: - Navigation

    /// Opens a saved site.
    ///
    /// An empty tab is a placeholder for "somewhere to go", so it gets *filled*
    /// by whatever is opened from it -- a typed address or, here, a saved site.
    /// That is what makes a second, independent view of a site possible: the
    /// saved item keeps its own warm session, and the tab gets its own. Jumping
    /// to the saved session and throwing the tab away instead would mean the
    /// tab could never be used to look at a site you had also saved.
    ///
    /// With no empty tab in play this is the plain dock behaviour: switch to the
    /// site's single persistent session.
    func openFavourite(_ favourite: Favourite) {
        if let tabID = activeTabID, blankTabIDs.contains(tabID) {
            load(favourite.url, inTab: tabID)
            return
        }

        let session = sessionManager.session(forFavourite: favourite)
        sessionManager.setActiveSession(session.id)
        destination = .favourite(favourite.id)
        UserDefaults.standard.set(favourite.id.uuidString, forKey: activeFavouriteKey)
    }

    /// Fills a transient tab with `url` and selects it.
    private func load(_ url: URL, inTab tabID: UUID) {
        guard let session = sessionManager.existingSession(for: .tab(tabID)) else { return }
        session.load(url)
        blankTabIDs.remove(tabID)
        sessionManager.setActiveSession(session.id)
        destination = .tab(tabID)
        isShowingFindBar = false
        UserDefaults.standard.removeObject(forKey: activeFavouriteKey)
    }

    /// 0-based convenience for the ⌘1…⌘9 shortcuts and the status-bar Sites
    /// menu. Silently ignored if there is no favourite at that index.
    func openFavourite(at index: Int) {
        guard favourites.items.indices.contains(index) else { return }
        openFavourite(favourites.items[index])
    }

    /// Menu-bar "Sites" entry point. Unlike plain `openFavourite(_:)` --
    /// used by the always-visible home grid, where the panel is already
    /// showing -- choosing a site from the status-bar menu while the panel
    /// is hidden needs to actually bring the panel on screen too, or the
    /// command silently loads the site invisibly and looks like nothing
    /// happened. `openFavourite(_:)` itself deliberately does not activate
    /// the app, so the home grid's behaviour is unaffected.
    func revealAndOpen(_ favourite: Favourite) {
        show()
        openFavourite(favourite)
    }

    /// 0-based convenience mirroring `openFavourite(at:)`.
    func revealAndOpen(at index: Int) {
        guard favourites.items.indices.contains(index) else { return }
        revealAndOpen(favourites.items[index])
    }

    /// The favourite backing the current destination, if any -- `nil` for
    /// `.home` and for transient tabs.
    var activeFavourite: Favourite? {
        guard case .favourite(let id) = destination else { return nil }
        return favourites.favourite(withID: id)
    }

    /// The transient tab backing the current destination, if any.
    var activeTabID: UUID? {
        guard case .tab(let id) = destination else { return nil }
        return id
    }

    /// Whether the main pane should show the start page rather than a web
    /// view: either the Home destination, or a tab nothing has been loaded
    /// into yet.
    var showsStartPage: Bool {
        switch destination {
        case .home:
            true
        case .favourite:
            false
        case .tab(let id):
            blankTabIDs.contains(id)
        }
    }

    /// Wraps forward through the favourites list; starts at the first item
    /// when nothing is currently active (matches `.home`'s behaviour).
    func selectNextFavourite() {
        let items = favourites.items
        guard !items.isEmpty else { return }
        guard let current = activeFavourite,
              let index = items.firstIndex(where: { $0.id == current.id }) else {
            openFavourite(items[0])
            return
        }
        openFavourite(items[(index + 1) % items.count])
    }

    /// Wraps backward through the favourites list; starts at the last item
    /// when nothing is currently active.
    func selectPreviousFavourite() {
        let items = favourites.items
        guard !items.isEmpty else { return }
        guard let current = activeFavourite,
              let index = items.firstIndex(where: { $0.id == current.id }) else {
            openFavourite(items[items.count - 1])
            return
        }
        openFavourite(items[(index - 1 + items.count) % items.count])
    }

    /// Opens an empty transient tab showing the start page, ready for an
    /// address. This is the rail's `+`: it adds an item you can navigate,
    /// rather than asking for a URL up front in a dialog.
    ///
    /// There is only ever one empty tab. Pressing `+` again selects the one
    /// already waiting instead of stacking up identical blank items that are
    /// impossible to tell apart.
    @discardableResult
    func newTab() -> UUID {
        if let waiting = sessionManager.tabSessions
            .compactMap(\.id.tabID)
            .first(where: { blankTabIDs.contains($0) }) {
            openTab(waiting)
            return waiting
        }

        let session = sessionManager.newTabSession()
        let id = session.id.tabID ?? UUID()
        blankTabIDs.insert(id)
        sessionManager.setActiveSession(session.id)
        destination = .tab(id)
        isShowingFindBar = false
        UserDefaults.standard.removeObject(forKey: activeFavouriteKey)
        bumpHomeFocus()
        return id
    }

    /// Loads an address (or a search) from the start page's omnibox.
    ///
    /// It reuses the tab already being viewed when there is one, so typing
    /// into a blank tab fills *that* tab rather than spawning another; from
    /// Home or a saved site it opens a new tab instead, so an ad-hoc search
    /// never stomps a saved site's session.
    func open(address: String) {
        guard let url = AddressResolver.resolve(address, using: preferences.searchEngine) else { return }

        let tabID: UUID
        if let existing = activeTabID {
            tabID = existing
        } else {
            let session = sessionManager.newTabSession()
            tabID = session.id.tabID ?? UUID()
        }
        load(url, inTab: tabID)
    }

    func openTab(_ id: UUID) {
        guard let session = sessionManager.existingSession(for: .tab(id)) else { return }
        sessionManager.setActiveSession(session.id)
        destination = .tab(id)
        isShowingFindBar = false
        if blankTabIDs.contains(id) {
            bumpHomeFocus()
        }
    }

    /// Closes a transient tab. Selecting what to show next mirrors a browser:
    /// the neighbouring tab if there is one, otherwise the start page.
    func closeTab(_ id: UUID) {
        let tabs = sessionManager.tabSessions.compactMap(\.id.tabID)
        let wasActive = activeTabID == id
        let successor = TabSelection.successor(after: id, in: tabs)

        sessionManager.closeSession(kind: .tab(id))
        blankTabIDs.remove(id)

        guard wasActive else { return }
        if let successor {
            openTab(successor)
        } else {
            goHome()
        }
    }

    func goHome() {
        destination = .home
        isShowingFindBar = false
        // Otherwise `activeSessionID` keeps pointing at the last favourite,
        // so reopening that same favourite later hits `setActiveSession`'s
        // early-return (`kind != activeSessionID` is false) and
        // `didBecomeVisible()` never runs -- silently breaking "reload when
        // shown" for that site. `SessionHostView` only unmounts a web view
        // that is absent from `sessionManager.sessions`; passing `nil` here
        // just hides it, so no session is torn down by going home.
        sessionManager.setActiveSession(nil)
        UserDefaults.standard.removeObject(forKey: activeFavouriteKey)
        bumpHomeFocus()
    }

    func removeFavourite(_ favourite: Favourite) {
        favourites.remove(favourite)
        sessionManager.closeSession(kind: .favourite(favourite.id))
        if destination == .favourite(favourite.id) {
            goHome()
        }
    }

    /// Focuses whatever text field is relevant to the current destination:
    /// the browser address field, or the home search field.
    func focusAddressField() {
        if showsStartPage {
            bumpHomeFocus()
        } else {
            addressFocusToken += 1
        }
    }

    /// Browser-mode only (find-in-page has nothing to search on the home
    /// grid). Closing clears any live WebKit find highlight so it does not
    /// linger after the bar disappears.
    func toggleFindBar() {
        guard !showsStartPage else { return }
        if isShowingFindBar {
            closeFindBar()
        } else {
            isShowingFindBar = true
            findFocusToken += 1
        }
    }

    func closeFindBar() {
        guard isShowingFindBar else { return }
        isShowingFindBar = false
        sessionManager.activeSession()?.clearFind()
    }

    func reloadActiveSession() {
        sessionManager.activeSession()?.reload()
    }

    /// Persists the user-agent choice on the favourite and applies it to the
    /// live session (if one exists) so an open tab updates immediately.
    func setUserAgentMode(_ mode: UserAgentMode, for favourite: Favourite) {
        guard let updated = favourites.setUserAgentMode(mode, for: favourite) else { return }
        sessionManager.applyPreferences(from: updated)
    }

    func setReloadsOnFocus(_ enabled: Bool, for favourite: Favourite) {
        guard let updated = favourites.setReloadsOnFocus(enabled, for: favourite) else { return }
        sessionManager.applyPreferences(from: updated)
    }

    /// Frees the active session's `WKWebView` (e.g. "close this tab to
    /// reclaim memory") and returns to the home screen, since there is
    /// nothing left to show in its place.
    func closeActiveSession() {
        guard let kind = sessionManager.activeSessionID else { return }
        sessionManager.closeSession(kind: kind)
        goHome()
    }

    /// "Close live sessions" / "Free memory": routes through the controller
    /// instead of calling `sessionManager.closeAllSessions()` directly, so a
    /// browser-mode destination is never left pointing at a session that no
    /// longer exists -- which otherwise showed a blank, chrome-less pane.
    /// Sessions are freed before `goHome()` runs so its own find-bar and
    /// active-session cleanup has nothing stale left to reference.
    func closeAllSessions() {
        sessionManager.closeAllSessions()
        goHome()
    }

    /// Fire-and-forget wrapper so callers (menu items, Settings buttons)
    /// don't need to be `async` themselves.
    func clearCaches() {
        Task { await sessionManager.clearCaches() }
    }

    /// Fire-and-forget wrapper; see `clearCaches()`. Favicon cache
    /// invalidation is intentionally not done here -- that is driven by the
    /// `faviconSource` preference, not by this action.
    func clearAllWebsiteData() {
        Task { await sessionManager.clearAllWebsiteData() }
    }

    func openAddFavourite() {
        isShowingAddFavourite = true
    }

    /// Promotes the page in the transient "browse" session into a permanent
    /// item in the sidebar, the way a browser's bookmark button works.
    ///
    /// This is the other half of "open a new site": you type an address, look
    /// at it, and only then decide to keep it. Without this the only way to
    /// add a site was to type its address a second time into a dialog.
    @discardableResult
    func addCurrentPageToSidebar() -> Favourite? {
        guard let session = sessionManager.activeSession(),
              let tabID = session.id.tabID else {
            // Not a tab: there is nothing to move, so just save and open it.
            guard let session = sessionManager.activeSession(),
                  let url = session.currentURL, url.host != nil else { return nil }
            let derived = Favourite.preferredName(pageTitle: session.pageTitle, host: session.displayHost)
            let added = favourites.add(name: favourites.uniqueName(derived), address: url.absoluteString)
            openFavourite(added)
            return added
        }
        return pinTab(tabID)
    }

    /// Turns a transient tab into a saved site, keeping its live page.
    ///
    /// `placement` positions the new item in the sidebar, which is what lets a
    /// tab be dragged to an exact spot among the saved sites rather than always
    /// landing at the end.
    @discardableResult
    func pinTab(_ tabID: UUID, placement: SiteDropInsertion? = nil) -> Favourite? {
        guard let session = sessionManager.existingSession(for: .tab(tabID)),
              let url = session.currentURL,
              url.host != nil else { return nil }

        let derived = Favourite.preferredName(pageTitle: session.pageTitle, host: session.displayHost)
        let added = favourites.add(name: favourites.uniqueName(derived), address: url.absoluteString)

        if let placement {
            if placement.isBelow {
                favourites.move(id: added.id, after: placement.targetID)
            } else {
                favourites.move(id: added.id, before: placement.targetID)
            }
        }

        // The tab *becomes* the saved site: the same live web view carries on
        // under the new identity, so the page stays exactly as it was instead
        // of reloading.
        sessionManager.rekey(session, to: .favourite(added.id))
        session.iconHost = added.host
        session.reloadsOnFocus = added.resolvedReloadsOnFocus
        blankTabIDs.remove(tabID)
        destination = .favourite(added.id)
        UserDefaults.standard.set(added.id.uuidString, forKey: activeFavouriteKey)
        return added
    }

    /// Whether the current page is a candidate for `addCurrentPageToSidebar`.
    var canAddCurrentPageToSidebar: Bool {
        guard activeFavourite == nil,
              let url = sessionManager.activeSession()?.currentURL,
              let host = url.host else { return false }
        // Already saved under the same host: offering to add it again would
        // just produce a duplicate rail icon.
        return !favourites.items.contains { $0.url.host == host }
    }

    // MARK: - Geometry

    /// True if `screen` still corresponds to a currently connected display.
    /// Compares by the stable `NSScreenNumber` device-description key
    /// rather than object identity, since AppKit is free to vend a
    /// different `NSScreen` instance for the same physical display across
    /// a screen reconfiguration even when nothing has actually changed.
    private func isScreenConnected(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return NSScreen.screens.contains(screen)
        }
        return NSScreen.screens.contains {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == number
        }
    }

    /// Resolves the screen the panel should actually be placed on right
    /// now, validating `dockedScreen` against the displays that are still
    /// connected -- a screen can be unplugged while the panel is hidden,
    /// which would otherwise silently park the panel and its edge-trigger
    /// strip off in space. Falls back, in order, to the panel's own current
    /// screen, the display under the pointer, then the main screen.
    private func resolvedDockedScreen() -> NSScreen? {
        if let dockedScreen, isScreenConnected(dockedScreen) {
            return dockedScreen
        }
        if let panelScreen = panel?.screen, isScreenConnected(panelScreen) {
            return panelScreen
        }
        let pointer = NSEvent.mouseLocation
        if let underPointer = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) {
            return underPointer
        }
        return NSScreen.main
    }

    private func screenFrame() -> NSRect {
        guard let screen = resolvedDockedScreen() else { return .zero }

        // Dock horizontally to the actual physical laptop/display edge.
        // Preserve the visible-frame vertical bounds so the panel does not
        // overlap the menu bar or a bottom Dock.
        let physical = screen.frame
        let visible = screen.visibleFrame
        return NSRect(
            x: physical.minX,
            y: visible.minY,
            width: physical.width,
            height: visible.height
        )
    }

    /// Where the panel sits at the start of a slide-in (and the end of a
    /// slide-out).
    ///
    /// This is deliberately a *short* offset from the docked edge rather than
    /// a position clear of the whole desktop. A hidden panel is `orderOut`'d,
    /// so it does not matter that this frame overlaps a display -- nothing is
    /// rendered. What does matter is the distance the window travels while
    /// animating: parking it beyond the far side of the desktop meant every
    /// reveal flew the panel across a neighbouring monitor before landing on
    /// the right one. Keeping the travel short, and fading alpha across it
    /// (see `animateReveal`), confines the motion to the docked display's
    /// edge.
    private func offscreenX(for width: CGFloat, in visibleFrame: NSRect) -> CGFloat {
        switch dockSide {
        case .left:
            return visibleFrame.minX - Self.slideTravel
        case .right:
            return visibleFrame.maxX - width + Self.slideTravel
        }
    }

    private func frame(in visibleFrame: NSRect) -> NSRect {
        let width = min(max(520, expandedSize.width), visibleFrame.width)
        let height = min(max(400, expandedSize.height), visibleFrame.height - 32)
        let y: CGFloat
        if let storedFrameY {
            y = min(max(storedFrameY, visibleFrame.minY), visibleFrame.maxY - height)
        } else {
            y = visibleFrame.midY - height / 2
        }
        let x = dockSide == .left ? visibleFrame.minX : visibleFrame.maxX - width
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func placePanel(animated: Bool) {
        guard let panel else { return }
        let visibleFrame = screenFrame()
        panel.minSize = NSSize(width: 520, height: 400)
        let target = frame(in: visibleFrame)

        if animated {
            animate(to: target)
        } else {
            panel.setFrame(target, display: true)
        }
    }

    private func animate(to target: NSRect) {
        guard let panel else { return }
        isAnimatingPanel = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = preferences.animationSpeed.slideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.isAnimatingPanel = false
            }
        }
    }

    private func createPanel() {
        let panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: expandedSize.width, height: expandedSize.height),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // THE critical flag for a slide-over. `NSPanel` defaults this to
        // `true`, which makes AppKit order the panel out the moment the app
        // is not frontmost. An edge-hover reveal deliberately does *not*
        // activate the app, so with the default the panel was ordered out
        // again the instant it appeared: the frame animated to the right
        // place, the window was never on screen, and the only way to see the
        // panel was a path that called `NSApp.activate` -- i.e. "I have to
        // open the app".
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Off deliberately. "Drag anywhere on the background to move the
        // window" is an AppKit behaviour that beats SwiftUI's `.onDrag`: it
        // claims the gesture first, so dragging a site in the rail (or a tile
        // on the home screen) moved the whole panel instead of reordering.
        // The panel is moved with the grip at the top of the rail instead
        // (see `WindowDragHandle`).
        panel.isMovableByWindowBackground = false
        panel.minSize = NSSize(width: 520, height: 400)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.appearance = preferences.appearance.nsAppearance
        panel.delegate = self

        let hosting = NSHostingView(rootView: LauncherShell(controller: self))
        let host = PanelHostView(frame: .zero)
        host.embed(hosting)
        host.onMouseExited = { [weak self] in self?.scheduleHideAfterPointerExit() }
        host.onMouseEntered = { [weak self] in self?.cancelAutoHide() }
        panel.contentView = host
        self.hostView = host

        self.panel = panel
        dockedScreen = panel.screen ?? NSScreen.main
    }

    /// Arms the edge reveal while the panel is hidden: the tracking strips
    /// *and* the pointer poll.
    ///
    /// Only screens whose docked edge is genuinely on the outside of the
    /// desktop are armed (see `ScreenEdge`). Arming an interior seam between
    /// two displays is worse than useless: the pointer sweeps across it
    /// without ever coming to rest, so the panel appears never to open.
    private func updateEdgeTrigger() {
        guard let panel, !panel.isVisible, preferences.edgeTriggerEnabled else {
            edgeTrigger.hide()
            stopEdgePolling()
            return
        }

        let screens = armableScreens()
        guard !screens.isEmpty else {
            edgeTrigger.hide()
            stopEdgePolling()
            return
        }
        edgeTrigger.show(on: screens, side: dockSide)
        startEdgePolling()
    }

    /// Which displays may arm a reveal right now.
    ///
    /// With "reveal on the display under the pointer" on, every display with
    /// an exposed edge qualifies. With it off we would ideally arm only the
    /// docked display -- but if that display's edge is an interior seam there
    /// is nothing to hover, so fall back to the exposed edges rather than
    /// leaving the user with no way in at all.
    private func armableScreens() -> [NSScreen] {
        let exposed = ScreenEdge.screensWithExposedEdge(dockSide)
        guard !preferences.followsMouseDisplay else { return exposed }

        if let docked = resolvedDockedScreen(),
           exposed.contains(where: { $0 === docked }) {
            return [docked]
        }
        return exposed
    }

    private func installOutsideClickMonitor() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hideForOutsideClick()
            }
        }
    }

    /// Global mouse movement is more reliable than a transparent overlay
    /// window on newer macOS releases, where fully transparent windows may
    /// not receive tracking events while another app is active. It is still
    /// only one of three sources feeding `handleEdgeApproach` -- see
    /// `startEdgePolling` for why none of them is trusted on its own.
    private func installEdgeMouseMonitor() {
        guard edgeMouseMonitor == nil else { return }
        edgeMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.revealForGlobalEdgeMotion()
            }
        }
    }

    private func removeEdgeMouseMonitor() {
        if let edgeMouseMonitor { NSEvent.removeMonitor(edgeMouseMonitor) }
        edgeMouseMonitor = nil
    }

    /// Polls the pointer position, and keeps the reveal machinery honest.
    ///
    /// Both event-driven reveal sources are conditional on things outside our
    /// control: a fully transparent tracking window may be treated as
    /// click-through, and a global `.mouseMoved` monitor depends on the window
    /// server routing motion to us. Reading `NSEvent.mouseLocation` a dozen
    /// times a second costs almost nothing and cannot fail, so it is the
    /// source of truth; the other two just make the response feel instant.
    ///
    /// It doubles as a watchdog. If the panel stops being on screen without
    /// going through `hide()` -- which is precisely what `hidesOnDeactivate`
    /// used to do -- then the edge triggers would stay disarmed and the user
    /// would be left with no way back in short of the menu bar. Rather than
    /// trusting that no such path exists, the tick reconciles `panelPhase`
    /// with reality and re-arms.
    private func startEdgePolling() {
        guard edgePollTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollEdgeState()
            }
        }
        // Keep firing while a menu or a window drag is running the run loop
        // in a modal tracking mode.
        RunLoop.main.add(timer, forMode: .common)
        edgePollTimer = timer
    }

    private func pollEdgeState() {
        guard let panel else { return }

        // Self-heal: the panel is meant to be up but is not on screen.
        if panelPhase == .visible, !panel.isVisible {
            panelPhase = .hidden
            isPanelVisible = false
            sessionManager.panelDidHide()
            updateEdgeTrigger()
            return
        }

        // While the panel is up, the poll watches for the pointer leaving it.
        // The tracking-area exit event does the same job and usually gets
        // there first, but it is not guaranteed to arrive at all (a warped
        // cursor produces no motion events, for instance), and a slide-over
        // that refuses to slide out is the whole problem.
        if panel.isVisible, panelPhase == .visible {
            let pointer = NSEvent.mouseLocation
            updatePointerNearTop(pointer, in: panel)
            if panel.frame.insetBy(dx: -4, dy: -4).contains(pointer) {
                cancelPointerExitHide()
            } else {
                scheduleHideAfterPointerExit()
            }
            return
        }

        if isPointerNearPanelTop { isPointerNearPanelTop = false }
        revealForGlobalEdgeMotion()
    }

    private func updatePointerNearTop(_ pointer: NSPoint, in panel: NSWindow) {
        let isNear = ScreenEdge.isPointerNearTop(
            pointer,
            panelFrame: panel.frame,
            wasNear: isPointerNearPanelTop
        )
        if isNear != isPointerNearPanelTop {
            isPointerNearPanelTop = isNear
        }
    }

    private func stopEdgePolling() {
        edgePollTimer?.invalidate()
        edgePollTimer = nil
    }

    /// Called both by the global mouse monitor (continuous polling while
    /// hidden) and by `EdgeTriggerController`'s tracking-area strip. Arms or
    /// re-arms the dwell timer; does not reveal anything by itself.
    private func handleEdgeApproach(on screen: NSScreen) {
        guard preferences.edgeTriggerEnabled, let panel, !panel.isVisible else { return }
        scheduleEdgeReveal(on: screen)
    }

    private func revealForGlobalEdgeMotion() {
        guard preferences.edgeTriggerEnabled, let panel, !panel.isVisible else {
            cancelPendingEdgeReveal()
            return
        }

        let pointer = NSEvent.mouseLocation
        // The pointer must be at the docked edge of one of the *armable*
        // screens. Checking the armable set (rather than "the screen the
        // pointer happens to be on") is what stops an interior seam between
        // two displays from being treated as a hot edge.
        let threshold: CGFloat = 4
        let candidate = armableScreens().first { screen in
            let frame = screen.frame
            guard pointer.y >= frame.minY, pointer.y <= frame.maxY else { return false }
            switch dockSide {
            case .left:
                return pointer.x >= frame.minX - threshold && pointer.x <= frame.minX + threshold
            case .right:
                return pointer.x >= frame.maxX - threshold && pointer.x <= frame.maxX + threshold
            }
        }

        guard let candidate else {
            cancelPendingEdgeReveal()
            return
        }
        scheduleEdgeReveal(on: candidate)
    }

    /// The dwell delay itself: the pointer must stay armed for
    /// `preferences.edgeTriggerDelay` seconds before the panel reveals, so a
    /// cursor merely passing over the edge (e.g. moving to another display)
    /// does not trigger an unwanted reveal.
    private func scheduleEdgeReveal(on screen: NSScreen) {
        if pendingEdgeReveal != nil, pendingEdgeRevealScreen === screen { return }
        cancelPendingEdgeReveal()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingEdgeReveal = nil
            self.pendingEdgeRevealScreen = nil
            if self.preferences.followsMouseDisplay {
                self.dockedScreen = screen
            }
            self.showFromEdgeHover()
        }
        pendingEdgeReveal = workItem
        pendingEdgeRevealScreen = screen
        DispatchQueue.main.asyncAfter(deadline: .now() + preferences.edgeTriggerDelay, execute: workItem)
    }

    private func cancelPendingEdgeReveal() {
        pendingEdgeReveal?.cancel()
        pendingEdgeReveal = nil
        pendingEdgeRevealScreen = nil
    }

    private func hideForOutsideClick() {
        guard canAutoHide,
              let panel,
              panel.isVisible,
              !panel.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) else { return }
        hide()
    }

    private func saveExpandedSize(_ size: NSSize) {
        expandedSize = NSSize(width: max(520, size.width), height: max(400, size.height))
        UserDefaults.standard.set(Double(expandedSize.width), forKey: panelWidthKey)
        UserDefaults.standard.set(Double(expandedSize.height), forKey: panelHeightKey)
    }
}

// MARK: - NSWindowDelegate (edge re-pinning)

extension PanelController: NSWindowDelegate {
    /// Whenever the user drags the panel (it is movable by its background),
    /// snap it back so it always hugs whichever screen edge it is nearer
    /// to horizontally -- dragging past the screen midpoint re-docks the
    /// panel to the other side. Only the vertical position is otherwise
    /// free to move. Both the resolved dock side and the vertical position
    /// are persisted so they survive relaunches.
    func windowDidMove(_ notification: Notification) {
        guard let panel, !isRepinning, !isAnimatingPanel else { return }
        let panelCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        if let screen = NSScreen.screens.first(where: {
            NSMouseInRect(panelCenter, $0.frame, false)
        }) {
            dockedScreen = screen
        }
        let visibleFrame = screenFrame()

        let nearestSide: DockSide = isLiveResizing
            ? dockSide
            : panel.frame.midX < visibleFrame.midX ? .left : .right
        if nearestSide != dockSide {
            dockSide = nearestSide
            UserDefaults.standard.set(nearestSide.rawValue, forKey: dockSideKey)
        }

        // The vertical position is free to follow the drag directly, and
        // dock-side/position are persisted immediately regardless of the
        // snap timing below.
        storedFrameY = panel.frame.origin.y
        UserDefaults.standard.set(Double(panel.frame.origin.y), forKey: frameYKey)

        pendingEdgeSnap?.cancel()
        pendingEdgeSnap = nil

        if NSEvent.pressedMouseButtons == 0 {
            // No button held -- this wasn't a live drag (e.g. a
            // programmatic move, or the mouse-up already happened), so
            // there is no ongoing drag to fight; snap immediately as before.
            snapToDockedEdge(side: nearestSide, in: visibleFrame)
        } else {
            // Mid-drag: forcing `setFrame` on every single move event
            // fights the user's own mouse movement and makes the drag
            // stutter/jitter instead of tracking the pointer smoothly.
            // Debounce the snap -- cancelled and rearmed on every move
            // event above -- so it only actually runs once movement has
            // settled, and only if the button has by then been released.
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.panel != nil,
                      !self.isRepinning, !self.isAnimatingPanel,
                      NSEvent.pressedMouseButtons == 0 else { return }
                self.snapToDockedEdge(side: self.dockSide, in: self.screenFrame())
            }
            pendingEdgeSnap = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }
    }

    /// Moves the panel's x-origin to hug `side` of `visibleFrame`. Guarded
    /// by `isRepinning` so the synthetic `windowDidMove` this triggers is
    /// not itself mistaken for another user drag.
    private func snapToDockedEdge(side: DockSide, in visibleFrame: NSRect) {
        guard let panel else { return }
        let targetX = side == .left ? visibleFrame.minX : visibleFrame.maxX - panel.frame.width
        guard abs(panel.frame.origin.x - targetX) > 0.5 else { return }
        isRepinning = true
        var repinned = panel.frame
        repinned.origin.x = targetX
        panel.setFrame(repinned, display: true)
        isRepinning = false
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        isLiveResizing = true
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        isLiveResizing = false
        guard let panel else { return }
        saveExpandedSize(panel.frame.size)

        let visibleFrame = screenFrame()
        var pinned = panel.frame
        pinned.origin.x = dockSide == .left
            ? visibleFrame.minX
            : visibleFrame.maxX - pinned.width
        panel.setFrame(pinned, display: true)
    }
}
