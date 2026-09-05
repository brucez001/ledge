import SwiftUI

/// The formatting row above a note's raw Markdown editor.
///
/// Everything here is a `MarkdownCommand` sent to the live text view
/// through `MarkdownEditorProxy`, so the toolbar holds no editing logic of
/// its own. The panel is narrow, so the row scrolls horizontally rather
/// than wrapping or squeezing hit targets below a comfortable size, and
/// related tools are separated by hairlines so the run of glyphs still
/// reads as groups.
struct NoteToolbar: View {
    @ObservedObject var proxy: MarkdownEditorProxy

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                button("arrow.uturn.backward", "Undo", .undoHistory)
                    .disabled(!proxy.canUndo)
                button("arrow.uturn.forward", "Redo", .redoHistory)
                    .disabled(!proxy.canRedo)
                button("eraser", "Clear formatting", .command(.clearFormatting))

                separator

                textButton("H1", "Heading 1", .heading(1))
                textButton("H2", "Heading 2", .heading(2))
                headingMenu

                separator

                button("bold", "Bold (⌘B)", .command(.bold))
                button("italic", "Italic (⌘I)", .command(.italic))
                button("strikethrough", "Strikethrough", .command(.strikethrough))
                button("chevron.left.forwardslash.chevron.right", "Inline code (⌘E)", .command(.inlineCode))
                button("link", "Link (⌘K)", .command(.link))

                separator

                button("list.bullet", "Bulleted list", .command(.bulletList))
                button("list.number", "Numbered list", .command(.numberedList))
                button("checklist", "Task list", .command(.taskList))
                button("text.quote", "Quote", .command(.quote))

                separator

                button("curlybraces", "Code block", .command(.codeBlock))
                button("tablecells", "Table", .command(.table))
                button("minus", "Divider", .command(.divider))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Theme.chrome)
    }

    /// Heading levels past 2 are rare in a note; they live in a menu so the
    /// row keeps its two common levels one click away.
    private var headingMenu: some View {
        Menu {
            ForEach(3...6, id: \.self) { level in
                Button("Heading \(level)") { proxy.apply(.heading(level)) }
            }
        } label: {
            Text("H⌄")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Theme.inkSecondary)
        .help("More heading levels")
        .accessibilityLabel("More heading levels")
    }

    private var separator: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }

    private func button(_ symbol: String, _ label: String, _ action: ToolbarAction) -> some View {
        NoteIconButton(
            tooltip: label,
            label: label,
            action: { perform(action) }
        ) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
        }
    }

    private func textButton(_ title: String, _ label: String, _ command: MarkdownCommand) -> some View {
        NoteIconButton(
            tooltip: label,
            label: label,
            action: { proxy.apply(command) }
        ) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
    }

    private func perform(_ action: ToolbarAction) {
        switch action {
        case .command(let command): proxy.apply(command)
        case .undoHistory: proxy.undo()
        case .redoHistory: proxy.redo()
        }
    }

    /// Undo and redo are AppKit history, not text transforms, so the row's
    /// buttons carry one of two kinds of action.
    private enum ToolbarAction {
        case command(MarkdownCommand)
        case undoHistory
        case redoHistory
    }
}
