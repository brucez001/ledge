import SwiftUI
import UniformTypeIdentifiers

struct FavouriteTile: View {
    @ObservedObject var controller: PanelController
    let item: Favourite
    let isActive: Bool

    @State private var isHovering = false
    @State private var isConfirmingRemoval = false

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
            .shadow(color: Theme.shadow(isDark: false).opacity(isHovering ? 0.5 : 0.3), radius: isHovering ? 14 : 9, y: isHovering ? 8 : 6)
        }
        .buttonStyle(TilePressStyle(isHovering: isHovering))
        .onHover { isHovering = $0 }
        .onDrag {
            NSItemProvider(object: SiteDragPayload.encode(item.id) as NSString)
        }
        .onDrop(of: [SiteDragPayload.type], isTargeted: nil) { providers in
            // Simple, robust drop handling: read back the dragged
            // favourite's UUID and re-insert it directly before this tile.
            // No live drag-preview reordering, just a clean drop-to-reorder.
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSString.self) { reading, _ in
                guard let string = reading as? String,
                      let draggedID = SiteDragPayload.decode(string) else { return }
                Task { @MainActor in
                    controller.favourites.move(id: draggedID, before: item.id)
                }
            }
            return true
        }
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

/// Scale-on-press feedback, layered on top of the hover-driven background
/// change already applied in the label itself.
private struct TilePressStyle: ButtonStyle {
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovering ? 1.02 : 1))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AddTile: View {
    let action: () -> Void
    /// Dropping a dragged favourite here moves it to the end of the grid.
    /// Tiles can only accept a drop "before themselves", so without this
    /// there is no way to reorder something past the final item.
    /// Typed `@MainActor @Sendable` because `NSItemProvider` delivers its
    /// result on an arbitrary queue.
    var onDropFavourite: (@MainActor @Sendable (UUID) -> Void)?

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
                        .stroke(
                            isDropTargeted ? Color.accentColor.opacity(0.9) : Theme.hairline,
                            lineWidth: isDropTargeted ? 2 : 1
                        )
                }
                .scaleEffect(isHovering ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Add favourite")
        .help("Add a favourite site")
        .onDrop(of: [SiteDragPayload.type], isTargeted: $isDropTargeted) { providers in
            guard let onDropFavourite, let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSString.self) { reading, _ in
                guard let string = reading as? String,
                      let draggedID = SiteDragPayload.decode(string) else { return }
                Task { @MainActor in onDropFavourite(draggedID) }
            }
            return true
        }
    }
}
