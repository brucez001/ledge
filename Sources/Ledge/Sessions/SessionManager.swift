import WebKit

/// Owns one persistent `WKWebView`-backed session per favourite plus a
/// single transient "browse" session, all sharing one website data store so
/// logins/cookies are consistent across sessions. Sessions are created
/// lazily on first use and never destroyed just because the user switched
/// away or hid the panel.
@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var sessions: [WebSession] = []
    /// Assign through `setActiveSession(_:)` so visibility lifecycle hooks
    /// (reload-on-focus) always run.
    @Published private(set) var activeSessionID: SessionKind?

    private let dataStore = WKWebsiteDataStore.default()
    private var sessionsByKind: [SessionKind: WebSession] = [:]

    /// Returns the favourite's existing session, or creates and starts one.
    @discardableResult
    func session(forFavourite favourite: Favourite) -> WebSession {
        let kind = SessionKind.favourite(favourite.id)
        if let existing = sessionsByKind[kind] {
            existing.reloadsOnFocus = favourite.resolvedReloadsOnFocus
            existing.setUserAgentMode(favourite.resolvedUserAgentMode)
            return existing
        }
        let session = makeSession(kind: kind, userAgentMode: favourite.resolvedUserAgentMode)
        session.reloadsOnFocus = favourite.resolvedReloadsOnFocus
        // Cache any icon this site declares under the favourite's own host, so
        // the rail item finds it even if the site redirects elsewhere to sign
        // the user in.
        session.iconHost = favourite.host
        session.load(favourite.url)
        register(session)
        return session
    }

    /// Creates a fresh transient tab. Unlike a saved site there is no reuse:
    /// pressing "new tab" is meant to give you somewhere new to go.
    @discardableResult
    func newTabSession() -> WebSession {
        let session = makeSession(kind: .tab(UUID()), userAgentMode: .desktop)
        register(session)
        return session
    }

    /// Transient tabs in the order they were opened (`sessions` preserves
    /// insertion order), for the rail.
    var tabSessions: [WebSession] {
        sessions.filter { $0.id.tabID != nil }
    }

    /// Re-files a live session under a new identity, keeping its web view.
    ///
    /// This is what makes "add this tab to the sidebar" a *move* rather than a
    /// copy: the tab you are looking at becomes the saved site, with the page,
    /// its scroll position, and any form state intact. Creating a fresh
    /// session for the new favourite and closing the tab would reload
    /// everything and briefly run two web views for the same page.
    func rekey(_ session: WebSession, to kind: SessionKind) {
        guard sessionsByKind[session.id] === session, sessionsByKind[kind] == nil else { return }

        let wasActive = activeSessionID == session.id
        sessionsByKind.removeValue(forKey: session.id)
        session.adopt(kind)
        sessionsByKind[kind] = session
        if wasActive {
            activeSessionID = kind
        }
        // `sessions` holds the same objects, so mutating an element's identity
        // publishes nothing by itself; reassigning forces the views that list
        // tabs to recompute.
        sessions = sessions
    }

    func hasSession(forFavouriteID id: UUID) -> Bool {
        sessionsByKind[.favourite(id)] != nil
    }

    func existingSession(for kind: SessionKind) -> WebSession? {
        sessionsByKind[kind]
    }

    func activeSession() -> WebSession? {
        guard let activeSessionID else { return nil }
        return sessionsByKind[activeSessionID]
    }

    /// Number of live web views, surfaced in Settings so the memory cost of
    /// keeping sessions warm is visible rather than mysterious.
    var liveSessionCount: Int { sessions.count }

    /// Switches the visible session, running hide/show hooks on the way.
    func setActiveSession(_ kind: SessionKind?) {
        guard kind != activeSessionID else { return }
        if let previous = activeSessionID, let session = sessionsByKind[previous] {
            session.didBecomeHidden(pausingMedia: false)
        }
        activeSessionID = kind
        if let kind, let session = sessionsByKind[kind] {
            session.didBecomeVisible()
        }
    }

    /// Re-runs the visible session's appearance hook, used when the panel
    /// itself is revealed without the active session changing.
    func panelDidReveal() {
        activeSession()?.didBecomeVisible()
    }

    func panelDidHide() {
        activeSession()?.didBecomeHidden(pausingMedia: false)
    }

    /// Applies a favourite's stored preferences to its live session, if any.
    func applyPreferences(from favourite: Favourite) {
        guard let session = sessionsByKind[.favourite(favourite.id)] else { return }
        session.reloadsOnFocus = favourite.resolvedReloadsOnFocus
        session.setUserAgentMode(favourite.resolvedUserAgentMode)
    }

    /// Frees a session's `WKWebView`, e.g. when a favourite is removed or
    /// the user asks to close a session to reclaim memory.
    func closeSession(kind: SessionKind) {
        guard let session = sessionsByKind.removeValue(forKey: kind) else { return }
        sessions.removeAll { $0.id == kind }
        session.webView.stopLoading()
        session.webView.removeFromSuperview()
        if activeSessionID == kind {
            activeSessionID = nil
        }
    }

    /// Releases every live web view. Sessions are recreated lazily the next
    /// time a site is opened, so this is the "reclaim memory now" action.
    func closeAllSessions() {
        // Snapshot the keys: `closeSession` mutates the dictionary.
        for kind in Array(sessionsByKind.keys) {
            closeSession(kind: kind)
        }
    }

    /// Clears caches only, keeping cookies (and therefore sign-ins) intact.
    func clearCaches() async {
        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache,
            WKWebsiteDataTypeFetchCache
        ]
        await dataStore.removeData(ofTypes: types, modifiedSince: .distantPast)
    }

    /// Clears everything WebKit stores for this app, including cookies, so
    /// the user is signed out of every site.
    func clearAllWebsiteData() async {
        await dataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
    }

    private func makeSession(kind: SessionKind, userAgentMode: UserAgentMode) -> WebSession {
        WebSession(kind: kind, dataStore: dataStore, userAgentMode: userAgentMode)
    }

    private func register(_ session: WebSession) {
        sessionsByKind[session.id] = session
        sessions.append(session)
    }
}
