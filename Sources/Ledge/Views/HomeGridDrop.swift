import SwiftUI

extension View {
    /// Makes a home-grid tile a drop target for its own kind of drag.
    ///
    /// `decode` is what separates one grid from another: both grids accept
    /// plain text, so each reads only the payload it owns and declines the
    /// rest. A nil `perform` is a tile that shows notes or favourites without
    /// letting them be arranged.
    func homeGridDropTarget(
        decoding decode: @escaping (String) -> UUID?,
        perform: ((UUID) -> Void)?
    ) -> some View {
        modifier(HomeGridDropTarget(decode: decode, perform: perform))
    }
}

private struct HomeGridDropTarget: ViewModifier {
    let decode: (String) -> UUID?
    let perform: ((UUID) -> Void)?

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            // A drop lands *before* its target, so the line sits on the
            // leading edge, in the gap rather than over the tile.
            .overlay(alignment: .leading) {
                InsertionLine(isShowing: isTargeted)
                    .offset(x: -Theme.Metrics.tileGap / 2)
            }
            // Widened into the gaps either side, then shrunk back so the grid
            // lays out unchanged. Without this the gap a drop is aimed at --
            // the gap the line is drawn in -- accepts nothing, and the release
            // animates the tile back to where it came from.
            .padding(.horizontal, Theme.Metrics.tileGap / 2)
            .dropDestination(for: String.self) { payloads, _ in
                guard let perform, let id = payloads.compactMap(decode).first else {
                    return false
                }
                perform(id)
                return true
            } isTargeted: { isTargeted = $0 }
            .padding(.horizontal, -Theme.Metrics.tileGap / 2)
    }
}

/// Where a dragged tile will land: the rail's insertion line on its side.
private struct InsertionLine: View {
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
