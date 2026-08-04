import AppKit
import SwiftUI

/// Semantic colour tokens for the panel.
///
/// Every token is a dynamic `NSColor`, so the whole surface follows the
/// effective appearance of the panel (which `Preferences.appearance` can pin
/// to light or dark). Views should never hard-code raw greys.
enum Theme {
    /// Main content background behind the home grid and browser chrome.
    static let canvas = dynamic(
        light: NSColor(calibratedWhite: 0.945, alpha: 1),
        dark: NSColor(calibratedRed: 0.106, green: 0.110, blue: 0.125, alpha: 1)
    )

    /// The narrow dock rail beside the content.
    static let rail = dynamic(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.55),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.06)
    )

    /// Toolbar / omnibox chrome sitting on top of `canvas`.
    static let chrome = dynamic(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.72),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.08)
    )

    /// Raised surfaces: favourite tiles, capsule fields.
    static let card = dynamic(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.86),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.10)
    )

    static let cardHover = dynamic(
        light: NSColor(calibratedWhite: 1.0, alpha: 1.0),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.16)
    )

    /// Primary text.
    static let ink = dynamic(
        light: NSColor(calibratedWhite: 0.09, alpha: 1),
        dark: NSColor(calibratedWhite: 0.96, alpha: 1)
    )

    static let inkSecondary = dynamic(
        light: NSColor(calibratedWhite: 0.09, alpha: 0.62),
        dark: NSColor(calibratedWhite: 0.96, alpha: 0.62)
    )

    static let inkTertiary = dynamic(
        light: NSColor(calibratedWhite: 0.09, alpha: 0.38),
        dark: NSColor(calibratedWhite: 0.96, alpha: 0.38)
    )

    /// Hairline separators and the panel's outer edge highlight.
    static let hairline = dynamic(
        light: NSColor(calibratedWhite: 0, alpha: 0.10),
        dark: NSColor(calibratedWhite: 1, alpha: 0.12)
    )

    static let panelBorder = dynamic(
        light: NSColor(calibratedWhite: 1, alpha: 0.65),
        dark: NSColor(calibratedWhite: 1, alpha: 0.14)
    )

    /// Subtle fill for hover/pressed feedback on icon-only controls (rail
    /// buttons, toolbar buttons) that otherwise have no raised background.
    static let controlHover = dynamic(
        light: NSColor(calibratedWhite: 0, alpha: 0.06),
        dark: NSColor(calibratedWhite: 1, alpha: 0.10)
    )

    static let controlPressed = dynamic(
        light: NSColor(calibratedWhite: 0, alpha: 0.12),
        dark: NSColor(calibratedWhite: 1, alpha: 0.18)
    )

    /// Inline error banner (failed navigation) surface + text.
    static let dangerSurface = dynamic(
        light: NSColor(calibratedRed: 0.98, green: 0.90, blue: 0.90, alpha: 1),
        dark: NSColor(calibratedRed: 0.32, green: 0.14, blue: 0.14, alpha: 1)
    )

    static let dangerInk = dynamic(
        light: NSColor(calibratedRed: 0.58, green: 0.11, blue: 0.09, alpha: 1),
        dark: NSColor(calibratedRed: 0.98, green: 0.62, blue: 0.58, alpha: 1)
    )

    /// Shadow strength differs per appearance: a heavy shadow reads as dirt
    /// on a dark surface.
    static func shadow(isDark: Bool) -> Color {
        Color.black.opacity(isDark ? 0.45 : 0.16)
    }

    // MARK: - Metrics

    /// Shared geometry so the rail, tiles, and window corners agree.
    enum Metrics {
        static let panelCornerRadius: CGFloat = 22
        static let cardCornerRadius: CGFloat = 16
        static let contentCornerRadius: CGFloat = 14
        /// The rail carries icon-only controls, so it is kept as narrow as a
        /// comfortable hit target allows: every extra point comes straight out
        /// of the web content beside it.
        static let railWidth: CGFloat = 44
        /// Square hit target for one rail row: a site, a tab, or an icon
        /// control.
        static let railItemSize: CGFloat = 34
        /// Gap between rail rows. Applied as padding *inside* each row rather
        /// than as stack spacing, so the seam belongs to a row and can accept a
        /// drop instead of being a dead zone between two targets.
        static let railRowSpacing: CGFloat = 4
        /// Full height of a reorderable rail row including its share of the
        /// spacing -- the height the drop delegate halves to tell "insert above"
        /// from "insert below".
        static let railRowHeight: CGFloat = railItemSize + railRowSpacing
        /// Favicon size inside a rail row, leaving a little padding inside the
        /// row's hover background.
        static let railIconSize: CGFloat = 22
        static let tileSize: CGFloat = 104
        static let toolbarHeight: CGFloat = 52
        /// Height of the browser toolbar's address pill (narrower than the
        /// full toolbar so it reads as a control, not a second bar).
        static let addressPillHeight: CGFloat = 30
        /// Height of the find-in-page bar shown above the web content.
        static let findBarHeight: CGFloat = 38
        /// Corner radius for small controls: rail icon buttons, tile hover
        /// backgrounds that don't need the full card radius.
        static let controlCornerRadius: CGFloat = 8
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

/// `NSVisualEffectView` bridge used for the panel's frosted backdrop, which
/// is what makes a floating slide-over read as part of macOS rather than a
/// flat grey rectangle pasted over the desktop.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var isEmphasized = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = isEmphasized
        nsView.state = .active
    }
}
