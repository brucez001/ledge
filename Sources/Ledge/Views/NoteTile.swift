import SwiftUI

/// One saved note on the Home grid. Clicking opens (or focuses) its tab;
/// right-clicking offers the same two actions a note has outside its
/// editor. Deleting always goes through an explicit confirmation, because
/// it removes the file rather than just closing the tab.
struct NoteTile: View {
    let note: Note
    /// Passed in rather than read from `note`, because `Note.preview` scans the
    /// body's Markdown and this view re-evaluates on every hover and drop-target
    /// change. Computed by the grid instead, which only changes with the data.
    let preview: String
    let isOpen: Bool
    let open: () -> Void
    let delete: () -> Void
    /// Drops a dragged note directly before this one. Omitted by callers that
    /// show notes without letting them be arranged.
    var onDropNote: ((UUID) -> Void)?

    @State private var isHovering = false
    @State private var isConfirmingDelete = false
    @State private var isDropTargeted = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                // "Open" borrows the Dock's idiom: a small neutral dot
                // beneath the icon. Not a 2pt accent ring -- several notes
                // can be open at once and a grid of blue boxes reads as an
                // error -- and not an accent dot in the corner, which reads
                // as an unread badge.
                VStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.inkTertiary)
                    Circle()
                        .fill(Theme.inkSecondary)
                        .frame(width: 4, height: 4)
                        .opacity(isOpen ? 1 : 0)
                }
                .fixedSize()

                Spacer(minLength: 0)

                Text(note.displayTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(preview)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 3)
            }
            .padding(14)
            .frame(width: Theme.Metrics.tileSize, height: Theme.Metrics.tileSize, alignment: .leading)
            .background(
                isHovering ? Theme.cardHover : Theme.card,
                in: RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            }
            // Same lift and shadow as a favourite tile: the two grids are
            // one surface, so they must answer the pointer identically.
            .tileHoverShadow(isHovering: isHovering)
            // Inside the button's label, not on the button: the button's press
            // gesture claims the press-and-move sequence, so a drag attached
            // outside it never starts a drag session.
            .draggable(SiteDragPayload.encodeHomeNote(note.id))
        }
        .buttonStyle(TilePressStyle(isHovering: isHovering))
        .onHover { isHovering = $0 }
        .overlay(alignment: .leading) {
            GridInsertionLine(isShowing: isDropTargeted)
                .offset(x: -Theme.Metrics.tileGap / 2)
        }
        .padding(.horizontal, Theme.Metrics.tileGap / 2)
        .dropDestination(for: String.self) { payloads, _ in
            guard let onDropNote,
                  let draggedID = payloads.compactMap(SiteDragPayload.decodeHomeNote).first else {
                return false
            }
            onDropNote(draggedID)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .padding(.horizontal, -Theme.Metrics.tileGap / 2)
        .contextMenu {
            NoteMenuItems(open: open) { isConfirmingDelete = true }
        }
        .confirmNoteDeletion(title: note.displayTitle, isPresented: $isConfirmingDelete, delete: delete)
        .help("Open note")
        .accessibilityLabel(isOpen ? "Open note: \(note.displayTitle)" : "Note: \(note.displayTitle)")
    }
}

/// The dashed "add" tile that creates a brand-new note, mirroring the
/// favourites grid's `AddTile`.
struct NewNoteTile: View {
    let action: () -> Void
    /// Dropping a dragged note here moves it to the end of the grid. Tiles can
    /// only accept a drop "before themselves", so without this there is no way
    /// to move a note past the final one.
    var onDropNote: ((UUID) -> Void)?

    @State private var isHovering = false
    @State private var isDropTargeted = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Theme.inkSecondary)

                Text("New note")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(width: Theme.Metrics.tileSize, height: Theme.Metrics.tileSize)
            .background(
                isHovering ? Theme.cardHover : Theme.card.opacity(0.6),
                in: RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            }
            // Matches `AddTile`: the two "add" tiles lift, but without the
            // full card shadow, so they stay quieter than real content.
            .scaleEffect(isHovering ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Create a new note")
        .help("New note (⌘N)")
        .overlay(alignment: .leading) {
            GridInsertionLine(isShowing: isDropTargeted)
                .offset(x: -Theme.Metrics.tileGap / 2)
        }
        .padding(.horizontal, Theme.Metrics.tileGap / 2)
        .dropDestination(for: String.self) { payloads, _ in
            guard let onDropNote,
                  let draggedID = payloads.compactMap(SiteDragPayload.decodeHomeNote).first else {
                return false
            }
            onDropNote(draggedID)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .padding(.horizontal, -Theme.Metrics.tileGap / 2)
    }
}
