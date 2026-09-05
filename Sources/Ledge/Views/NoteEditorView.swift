import SwiftUI

/// The Markdown editor for one open note tab, embedded in the panel
/// alongside the rail.
///
/// Notes are plain Markdown files, so the tab shows them two ways: the raw
/// text with a formatting toolbar, and a rendered preview. Both read the
/// same `NoteTab.body`, so there is only ever one copy of the note and
/// nothing to reconcile between the modes.
///
/// The editor itself has two modes of its own. By default it renders the
/// Markdown as it is typed -- `- ` becomes a bullet dot point, `# ` a
/// heading -- and `Preferences.notesRenderMarkdown` turns that off for
/// anyone who would rather see the raw characters. Both are the same text
/// view over the same plain-text buffer: only the drawing differs.
///
/// Every open note tab is kept mounted with the same `NoteTab`, so a
/// half-typed draft never disappears when you switch away and back; only
/// the active tab claims keyboard focus and hit-testing.
struct NoteEditorView: View {
    @ObservedObject var tab: NoteTab
    /// Live rendering is a habit rather than a property of one note, so it
    /// is shared by every open tab.
    @ObservedObject private var preferences = Preferences.shared
    /// Whether this tab is the one currently shown in the pane.
    let isActive: Bool
    /// Runs after the user confirms the destructive delete action.
    let onDelete: () -> Void
    /// Runs when the user asks to close this tab without deleting it.
    let onClose: () -> Void

    @State private var isConfirmingDelete = false
    /// Rename state. The draft is separate from the note so a half-typed
    /// title never reaches the file until it is committed.
    @State private var isRenaming = false
    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool
    /// Owns the live `NSTextView` so the toolbar can act on the user's
    /// current selection. One per mounted tab, exactly like the editor it
    /// drives.
    @StateObject private var proxy = MarkdownEditorProxy()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            // The formatting tools act on raw text, so they are absent in
            // preview rather than shown dimmed: a dead row of sixteen
            // glyphs would be noise in a panel this narrow.
            if !tab.isPreviewing {
                NoteToolbar(proxy: proxy)
                Divider()
            }

            content
        }
        .background(Theme.canvas)
        // One tooltip layer for the whole pane: bubbles from the header and
        // from the scrolling toolbar are drawn here, so neither is clipped
        // by its own container.
        .noteTooltipLayer()
        .onChange(of: tab.body) { _, _ in
            tab.bodyDidChange()
        }
        .onAppear {
            focusEditorIfNeeded()
        }
        .onChange(of: isActive) { _, _ in
            focusEditorIfNeeded()
        }
        .onChange(of: tab.focusToken) { _, _ in
            focusEditorIfNeeded()
        }
        .onChange(of: tab.isPreviewing) { _, _ in
            focusEditorIfNeeded()
        }
        // The same dialog the Home tile and the rail row raise: one
        // destructive action, asked one way, wherever it is reached from.
        .confirmNoteDeletion(title: tab.displayTitle, isPresented: $isConfirmingDelete, delete: onDelete)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)

            title

            Spacer(minLength: 8)

            // Editing-mode switch, so it is absent in preview -- where
            // everything is rendered anyway and the control would say
            // nothing about what is on screen.
            if !tab.isPreviewing {
                NoteIconButton(
                    tooltip: preferences.notesRenderMarkdown
                        ? "Show raw Markdown while editing (⇧⌘L)"
                        : "Render Markdown while typing (⇧⌘L)",
                    label: "Render Markdown while typing",
                    isOn: preferences.notesRenderMarkdown,
                    action: { preferences.notesRenderMarkdown.toggle() }
                ) {
                    Image(systemName: "textformat")
                        .font(.system(size: 12, weight: .medium))
                }
            }

            // A switch rather than a one-shot action, so it also shows an
            // "on" fill while the preview is up.
            NoteIconButton(
                tooltip: tab.isPreviewing ? "Edit Markdown (⇧⌘P)" : "Preview Markdown (⇧⌘P)",
                label: tab.isPreviewing ? "Edit Markdown" : "Preview Markdown",
                isOn: tab.isPreviewing,
                action: tab.togglePreview
            ) {
                Image(systemName: tab.isPreviewing ? "square.and.pencil" : "book")
                    .font(.system(size: 12, weight: .medium))
            }

            NoteIconButton(
                tooltip: "Close note — the file is kept (⌘W)",
                label: "Close note",
                action: onClose
            ) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }

            NoteIconButton(
                tooltip: "Delete note permanently",
                label: "Delete note",
                hoverTint: Theme.dangerInk,
                action: { isConfirmingDelete = true }
            ) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .regular))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// The title doubles as the rename control: clicking it swaps the label
    /// for a field over the note's first line, which is where the title
    /// actually lives.
    @ViewBuilder
    private var title: some View {
        if isRenaming {
            TextField("Note title", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .focused($titleFocused)
                .onSubmit(commitRename)
                // Clicking away commits, matching every other macOS
                // inline rename; Escape blurs the field, so it lands here
                // too rather than silently discarding the edit.
                .onChange(of: titleFocused) { _, focused in
                    if !focused { commitRename() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            RenameTitleButton(title: tab.displayTitle, action: beginRename)
        }
    }

    private func beginRename() {
        titleDraft = tab.note.title
        isRenaming = true
        titleFocused = true
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        tab.rename(to: titleDraft)
        // Renaming is a detour from writing, so hand focus back to the
        // text the moment it is done.
        focusEditorIfNeeded()
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            // Mounted only while it is showing: parsing the whole note on
            // every keystroke would be wasted work behind the editor.
            if tab.isPreviewing {
                ScrollView(.vertical) {
                    MarkdownPreview(markdown: tab.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
            }

            // Never unmounted, only hidden -- the same rule the panel's web
            // views follow. Tearing the text view down for a peek at the
            // preview would throw away its undo history and caret.
            MarkdownTextEditor(
                text: $tab.body,
                proxy: proxy,
                rendersMarkdown: preferences.notesRenderMarkdown,
                isVisible: isActive && !tab.isPreviewing
            )
                .opacity(tab.isPreviewing ? 0 : 1)
                .allowsHitTesting(!tab.isPreviewing)
        }
    }

    /// The editor has to win focus over the toolbar the moment a note is
    /// shown, or the first keystroke would land on a control.
    private func focusEditorIfNeeded() {
        guard isActive else { return }
        guard !tab.isPreviewing else {
            proxy.relinquishFocus()
            return
        }
        proxy.focus()
    }
}

/// The title as a click target: a label with hover feedback and a tooltip,
/// so it reads as something you can rename rather than as static chrome.
private struct RenameTitleButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovering ? Theme.controlHover : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Rename note")
        .accessibilityLabel("Rename note")
        .accessibilityValue(title)
        // Like the rest of the note chrome, it is clicked rather than
        // tabbed to: a focus ring around the title would read as an edit
        // field that is not actually open yet.
        .focusable(false)
    }
}
