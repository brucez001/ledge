import SwiftUI

/// Shared wording for deleting a note, so the Home tile, the rail row, and
/// the editor's own trash button all say the same thing about the same
/// action.
enum NoteDeletion {
    static let menuTitle = "Delete Note…"

    static func confirmationTitle(_ title: String) -> String {
        "Delete \(title)?"
    }

    /// Deleting a note removes a file, which is the one note action that
    /// cannot be undone -- unlike closing a tab, which keeps it.
    static let confirmationMessage =
        "The note will be permanently removed from your Mac. Closing a note instead keeps the file."
}

extension View {
    func confirmNoteDeletion(
        title: String,
        isPresented: Binding<Bool>,
        delete: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            NoteDeletion.confirmationTitle(title),
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Note", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(NoteDeletion.confirmationMessage)
        }
    }
}

/// The right-click menu for a saved note, wherever it is shown. Kept to the
/// two things a note outside its editor can do: open it, or delete the
/// file.
struct NoteMenuItems: View {
    let open: () -> Void
    let confirmDeletion: () -> Void

    var body: some View {
        Button("Open", action: open)

        Divider()

        Button(NoteDeletion.menuTitle, role: .destructive, action: confirmDeletion)
    }
}
