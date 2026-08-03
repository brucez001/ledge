import AppKit

/// Wraps the SwiftUI content view so the windowing layer can observe raw
/// mouse enter/exit for the whole panel (used to drive auto-hide) without
/// requiring the UI layer to know anything about it.
final class PanelHostView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    /// The panel uses `.fullSizeContentView`, so its content is drawn under a
    /// transparent title bar whose region AppKit would otherwise treat as a
    /// window-drag area. Refusing that here keeps drags inside the content --
    /// reordering a site, selecting text on a page -- from moving the window.
    override var mouseDownCanMoveWindow: Bool { false }

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    /// Embeds `child` filling the full bounds via Auto Layout.
    func embed(_ child: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: leadingAnchor),
            child.trailingAnchor.constraint(equalTo: trailingAnchor),
            child.topAnchor.constraint(equalTo: topAnchor),
            child.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
