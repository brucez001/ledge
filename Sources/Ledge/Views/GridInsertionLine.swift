import SwiftUI

/// Where a dragged tile will land on a home grid: the rail's insertion line
/// turned on its side.
///
/// Drawn by the tile the pointer is over, offset into the gap before it,
/// because a drop always inserts *before* its target.
struct GridInsertionLine: View {
    let isShowing: Bool

    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: 2)
            .padding(.vertical, 6)
            .opacity(isShowing ? 1 : 0)
            // Scoped to the line. Animating this from the tile animates the
            // tile's whole subtree -- card shadow included -- every time the
            // pointer crosses a drop target.
            .animation(.easeOut(duration: 0.12), value: isShowing)
            .allowsHitTesting(false)
    }
}
