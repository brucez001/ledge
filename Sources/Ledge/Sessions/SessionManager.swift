import WebKit

/// Owns the currently open `WKWebView`-backed sessions.
///
/// Every session has the same lifetime: it remains alive while the user
/// switches away or hides the panel, and is destroyed only when explicitly
/// closed. A session may be associated with a Home favourite, but favourites
/// themselves do not own or restore sessions.
@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var sessions: [WebSession] = []
    /// Assign through `setActiveSession(_:)` rather than directly.
    @Published private(set) var activeSessionID: SessionKind?

    private let dataStore = WKWebsiteDataStore.default()
    private var sessionsByKind: [SessionKind: WebSession] = [:]

    /// Returns the favourite's existing open session, or creates one.
    @discardableResult
    func session(forFavourite favourite: Favourite) -> WebSession {
        let kind = SessionKind.favourite(favourite.id)
        if let existing = sessionsByKind[kind] {
            return existing
        }
        let session = makeSession(kind: kind)
        // Cache any icon this site declares under the favourite's own host, so
        // the rail item finds it even if the site redirects elsewhere to sign
        // the user in.
        session.iconHost = favourite.host
        session.load(favourite.url)
        register(session)
        return session
    }

    /// Creates a fresh ordinary session.
    @discardableResult
    func newTabSession() -> WebSession {
        let session = makeSession(kind: .tab(UUID()))
        register(session)
        return session
    }

    /// Ordinary tabs in their current rail order.
    var tabSessions: [WebSession] {
        sessions.filter { $0.id.tabID != nil }
    }

    /// Every live session in rail order. In-memory only.
    var sessionOrder: [SessionKind] {
        sessions.map(\.id)
    }

    /// Reorders all live sessions after validating a true permutation.
    func setSessionOrder(_ order: [SessionKind]) {
        let current = sessionOrder
        let reordered = order.filter { sessionsByKind[$0] != nil }
        guard Set(reordered) == Set(current), reordered.count == current.count else { return }
        guard reordered != current else { return }
        sessions = reordered.compactMap { sessionsByKind[$0] }
    }

    /// Re-files a live session under a new identity, keeping its web view.
    ///
    /// Adding or removing a Home favourite only changes this association. The
    /// page, scroll position, form state, rail position, and behaviour remain.
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

    /// Switches the visible session. Sessions keep running while hidden, so
    /// nothing is torn down, paused, or reloaded here.
    func setActiveSession(_ kind: SessionKind?) {
        guard kind != activeSessionID else { return }
        activeSessionID = kind
    }

    /// Frees a session's `WKWebView` when the user closes its rail row.
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

    private func makeSession(kind: SessionKind) -> WebSession {
        WebSession(kind: kind, dataStore: dataStore)
    }

    private func register(_ session: WebSession) {
        sessionsByKind[session.id] = session
        sessions.append(session)
    }
}
