import AppKit

/// One or more transparent, two-point non-activating windows that sit at a
/// chosen display edge while Ledge is hidden. Their tracking areas give
/// the slide-over a real AppKit mouse-enter/exit trigger instead of relying
/// on polling or focus changes -- one panel per screen, because "follow
/// mouse display" needs every display's edge covered, not just the docked
/// one (see `PanelController.updateEdgeTrigger`).
///
/// The strips are *nearly* transparent rather than fully clear on purpose: a
/// window whose pixels are completely transparent is commonly treated as
/// click-through, and then its tracking areas never receive mouse-entered at
/// all. One percent alpha over a few points is invisible in practice but
/// keeps the window hit-testable. Even so, this is only one of the reveal
/// sources -- `PanelController` also polls the pointer -- because the exact
/// behaviour varies between macOS releases.
@MainActor
final class EdgeTriggerController {
    /// Wide enough that a fast cursor cannot step straight over it between
    /// two mouse samples, narrow enough to stay out of the way.
    private static let stripWidth: CGFloat = 4

    private var panels: [EdgeTriggerPanel] = []
    private let onEnter: (NSScreen) -> Void
    private let onExit: (NSScreen) -> Void

    init(onEnter: @escaping (NSScreen) -> Void, onExit: @escaping (NSScreen) -> Void) {
        self.onEnter = onEnter
        self.onExit = onExit
    }

    /// Replaces whatever strips are currently showing with one per screen
    /// in `screens`, all pinned to the same docked `side`.
    func show(on screens: [NSScreen], side: DockSide) {
        hide()
        panels = screens.map { screen in
            let trackingView = EdgeTriggerView(frame: .zero)
            trackingView.onMouseEntered = { [onEnter] in onEnter(screen) }
            trackingView.onMouseExited = { [onExit] in onExit(screen) }

            let panel = EdgeTriggerPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = trackingView
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = NSColor.black.withAlphaComponent(0.01)
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = false

            let frame = screen.frame
            let width = Self.stripWidth
            let x = side == .left ? frame.minX : frame.maxX - width
            panel.setFrame(NSRect(x: x, y: frame.minY, width: width, height: frame.height), display: false)
            panel.orderFrontRegardless()
            return panel
        }
    }

    func hide() {
        for panel in panels { panel.orderOut(nil) }
        panels = []
    }
}

private final class EdgeTriggerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class EdgeTriggerView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}
