import SwiftUI

/// The editor shown inside a `NoteWindow`. Plain text only -- no WebKit, no
/// browser chrome. Text autosaves on a short debounce and again on close.
struct NoteEditorView: View {
    @ObservedObject var controller: NoteWindowController
    @FocusState private var editorFocused: Bool
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)

                Text(controller.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Button {
                    isConfirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.inkSecondary)
                .help("Delete note")
                .accessibilityLabel("Delete note")
                // The delete button must never be reached by keyboard
                // navigation before the editor itself: it has no key
                // equivalent, and an accidental Space "click" on it would
                // raise the destructive confirmation for no reason.
                .focusable(false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            TextEditor(text: $controller.body)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .padding(10)
                .onChange(of: controller.body) { _, _ in
                    controller.bodyDidChange()
                }
        }
        .background(Theme.canvas)
        .onAppear {
            editorFocused = true
        }
        .onChange(of: controller.focusToken) { _, _ in
            editorFocused = true
        }
        .alert("Delete this note?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                controller.deleteNote()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will be permanently removed from your Mac.")
        }
    }
}
