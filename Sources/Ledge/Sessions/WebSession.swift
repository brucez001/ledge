import AppKit
import WebKit

/// One persistent, live `WKWebView`. It may be associated with a Home
/// favourite, but every open session has the same lifetime and behaviour.
/// Switching away only hides it (see `SessionHostView`).
@MainActor
// Deliberately not `Identifiable`: nothing iterates sessions in a `ForEach`,
// and the protocol's `id` requirement is nonisolated, which a mutable
// main-actor property cannot satisfy. `id` has to be mutable so a tab can be
// associated with a Home favourite without rebuilding it (see `adopt`).
final class WebSession: NSObject, ObservableObject {
    /// Zoom steps offered by ⌘+ / ⌘- so a cramped panel can still show a
    /// desktop layout comfortably.
    static let zoomSteps: [Double] = [0.5, 0.67, 0.75, 0.85, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0]

    /// Not `let`: adding or removing a Home favourite changes the session's
    /// association without rebuilding its web view.
    private(set) var id: SessionKind
    let webView: WKWebView

    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentURL: URL?
    @Published var pageTitle: String = ""
    @Published var isLoading = false
    @Published var estimatedProgress: Double = 0
    /// Human-readable description of the last navigation failure, cleared as
    /// soon as a new navigation starts. Drives the inline error banner.
    @Published var loadErrorMessage: String?
    @Published private(set) var zoom: Double = 1.0
    /// Most recent find-in-page match count, for the find bar's counter.
    @Published var lastFindMatched: Bool?
    /// Destination of the most recently completed download, published only
    /// so a future UI can surface it cheaply; nothing reads it today.
    @Published private(set) var lastDownloadURL: URL?

    /// Host to cache this session's icon under. A favourite-launched session
    /// uses the shortcut's host so redirects do not lose its icon.
    var iconHost: String?

    private var progressObserver: NSKeyValueObservation?
    private var titleObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?
    private var canGoBackObserver: NSKeyValueObservation?
    private var canGoForwardObserver: NSKeyValueObservation?

    /// In-flight find-in-page search, retained so a new search can cancel
    /// whichever one is still running instead of letting both race to
    /// publish `lastFindMatched`.
    private var findTask: Task<Void, Never>?
    private var iconDiscoveryTask: Task<Void, Never>?
    /// Bumped on every `find`/`clearFind` call; a result is only published
    /// if this has not moved on since the search that produced it started.
    private var findGeneration = 0
    /// Chosen destination for each in-flight `WKDownload`, keyed by object
    /// identity so overlapping downloads do not clobber one another.
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]

    init(
        kind: SessionKind,
        dataStore: WKWebsiteDataStore
    ) {
        self.id = kind

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // Safari-compatible UA so Google/Meta-style sign-in flows do not
        // reject the embedded view as an unsupported browser.
        configuration.applicationNameForUserAgent = "Version/17.4 Safari/605.1.15"
        configuration.allowsAirPlayForMediaPlayback = true
        // Element full screen powers both full-screen video and the
        // Picture-in-Picture control inside embedded players.
        configuration.preferences.isElementFullscreenEnabled = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        // Keeps the area around a short page in step with the panel instead
        // of flashing plain white inside a dark surface.
        webView.underPageBackgroundColor = .clear
        self.webView = webView

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        progressObserver = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] observedWebView, _ in
            MainActor.assumeIsolated {
                self?.estimatedProgress = observedWebView.estimatedProgress
            }
        }
        // Single-page apps change title/URL without a navigation delegate
        // callback, so observe them directly to keep the toolbar honest.
        titleObserver = webView.observe(\.title, options: [.new]) { [weak self] observedWebView, _ in
            MainActor.assumeIsolated {
                guard let title = observedWebView.title, !title.isEmpty else { return }
                self?.pageTitle = title
            }
        }
        urlObserver = webView.observe(\.url, options: [.new]) { [weak self] observedWebView, _ in
            MainActor.assumeIsolated {
                guard let url = observedWebView.url else { return }
                self?.currentURL = url
            }
        }
        // `syncNavigationState()` still runs from the navigation-delegate
        // callbacks below, but single-page apps flip back/forward
        // eligibility via `pushState`/`replaceState` without invoking any
        // of them, so KVO is the only reliable signal for those cases.
        canGoBackObserver = webView.observe(\.canGoBack, options: [.new]) { [weak self] observedWebView, _ in
            MainActor.assumeIsolated {
                self?.canGoBack = observedWebView.canGoBack
            }
        }
        canGoForwardObserver = webView.observe(\.canGoForward, options: [.new]) { [weak self] observedWebView, _ in
            MainActor.assumeIsolated {
                self?.canGoForward = observedWebView.canGoForward
            }
        }
    }

    deinit {
        // KVO observations are invalidated deterministically here rather
        // than relying on `NSKeyValueObservation`'s own dealloc-time
        // invalidation, and the find task is cancelled so it cannot fire
        // into a session that is going away.
        progressObserver?.invalidate()
        titleObserver?.invalidate()
        urlObserver?.invalidate()
        canGoBackObserver?.invalidate()
        canGoForwardObserver?.invalidate()
        findTask?.cancel()
        iconDiscoveryTask?.cancel()
    }

    // MARK: - Loading and navigation

    func load(_ url: URL) {
        loadErrorMessage = nil
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    /// Takes on a new identity, keeping the live web view. Only
    /// `SessionManager` should call this, so its lookup table stays in step.
    func adopt(_ kind: SessionKind) {
        id = kind
    }

    /// Single control backing the reload/stop toggle in the browser toolbar.
    func reloadOrStop() {
        if isLoading {
            webView.stopLoading()
        } else {
            reload()
        }
    }

    func reload() {
        loadErrorMessage = nil
        if webView.url == nil {
            webView.reloadFromOrigin()
        } else {
            webView.reload()
        }
    }

    /// `true` when the current page came over a secure transport, used for
    /// the lock glyph in the address field.
    var isSecure: Bool {
        currentURL?.scheme?.lowercased() == "https"
    }

    /// Host without a `www.` prefix, shown instead of a raw URL when the
    /// address field is not being edited.
    var displayHost: String {
        guard let host = currentURL?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: - Zoom

    func zoomIn() { applyZoom(step: 1) }
    func zoomOut() { applyZoom(step: -1) }

    func resetZoom() {
        zoom = 1
        webView.pageZoom = 1
    }

    private func applyZoom(step: Int) {
        let steps = Self.zoomSteps
        let currentIndex = steps.enumerated().min {
            abs($0.element - zoom) < abs($1.element - zoom)
        }?.offset ?? steps.firstIndex(of: 1.0) ?? 0
        let nextIndex = min(max(currentIndex + step, 0), steps.count - 1)
        zoom = steps[nextIndex]
        webView.pageZoom = zoom
    }

    // MARK: - Find in page

    func find(_ text: String, forward: Bool = true) {
        // Cancel whatever search is still in flight before starting a new
        // one, and bump the generation so a late result from it cannot be
        // mistaken for the answer to this query.
        findTask?.cancel()
        findGeneration += 1
        let generation = findGeneration
        guard !text.isEmpty else {
            lastFindMatched = nil
            return
        }
        let configuration = WKFindConfiguration()
        configuration.backwards = !forward
        configuration.caseSensitive = false
        configuration.wraps = true
        findTask = Task { [weak self] in
            guard let self,
                  let result = try? await self.webView.find(text, configuration: configuration) else { return }
            // The generation check discards a result from a search that has
            // since been superseded by a newer one (or cleared).
            guard !Task.isCancelled, self.findGeneration == generation else { return }
            self.lastFindMatched = result.matchFound
        }
    }

    func clearFind() {
        findTask?.cancel()
        findGeneration += 1
        lastFindMatched = nil
        // Collapsing the selection removes WebKit's find highlight.
        Task { [webView] in
            _ = try? await webView.evaluateJavaScript("window.getSelection().removeAllRanges()")
        }
    }

    // MARK: - Media

    func pauseMedia() {
        Task { await webView.pauseAllMediaPlayback() }
    }

    // MARK: - Icon discovery

    /// Reads the icon the page declares for itself and hands it to
    /// `FaviconStore`.
    ///
    /// Runs inside the web view on purpose. `fetch` there carries the page's
    /// own cookies, so this works for sites behind a login — which guessing
    /// `https://host/favicon.ico` from a bare `URLSession` cannot do — and it
    /// finds icons at the hashed paths that bundlers emit, which no fixed list
    /// of guesses will ever contain.
    private func discoverDeclaredIcon() {
        let host = iconHost ?? displayHost
        guard !host.isEmpty else { return }

        iconDiscoveryTask?.cancel()
        iconDiscoveryTask = Task { [weak self] in
            guard let self else { return }
            guard let base64 = try? await self.webView.callAsyncJavaScript(
                Self.iconDiscoveryScript,
                arguments: [:],
                in: nil,
                contentWorld: .defaultClient
            ) as? String,
                  let data = Data(base64Encoded: base64),
                  !Task.isCancelled else { return }
            FaviconStore.shared.storeDeclaredIcon(data, for: host)
        }
    }

    /// Finds the icon the page declares and returns it as base64 PNG.
    ///
    /// It rasterises through a `<canvas>` rather than returning the original
    /// bytes, because WebKit is the only thing here that renders every format
    /// a site might declare. `NSImage` will happily *decode* an SVG and then
    /// draw almost nothing of it -- an inline `data:image/svg+xml` icon whose
    /// artwork is an emoji glyph rasterises to a near-empty tile. Letting the
    /// page draw it and handing back PNG avoids the whole problem, and picks
    /// up ICO and data URIs for free.
    ///
    /// A canvas holding a cross-origin image is tainted and cannot be read
    /// back, so that case falls through to the original bytes; and anything
    /// that rasterises to nearly nothing is rejected so the caller shows a
    /// letter tile instead of an apparently-broken icon.
    private static let iconDiscoveryScript = """
    const rels = ['icon', 'shortcut', 'apple-touch-icon', 'apple-touch-icon-precomposed'];
    const declared = Array.from(document.querySelectorAll('link[rel][href]')).filter(link => {
        const parts = (link.getAttribute('rel') || '').toLowerCase().split(/\\s+/);
        return parts.some(part => rels.includes(part));
    });

    const score = (link) => {
        const sizes = (link.getAttribute('sizes') || '').toLowerCase();
        const largest = Math.max(0, ...sizes.split(/\\s+/).map(s => parseInt(s, 10) || 0));
        const rel = (link.getAttribute('rel') || '').toLowerCase();
        // A declared size wins; failing that, apple-touch-icon is usually the
        // highest-resolution artwork a site ships.
        return largest > 0 ? largest : (rel.includes('apple-touch-icon') ? 180 : 32);
    };
    declared.sort((a, b) => score(b) - score(a));

    const candidates = declared.map(link => link.href);
    try { candidates.push(new URL('/favicon.ico', location.href).href); } catch (error) {}
    if (candidates.length === 0) { return null; }

    const SIZE = 64;
    const MIN_PAINTED = SIZE * SIZE * 0.02;

    const rasterise = (src, anonymous) => new Promise((resolve) => {
        const image = new Image();
        // Icons are usually served from a CDN on another origin, which taints
        // the canvas and makes `getImageData` throw. Requesting the image as a
        // CORS fetch avoids that, and the CDNs sites use for their icons
        // generally answer with the requesting origin reflected back. Hosts
        // that send no CORS headers fail this attempt outright, so the caller
        // retries without it for the same-origin case.
        if (anonymous) { image.crossOrigin = 'anonymous'; }
        image.onload = () => {
            try {
                const canvas = document.createElement('canvas');
                canvas.width = SIZE;
                canvas.height = SIZE;
                const context = canvas.getContext('2d');
                context.clearRect(0, 0, SIZE, SIZE);
                context.drawImage(image, 0, 0, SIZE, SIZE);
                const pixels = context.getImageData(0, 0, SIZE, SIZE).data;
                let painted = 0;
                for (let i = 3; i < pixels.length; i += 4) {
                    if (pixels[i] > 12) { painted++; }
                }
                if (painted < MIN_PAINTED) { resolve(null); return; }
                resolve(canvas.toDataURL('image/png').split(',')[1] || null);
            } catch (error) {
                resolve(null);
            }
        };
        image.onerror = () => resolve(null);
        image.src = src;
    });

    const rawBytes = async (src, credentials) => {
        try {
            const response = await fetch(src, { credentials });
            if (!response.ok) { return null; }
            const buffer = await response.arrayBuffer();
            if (buffer.byteLength === 0 || buffer.byteLength > 524288) { return null; }
            const bytes = new Uint8Array(buffer);
            let binary = '';
            for (let i = 0; i < bytes.length; i++) { binary += String.fromCharCode(bytes[i]); }
            return btoa(binary);
        } catch (error) {
            return null;
        }
    };

    const discover = async () => {
        for (const src of candidates) {
            const png = (await rasterise(src, true)) || (await rasterise(src, false));
            if (png) { return png; }
        }
        for (const src of candidates) {
            // Credentials first, because an internal site's icon can sit
            // behind its login; a cross-origin CDN rejects that (it allows the
            // origin but not credentials) and is retried without them.
            const raw = (await rawBytes(src, 'include')) || (await rawBytes(src, 'omit'));
            if (raw) { return raw; }
        }
        return null;
    };

    // A hung image or fetch must not leave the caller awaiting for ever.
    const timeout = new Promise((resolve) => setTimeout(() => resolve(null), 4000));
    return await Promise.race([discover(), timeout]);
    """

    // MARK: - Sharing

    func copyCurrentURL() {
        guard let url = currentURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func openInDefaultBrowser() {
        guard let url = currentURL, !url.isFileURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func syncNavigationState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

// MARK: - WKNavigationDelegate

extension WebSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        currentURL = webView.url ?? currentURL
        isLoading = true
        loadErrorMessage = nil
        syncNavigationState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        currentURL = webView.url ?? currentURL
        pageTitle = webView.title ?? pageTitle
        syncNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        currentURL = webView.url ?? currentURL
        pageTitle = webView.title ?? pageTitle
        isLoading = false
        estimatedProgress = 1
        syncNavigationState()
        discoverDeclaredIcon()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        record(error)
        syncNavigationState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        record(error)
        syncNavigationState()
    }

    /// Content the panel cannot render (installers, archives, attachments
    /// served with a download disposition) becomes a `WKDownload` instead of
    /// being handed to the default browser: routing it through
    /// `NSWorkspace` would start a brand-new, unauthenticated request and
    /// lose this app's WebKit cookies and any POST context the original
    /// request carried.
    ///
    /// The `async` form of each delegate method is used deliberately: the
    /// completion-handler variants take `@MainActor` blocks, and a plain
    /// `@escaping` closure only "nearly matches" them, which silently means
    /// the method is never called.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        guard !navigationResponse.canShowMIMEType else { return .allow }
        return .download
    }

    /// Non-web schemes (mailto:, tel:, zoommtg:, slack:, …) belong to other
    /// apps; hand them off rather than showing an "unsupported URL" error.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              !["http", "https", "file", "about", "blob", "data"].contains(scheme) else {
            return .allow
        }
        NSWorkspace.shared.open(url)
        return .cancel
    }

    /// WebKit calls one of these two `didBecome` methods immediately after
    /// a `decidePolicyFor` above returns `.download`; either way the fix is
    /// the same, attach this session as the `WKDownloadDelegate` so the
    /// destination/completion/failure callbacks below actually run.
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    private func record(_ error: Error) {
        let nsError = error as NSError
        // A cancelled load is what `stopLoading()` and in-flight redirects
        // produce; surfacing it as a failure would be noise.
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled),
              nsError.code != 102 else { return }
        loadErrorMessage = nsError.localizedDescription
    }
}

// MARK: - WKUIDelegate

extension WebSession: WKUIDelegate {
    /// `target=_blank` links and `window.open()` popups load in the current
    /// session's web view rather than being silently dropped or spawning a
    /// detached window.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Load the original request as-is (not a rebuilt `URLRequest(url:)`)
        // so POST bodies and headers survive -- OAuth, payment, and form
        // submissions that open in a new window depend on this.
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // JavaScript dialogs are silently dropped unless the host implements
    // them, which breaks confirmation flows in real web apps.

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async {
        let alert = makeAlert(message: message)
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async -> Bool {
        let alert = makeAlert(message: message)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        let alert = makeAlert(message: prompt)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field

        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// Lets sites that ask for the camera/microphone (video calls, voice
    /// notes) prompt through the normal macOS permission sheet.
    func webView(
        _ webView: WKWebView,
        decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo,
        type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
        .prompt
    }

    private func makeAlert(message: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = displayHost.isEmpty ? "Website" : displayHost
        alert.informativeText = message
        return alert
    }
}

// MARK: - WKDownloadDelegate

extension WebSession: WKDownloadDelegate {
    /// Chooses where a download lands: the user's Downloads folder (falling
    /// back to `/tmp` on the rare system without one), never overwriting an
    /// existing file. Returning `nil` cancels the download outright, which
    /// is also how an unusable (empty) suggested filename is rejected.
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        guard let destination = Self.uniqueDownloadDestination(suggestedFilename: suggestedFilename) else {
            return nil
        }
        downloadDestinations[ObjectIdentifier(download)] = destination
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        lastDownloadURL = url
        // Reveals the finished file instead of leaving the user to guess
        // where it landed -- there is no download UI of our own yet.
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        loadErrorMessage = (error as NSError).localizedDescription
    }

    /// Strips path separators and surrounding whitespace from a
    /// server-suggested filename; a name that becomes empty is treated as
    /// unusable rather than guessed at.
    private static func sanitizedFilename(_ suggested: String) -> String {
        let disallowed = CharacterSet(charactersIn: "/\\:")
        return suggested
            .components(separatedBy: disallowed)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Finds a non-clobbering destination in the Downloads folder, adding
    /// " 2", " 3", … before the extension the same way Finder does when a
    /// name is already taken.
    private static func uniqueDownloadDestination(suggestedFilename: String) -> URL? {
        let name = sanitizedFilename(suggestedFilename)
        guard !name.isEmpty else { return nil }

        let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let baseURL = directory.appendingPathComponent(name)
        let stem = baseURL.deletingPathExtension().lastPathComponent
        let ext = baseURL.pathExtension

        var candidate = baseURL
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let disambiguated = ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
            candidate = directory.appendingPathComponent(disambiguated)
            suffix += 1
        }
        return candidate
    }
}
