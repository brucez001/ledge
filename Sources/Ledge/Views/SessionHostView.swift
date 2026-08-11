import AppKit
import SwiftUI

/// Hosts every live session's `WKWebView` in a single container, adding
/// each one to the view hierarchy exactly once and thereafter only toggling
/// `isHidden` to switch the visible session. This is what lets sessions
/// survive collapsing/switching without ever being destroyed or re-attached.
struct SessionHostView: NSViewRepresentable {
    @ObservedObject var sessionManager: SessionManager
    /// Height of the hover-sensitive strip along the top of the web content.
    /// Zero disables it.
    var topHoverHeight: CGFloat = 0
    var onTopHoverChange: ((Bool) -> Void)?

    func makeNSView(context: Context) -> SessionHostContainerView {
        SessionHostContainerView()
    }

    func updateNSView(_ nsView: SessionHostContainerView, context: Context) {
        nsView.onTopHoverChange = onTopHoverChange
        nsView.setTopHoverHeight(topHoverHeight)
        nsView.apply(sessions: sessionManager.sessions, activeID: sessionManager.activeSessionID)
    }
}

final class SessionHostContainerView: NSView {
    private var installedWebViews: [SessionKind: NSView] = [:]

    /// Reports the pointer entering/leaving a strip along the top edge, used
    /// to reveal the browser toolbar on demand.
    ///
    /// This lives on the container rather than on a SwiftUI overlay because a
    /// `WKWebView` is a real `NSView` that swallows mouse events over its own
    /// area. A tracking area on an ancestor still fires even when a subview
    /// covers it (the same reason `PanelHostView`'s panel-wide tracking works
    /// through the web view), so this is the reliable place for it.
    var onTopHoverChange: ((Bool) -> Void)?

    private var topHoverHeight: CGFloat = 0
    private var topHoverArea: NSTrackingArea?

    func setTopHoverHeight(_ height: CGFloat) {
        guard height != topHoverHeight else { return }
        topHoverHeight = height
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let topHoverArea {
            removeTrackingArea(topHoverArea)
            self.topHoverArea = nil
        }
        guard topHoverHeight > 0, bounds.width > 0, bounds.height > 0 else { return }
        // Not `.inVisibleRect`: that option ignores the supplied rect and
        // tracks the whole visible area, which would fire for the entire page.
        let rect = NSRect(
            x: bounds.minX,
            y: bounds.maxY - min(topHoverHeight, bounds.height),
            width: bounds.width,
            height: min(topHoverHeight, bounds.height)
        )
        let area = NSTrackingArea(
            rect: rect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        topHoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onTopHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onTopHoverChange?(false)
    }

    func apply(sessions: [WebSession], activeID: SessionKind?) {
        var current: [SessionKind: NSView] = [:]

        for session in sessions {
            let webView = session.webView
            if webView.superview !== self {
                webView.translatesAutoresizingMaskIntoConstraints = false
                addSubview(webView)
                NSLayoutConstraint.activate([
                    webView.leadingAnchor.constraint(equalTo: leadingAnchor),
                    webView.trailingAnchor.constraint(equalTo: trailingAnchor),
                    webView.topAnchor.constraint(equalTo: topAnchor),
                    webView.bottomAnchor.constraint(equalTo: bottomAnchor)
                ])
            }
            webView.isHidden = session.id != activeID
            current[session.id] = webView
        }

        // Removal is decided by *view identity*, not by key. A session can be
        // re-filed under a new `SessionKind` while keeping its web view (when a
        // Home favourite is added or removed), and a key-based sweep would tear that
        // web view out of the hierarchy -- breaking the invariant that a live
        // session is never unmounted.
        let liveViews = Set(sessions.map { ObjectIdentifier($0.webView) })
        for view in installedWebViews.values where !liveViews.contains(ObjectIdentifier(view)) {
            view.removeFromSuperview()
        }
        installedWebViews = current
    }
}
