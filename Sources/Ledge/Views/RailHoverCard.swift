import SwiftUI

/// A hover card for rail rows whose glyph alone does not say what they are.
///
/// Every open note shares the same `note.text` glyph, so the rail gives no
/// clue which tab is which. Hovering a row shows the note's name and the
/// same one-line peek its Home tile carries, so the rail and the tile read
/// identically.
///
/// This is Ledge's own layer rather than `.help()` for the reason set out
/// in `NoteTooltip.swift`: macOS only draws system tooltips for the active
/// app, and an edge-hover reveal leaves Ledge in the background. The rail is
/// also only 44pt wide, so the card is drawn by the shell -- beside the rail,
/// over the content -- rather than clipped inside it.
struct RailHoverCardRequest: Equatable {
    /// The row asking for the card. Each row's card is its own view, so
    /// moving between rows crossfades rather than sliding a shared bubble
    /// whose text, size, and position would otherwise update on different
    /// frames.
    let id: UUID
    let title: String
    let subtitle: String?
    let anchor: Anchor<CGRect>
}

struct RailHoverCardKey: PreferenceKey {
    static let defaultValue: RailHoverCardRequest? = nil

    static func reduce(value: inout RailHoverCardRequest?, nextValue: () -> RailHoverCardRequest?) {
        // Last writer wins: only one row is hovered at a time.
        if let next = nextValue() { value = next }
    }
}

/// Where the card sits relative to its row. Pure geometry so the rules can
/// be unit-tested without a window.
enum RailHoverCardPlacement {
    /// Gap between the rail row and the card.
    static let gap: CGFloat = 8
    /// Smallest distance the card keeps from the panel's top and bottom.
    static let margin: CGFloat = 8

    /// Top-left corner for a `card`-sized bubble beside `row`, in the
    /// coordinate space of a `container`-sized shell.
    ///
    /// The card always opens away from the rail and towards the content:
    /// leftwards when the rail is docked on the right, rightwards when it is
    /// docked on the left. Vertically it is centred on the row and clamped so
    /// a row at the very bottom of a long rail keeps its whole card on screen.
    static func origin(row: CGRect, container: CGSize, card: CGSize, dockSide: DockSide) -> CGPoint {
        let x: CGFloat = switch dockSide {
        case .right: row.minX - gap - card.width
        case .left: row.maxX + gap
        }

        let centred = row.midY - card.height / 2
        let maxY = container.height - card.height - margin
        let y = max(margin, min(centred, maxY))

        return CGPoint(x: x, y: y)
    }
}

/// The card itself: name on top, peek underneath, in the panel's own chrome.
struct RailHoverCardBubble: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 240, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 8, y: 2)
        // Purely informational: it must never intercept the pointer.
        .allowsHitTesting(false)
    }
}

extension View {
    /// Draws whichever hover card the rail rows inside this view are asking
    /// for. Apply once on the shell, so the card can extend over the content.
    func railHoverCardLayer(dockSide: DockSide) -> some View {
        modifier(RailHoverCardLayer(dockSide: dockSide))
    }

    /// Publishes this row's hover card while `isShowing` is true.
    func railHoverCard(id: UUID, title: String, subtitle: String? = nil, isShowing: Bool) -> some View {
        anchorPreference(key: RailHoverCardKey.self, value: .bounds) { anchor in
            isShowing ? RailHoverCardRequest(id: id, title: title, subtitle: subtitle, anchor: anchor) : nil
        }
    }
}

private struct RailHoverCardLayer: ViewModifier {
    let dockSide: DockSide

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(RailHoverCardKey.self) { request in
            GeometryReader { proxy in
                if let request {
                    PlacedRailHoverCard(
                        request: request,
                        row: proxy[request.anchor],
                        container: proxy.size,
                        dockSide: dockSide
                    )
                    // Identity per row: a new row means a new card, so the
                    // old one fades out as a unit and the new one fades in.
                    .id(request.id)
                    .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.12), value: request?.id)
        }
    }
}

/// One card, measured and placed. Owns its own size so a freshly shown card
/// is never positioned with a predecessor's measurements.
private struct PlacedRailHoverCard: View {
    let request: RailHoverCardRequest
    let row: CGRect
    let container: CGSize
    let dockSide: DockSide

    /// Invisible until measured so the first frame never flashes in the
    /// wrong corner.
    @State private var size: CGSize = .zero

    var body: some View {
        let origin = RailHoverCardPlacement.origin(
            row: row,
            container: container,
            card: size,
            dockSide: dockSide
        )
        RailHoverCardBubble(title: request.title, subtitle: request.subtitle)
            .background {
                GeometryReader { bubble in
                    Color.clear
                        .onAppear { size = bubble.size }
                        .onChange(of: bubble.size) { _, new in size = new }
                }
            }
            .position(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
            .opacity(size == .zero ? 0 : 1)
    }
}
