import AppKit

/// The menu-bar glyph for the status item: a docked panel with a curl of
/// light spilling out from underneath it, echoing `Assets/AppIcon.svg`'s
/// "lit ledge" motif at status-item scale.
///
/// This is drawn procedurally with Core Graphics rather than rasterising the
/// SVG, so the status item stays dependency-free -- no bundled PDF/PNG asset
/// and no SVG parser, just the two shapes from the app icon redrawn at their
/// own coordinates.
enum LedgeMarkImage {
    /// Point size the glyph is authored at. `NSStatusItem` scales this to
    /// whatever the menu bar actually needs, but Retina rendering still goes
    /// through the same drawing closure at the higher backing scale, so
    /// hairlines stay crisp rather than being upscaled from a small bitmap.
    private static let canvasSize = NSSize(width: 18, height: 18)

    /// Builds the template image for the status item, docked to `dockSide`.
    ///
    /// The image itself has no notion of dock side changing later -- callers
    /// (`StatusItemController`) must call this again and re-assign
    /// `button.image` whenever `PanelController.dockSide` changes.
    static func make(dockSide: DockSide) -> NSImage {
        let image = NSImage(size: canvasSize, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }

            // The geometry below is authored for a panel docked left. Rather
            // than maintaining a second, separately-mirrored copy of the same
            // maths for `.right`, flip the canvas horizontally and draw the
            // same shapes -- the panel and its ledge end up on the opposite
            // edge, facing the opposite way, exactly as the real panel does.
            if dockSide == .right {
                context.translateBy(x: rect.width, y: 0)
                context.scaleBy(x: -1, y: 1)
            }

            drawMark(in: rect, context: context)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Ledge"
        return image
    }

    // MARK: - Geometry

    // `Assets/AppIcon.svg`'s artwork sits on an 824x824 square inset by 100pt
    // inside its 1024x1024 tile. Coordinates below are copied straight from
    // that file's panel `<rect>` and ledge `<path>` so the two stay in sync
    // by construction rather than by a separately eyeballed redraw.
    private static let artworkOrigin: CGFloat = 100
    private static let artworkSide: CGFloat = 824

    /// Maps an absolute SVG coordinate onto a point inside `rect`.
    private static func point(_ x: CGFloat, _ y: CGFloat, in rect: NSRect) -> CGPoint {
        CGPoint(
            x: rect.minX + (x - artworkOrigin) / artworkSide * rect.width,
            y: rect.minY + (y - artworkOrigin) / artworkSide * rect.height
        )
    }

    /// Maps an SVG length (a width, radius or stroke weight, as opposed to a
    /// coordinate) onto a length inside `rect`. `rect` is square, so a single
    /// scale factor serves both axes.
    private static func length(_ value: CGFloat, in rect: NSRect) -> CGFloat {
        value / artworkSide * rect.width
    }

    /// Draws the panel outline and its ledge, docked to the left of `rect`.
    ///
    /// Keeping the panel hollow is important: the app icon is a glass panel
    /// resting inside a heavier L-shaped ledge. Filling the panel turned the
    /// mark into an unrelated solid block at menu-bar size. `isTemplate` on
    /// the returned image means macOS re-tints these strokes for the current
    /// menu-bar appearance and highlight state.
    private static func drawMark(in rect: NSRect, context: CGContext) {
        NSColor.black.setStroke()

        // Panel: SVG `<rect x="212" y="218" width="344" height="494" rx="40">`.
        let panelRect = CGRect(
            origin: point(212, 218, in: rect),
            size: CGSize(width: length(344, in: rect), height: length(494, in: rect))
        )
        let panelPath = CGPath(
            roundedRect: panelRect,
            cornerWidth: length(40, in: rect),
            cornerHeight: length(40, in: rect),
            transform: nil
        )
        context.addPath(panelPath)
        // The SVG uses a fine white glass border. A 46pt source stroke maps
        // to almost exactly one point here: enough to survive at 18pt without
        // competing with the heavier ledge.
        context.setLineWidth(length(46, in: rect))
        context.strokePath()

        // Ledge: SVG `<path d="M212 236V664C212 717 255 760 308 760H800">`,
        // the boldest of the icon's four stacked glow strokes -- the others
        // exist only to fake a soft falloff at icon scale, which a 1-bit
        // template mask cannot represent anyway.
        let ledgePath = CGMutablePath()
        ledgePath.move(to: point(212, 236, in: rect))
        ledgePath.addLine(to: point(212, 664, in: rect))
        ledgePath.addCurve(
            to: point(308, 760, in: rect),
            control1: point(212, 717, in: rect),
            control2: point(255, 760, in: rect)
        )
        ledgePath.addLine(to: point(800, 760, in: rect))

        context.addPath(ledgePath)
        context.setLineWidth(length(96, in: rect))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }
}
