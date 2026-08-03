import AppKit

/// Geometry helpers for deciding *where* a slide-over can actually be
/// revealed from.
///
/// A display's own `frame.minX`/`maxX` is not necessarily somewhere the user
/// can push the pointer against. On a multi-display desktop, the left edge of
/// a screen that has another screen immediately to its left is an interior
/// *seam*: the cursor slides straight across it, so there is nothing to hover.
/// Arming a hot edge there means the panel simply never appears, and parking
/// the hidden panel just beyond it puts the panel on top of the neighbouring
/// display instead of off-screen.
enum ScreenEdge {
    // MARK: - Pure geometry (unit-tested against real display layouts)

    /// `true` when `side` of `frame` lies on the outer boundary of the desktop
    /// described by `frames`, i.e. no other display adjoins it.
    ///
    /// Deliberately conservative: if *any* part of the edge is covered by a
    /// neighbour, the edge counts as unexposed. A partially hoverable edge
    /// would be unpredictable, which is worse than not offering it.
    static func isExposed(_ side: DockSide, of frame: CGRect, among frames: [CGRect]) -> Bool {
        let probe: CGRect
        switch side {
        case .left:
            probe = CGRect(x: frame.minX - 2, y: frame.minY, width: 1, height: frame.height)
        case .right:
            probe = CGRect(x: frame.maxX + 1, y: frame.minY, width: 1, height: frame.height)
        }
        return !frames.contains { other in
            other != frame && other.intersects(probe)
        }
    }

    static func framesWithExposedEdge(_ side: DockSide, among frames: [CGRect]) -> [CGRect] {
        frames.filter { isExposed(side, of: $0, among: frames) }
    }

    /// The union of every display, used to park a hidden panel genuinely off
    /// the desktop rather than merely off one display.
    static func desktopBounds(among frames: [CGRect]) -> CGRect {
        frames.reduce(CGRect.null) { $0.union($1) }
    }

    // MARK: - NSScreen convenience

    static func isExposed(_ side: DockSide, of screen: NSScreen, among screens: [NSScreen] = NSScreen.screens) -> Bool {
        isExposed(side, of: screen.frame, among: screens.map(\.frame))
    }

    /// Every screen whose `side` edge the user can actually hover.
    static func screensWithExposedEdge(_ side: DockSide, among screens: [NSScreen] = NSScreen.screens) -> [NSScreen] {
        let frames = screens.map(\.frame)
        return screens.filter { isExposed(side, of: $0.frame, among: frames) }
    }

    static func desktopBounds(among screens: [NSScreen] = NSScreen.screens) -> NSRect {
        desktopBounds(among: screens.map(\.frame))
    }

    /// The screen currently under `point`, if any.
    static func screen(containing point: NSPoint, among screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    // MARK: - Toolbar reveal band

    /// Distance from the panel's top edge that arms the floating browser
    /// toolbar, and the wider distance that keeps it armed.
    static let toolbarRevealBand: CGFloat = 24
    static let toolbarKeepRevealedBand: CGFloat = 96

    /// Whether the pointer counts as "near the top of the panel".
    ///
    /// Hysteresis on purpose: a tight band arms the reveal so the toolbar does
    /// not appear while reading, and a wider band keeps it armed once shown.
    /// Without the wider band the pointer resting on the revealed toolbar --
    /// which is taller than the trigger band -- would flicker it away again.
    static func isPointerNearTop(_ pointer: NSPoint, panelFrame: CGRect, wasNear: Bool) -> Bool {
        guard panelFrame.contains(pointer) else { return false }
        let band = wasNear ? toolbarKeepRevealedBand : toolbarRevealBand
        return (panelFrame.maxY - pointer.y) <= band
    }
}
