import SwiftUI
import UniformTypeIdentifiers

struct FavouriteTile: View {
    @ObservedObject var controller: PanelController
    let item: Favourite
    let isActive: Bool

    @State private var isHovering = false
    @State private var isConfirmingRemoval = false
    @State private var isDropTargeted = false

    var body: some View {
        Button {
            controller.openFavourite(item)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                FaviconView(host: item.host, size: 30)
                    .frame(width: 30, height: 30)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer(minLength: 0)

                Text(item.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(width: Theme.Metrics.tileSize, height: Theme.Metrics.tileSize, alignment: .leading)
            .background(isHovering ? Theme.cardHover : Theme.card, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius, style: .continuous)
                    .stroke(isActive ? Color.accentColor.opacity(0.9) : Theme.hairline, lineWidth: isActive ? 2 : 1)
            }
            .tileHoverShadow(isHovering: isHovering)
            // Inside the button's label, not on the button: SwiftUI's button
            // press gesture claims the whole press-and-move sequence, so a
            // drag modifier attached outside it never starts a drag session.
            .draggable(SiteDragPayload.encode(item.id))
        }
        .buttonStyle(TilePressStyle(isHovering: isHovering))
        .onHover { isHovering = $0 }
        // A dropped tile lands *before* this one, so the indicator sits on the
        // leading edge, in the gap between tiles rather than over the target.
        .overlay(alignment: .leading) {
            GridInsertionLine(isShowing: isDropTargeted)
                .offset(x: -Theme.Metrics.tileGap / 2)
        }
        // Widened into the gaps either side, then shrunk back so the grid
        // lays out unchanged. Without this the gap a drop is aimed at -- the
        // gap the indicator is drawn in -- accepts nothing, and the release
        // animates the tile back to where it came from.
        .padding(.horizontal, Theme.Metrics.tileGap / 2)
        .dropDestination(for: String.self) { payloads, _ in
            // Re-inserts the dragged favourite directly before this tile.
            guard let draggedID = payloads.compactMap(SiteDragPayload.decode).first else {
                return false
            }
            controller.favourites.move(id: draggedID, before: item.id)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .padding(.horizontal, -Theme.Metrics.tileGap / 2)
        .contextMenu {
            FavouriteMenuItems(
                controller: controller,
                item: item
            ) {
                isConfirmingRemoval = true
            }
        }
        .confirmFavouriteRemoval(item, isPresented: $isConfirmingRemoval) {
            controller.removeFavourite(item)
        }
        .accessibilityLabel("Open \(item.name)")
    }
}

struct AddTile: View {
    let action: () -> Void
    /// Dropping a dragged favourite here moves it to the end of the grid.
    /// Tiles can only accept a drop "before themselves", so without this
    /// there is no way to reorder something past the final item.
    var onDropFavourite: ((UUID) -> Void)?

    @State private var isHovering = false
    @State private var isDropTargeted = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: Theme.Metrics.tileSize, height: Theme.Metrics.tileSize)
                .background(isHovering ? Theme.cardHover : Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                }
                .scaleEffect(isHovering ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Add favourite")
        .help("Add a favourite site")
        // Dropping here sends the tile to the end of the grid, so the line
        // marks the position *after* the last favourite.
        .overlay(alignment: .leading) {
            GridInsertionLine(isShowing: isDropTargeted)
                .offset(x: -Theme.Metrics.tileGap / 2)
        }
        .padding(.horizontal, Theme.Metrics.tileGap / 2)
        .dropDestination(for: String.self) { payloads, _ in
            guard let onDropFavourite,
                  let draggedID = payloads.compactMap(SiteDragPayload.decode).first else {
                return false
            }
            onDropFavourite(draggedID)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .padding(.horizontal, -Theme.Metrics.tileGap / 2)
    }
}
