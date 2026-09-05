import SwiftUI

/// Ledge's own tooltip, used instead of AppKit's.
///
/// macOS only draws `NSView.toolTip` for windows belonging to the *active*
/// app, and an edge-hover reveal deliberately leaves Ledge in the
/// background (`PanelController.reveal(activating:)` orders the panel front
/// without activating). So the system tooltip never appeared in the case
/// that matters most: the panel is on screen, the pointer is on a glyph,
/// and the user has not clicked yet. This layer is plain SwiftUI, so it is
/// drawn whether or not the app is frontmost.
///
/// A control publishes a request through a preference and the pane draws
/// the bubble in one overlay above everything, so a tooltip is never
/// clipped by the toolbar's horizontal `ScrollView` or by a 26pt button.
struct NoteTooltipRequest: Equatable {
    let text: String
    let anchor: Anchor<CGRect>
}

struct NoteTooltipKey: PreferenceKey {
    static let defaultValue: NoteTooltipRequest? = nil

    static func reduce(value: inout NoteTooltipRequest?, nextValue: () -> NoteTooltipRequest?) {
        // Last writer wins: only one control is hovered at a time, and a
        // newly hovered one should replace whatever was showing.
        if let next = nextValue() { value = next }
    }
}

/// Where the bubble sits relative to its control. Pure geometry, kept
/// separate from the view so the clamping rules can be unit-tested.
enum NoteTooltipPlacement {
    /// Gap between the control and the bubble.
    static let gap: CGFloat = 6
    /// Smallest distance the bubble keeps from the pane's edges.
    static let margin: CGFloat = 8

    /// Top-left corner for a `tooltip`-sized bubble pointing at `control`,
    /// in the coordinate space of a `container`-sized pane.
    ///
    /// Below the control by default -- the note chrome lives at the top of
    /// the pane -- flipping above only when the bubble would otherwise fall
    /// off the bottom, and always clamped horizontally so a control near
    /// the right edge (the delete button, say) keeps its whole label
    /// on screen.
    static func origin(control: CGRect, container: CGSize, tooltip: CGSize) -> CGPoint {
        let centred = control.midX - tooltip.width / 2
        let maxX = container.width - tooltip.width - margin
        // `max(margin, ...)` last so a bubble wider than the pane starts at
        // the left margin rather than being pushed off to the left.
        let x = max(margin, min(centred, maxX))

        let below = control.maxY + gap
        let fitsBelow = below + tooltip.height <= container.height - margin
        let above = control.minY - gap - tooltip.height
        let y = fitsBelow ? below : max(margin, above)

        return CGPoint(x: x, y: y)
    }
}

/// The bubble itself: a compact, non-interactive label matching the panel's
/// chrome rather than the system's yellow tooltip.
struct NoteTooltipBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
            // Purely informational: it must never swallow the click the
            // user is lining up on the control underneath.
            .allowsHitTesting(false)
    }
}

extension View {
    /// Draws whichever tooltip the controls inside this view are asking for.
    /// Apply once per pane, above the content.
    func noteTooltipLayer() -> some View {
        modifier(NoteTooltipLayer())
    }

    /// Publishes this control's tooltip while `isShowing` is true.
    func noteTooltip(_ text: String, isShowing: Bool) -> some View {
        anchorPreference(key: NoteTooltipKey.self, value: .bounds) { anchor in
            isShowing ? NoteTooltipRequest(text: text, anchor: anchor) : nil
        }
    }
}

private struct NoteTooltipLayer: ViewModifier {
    /// The bubble has to be measured before it can be placed; until it is,
    /// it stays invisible so the first frame never flashes in the wrong
    /// corner.
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(NoteTooltipKey.self) { request in
            GeometryReader { proxy in
                if let request {
                    let origin = NoteTooltipPlacement.origin(
                        control: proxy[request.anchor],
                        container: proxy.size,
                        tooltip: size
                    )
                    NoteTooltipBubble(text: request.text)
                        .fixedSize()
                        .background {
                            GeometryReader { bubble in
                                Color.clear
                                    .onAppear { size = bubble.size }
                                    .onChange(of: bubble.size) { _, new in size = new }
                            }
                        }
                        .position(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
                        .opacity(size == .zero ? 0 : 1)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.12), value: request?.text)
        }
    }
}
