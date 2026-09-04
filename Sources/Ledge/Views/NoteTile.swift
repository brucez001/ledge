import SwiftUI

/// One saved note on the Home grid. Clicking opens (or focuses) its window;
/// the note itself is deleted from inside the window so the destructive
/// action always has an explicit confirmation.
struct NoteTile: View {
    let note: Note
    let isOpen: Bool
    let open: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "note.text")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(isOpen ? Color.accentColor : Theme.inkTertiary)

                Spacer(minLength: 0)

                Text(note.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(note.preview)
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
                    .stroke(isOpen ? Color.accentColor.opacity(0.9) : Theme.hairline, lineWidth: isOpen ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Open note")
        .accessibilityLabel(isOpen ? "Open note: \(note.title)" : "Note: \(note.title)")
    }
}

/// The dashed "add" tile that creates a brand-new note, mirroring the
/// favourites grid's `AddTile`.
struct NewNoteTile: View {
    let action: () -> Void

    @State private var isHovering = false

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
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Create a new note")
        .help("New note (⌘N)")
    }
}
