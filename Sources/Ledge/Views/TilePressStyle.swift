import SwiftUI

/// Hover-lift and press feedback shared by every Home tile.
///
/// Lives on its own so favourites and notes cannot drift apart: the grid
/// reads as one surface, and a note that only changed its background while
/// the favourite beside it lifted looked broken rather than different.
/// Layered on top of the hover-driven background change applied in each
/// tile's label.
struct TilePressStyle: ButtonStyle {
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovering ? 1.02 : 1))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// The tile shadow, which deepens and drops further on hover so the
    /// tile reads as rising towards the pointer.
    func tileHoverShadow(isHovering: Bool) -> some View {
        shadow(
            color: Theme.shadow(isDark: false).opacity(isHovering ? 0.5 : 0.3),
            radius: isHovering ? 14 : 9,
            y: isHovering ? 8 : 6
        )
    }
}
