import AppKit
import SwiftUI

/// The live text view behind a note's raw Markdown mode, plus the small
/// proxy the toolbar uses to drive it.
///
/// SwiftUI's own `TextEditor` cannot report or move the selection on macOS
/// 14, and a formatting toolbar is nothing without one: every command here
/// ("wrap the selected words in `**`", "put the caret on the link's URL")
/// needs the exact selected range and needs to hand a new one back. So the
/// editor is an `NSTextView` bridged into SwiftUI, with `MarkdownEditing`
/// doing the pure text arithmetic and this file limited to AppKit plumbing.
@MainActor
final class MarkdownEditorProxy: ObservableObject {
    /// Weak: the text view belongs to the view hierarchy, and the proxy
    /// outlives individual `updateNSView` passes.
    fileprivate weak var textView: NSTextView?

    /// Mirrored for the toolbar, which has to dim its undo/redo buttons
    /// without reaching into AppKit itself.
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    /// Runs one toolbar command against the current text and selection.
    ///
    /// The replacement goes through `shouldChangeText(in:replacementString:)`
    /// so AppKit registers it as a single undoable edit -- pressing ⌘Z after
    /// "make this a list" must undo the whole list, not one character.
    func apply(_ command: MarkdownCommand) {
        guard let textView, let storage = textView.textStorage else { return }
        let current = textView.string
        let edit = MarkdownEditing.apply(command, to: current, selection: textView.selectedRange())

        if edit.text != current {
            let (range, replacement) = Self.minimalChange(from: current, to: edit.text)
            guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
            storage.beginEditing()
            storage.replaceCharacters(in: range, with: replacement)
            storage.endEditing()
            textView.didChangeText()
        }

        let length = (textView.string as NSString).length
        let location = min(max(edit.selection.location, 0), length)
        let selection = NSRange(
            location: location,
            length: min(max(edit.selection.length, 0), length - location)
        )
        textView.setSelectedRange(selection)
        textView.scrollRangeToVisible(selection)
        refreshUndoState()
    }

    func undo() {
        guard let manager = textView?.undoManager, manager.canUndo else { return }
        manager.undo()
        refreshUndoState()
    }

    func redo() {
        guard let manager = textView?.undoManager, manager.canRedo else { return }
        manager.redo()
        refreshUndoState()
    }

    /// Gives the editor keyboard focus. Called when a note tab opens or is
    /// re-selected so the user's first keystroke lands in the text rather
    /// than on a toolbar button.
    ///
    /// A tab can be selected before its `NSTextView` has joined a window,
    /// so a focus request that arrives too early is retried on the next
    /// few runloop turns rather than dropped.
    func focus(retries: Int = 3) {
        guard let textView else { return }
        // A hidden editor cannot take focus; it is unhidden in
        // `updateNSView`, which may land a turn after the request.
        if let window = textView.window, !textView.isHiddenOrHasHiddenAncestor {
            window.makeFirstResponder(textView)
            return
        }
        guard retries > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.focus(retries: retries - 1)
        }
    }

    /// Parks keyboard focus while the preview is showing.
    ///
    /// The editor stays mounted behind the preview, so it must not keep
    /// first responder -- typing would disappear into a hidden view. And
    /// focus has to be dropped rather than passed on: left to find its own
    /// home, AppKit hands it to the nearest control and paints a focus
    /// ring around a bare toolbar glyph.
    func relinquishFocus() {
        guard let textView, let window = textView.window else { return }
        guard window.firstResponder === textView else { return }
        window.makeFirstResponder(nil)
    }

    fileprivate func refreshUndoState() {
        let manager = textView?.undoManager
        let undoable = manager?.canUndo ?? false
        let redoable = manager?.canRedo ?? false
        if undoable != canUndo { canUndo = undoable }
        if redoable != canRedo { canRedo = redoable }
    }

    /// Narrows a whole-text replacement down to the span that actually
    /// changed, so the text view keeps its scroll position and AppKit's
    /// undo stack stays proportionate to the edit.
    ///
    /// Boundaries are nudged off the inside of a surrogate pair: replacing
    /// half of an emoji would corrupt the storage.
    nonisolated static func minimalChange(from old: String, to new: String) -> (NSRange, String) {
        let oldUnits = Array(old.utf16)
        let newUnits = Array(new.utf16)

        var start = 0
        while start < oldUnits.count, start < newUnits.count, oldUnits[start] == newUnits[start] {
            start += 1
        }
        var oldEnd = oldUnits.count
        var newEnd = newUnits.count
        while oldEnd > start, newEnd > start, oldUnits[oldEnd - 1] == newUnits[newEnd - 1] {
            oldEnd -= 1
            newEnd -= 1
        }

        if start > 0, isHighSurrogate(oldUnits[start - 1]) {
            start -= 1
        }
        if oldEnd < oldUnits.count, isLowSurrogate(oldUnits[oldEnd]) {
            oldEnd += 1
            newEnd = min(newEnd + 1, newUnits.count)
        }

        let range = NSRange(location: start, length: max(0, oldEnd - start))
        let replacement = String(utf16CodeUnits: Array(newUnits[start..<max(start, newEnd)]), count: max(0, newEnd - start))
        return (range, replacement)
    }

    private nonisolated static func isHighSurrogate(_ unit: UInt16) -> Bool {
        (0xD800...0xDBFF).contains(unit)
    }

    private nonisolated static func isLowSurrogate(_ unit: UInt16) -> Bool {
        (0xDC00...0xDFFF).contains(unit)
    }
}

/// Markdown editing surface for one note tab.
///
/// The same text view serves both editing modes. In live mode
/// `MarkdownLiveStyler` restyles the storage after every change, so the note
/// is drawn as formatted text while the buffer stays plain Markdown; with
/// `rendersMarkdown` off the storage is reset to unstyled source.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    let proxy: MarkdownEditorProxy
    /// Whether Markdown is rendered as it is typed.
    let rendersMarkdown: Bool
    /// Whether the editor is the one on screen. Inactive editors stay
    /// mounted (undo history, caret) but are hidden at the AppKit level:
    /// SwiftUI's `opacity(0)` and `allowsHitTesting(false)` leave the
    /// `NSTextView`'s cursor rects live, so without this the I-beam bleeds
    /// through onto Home and the browser.
    let isVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, proxy: proxy, rendersMarkdown: rendersMarkdown)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Built by hand rather than by `NSTextView()`, which would give a
        // TextKit 2 layout manager: hiding syntax needs
        // `shouldGenerateGlyphs`, and that hook exists on TextKit 1 only.
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)

        let textView = MarkdownNSTextView(frame: .zero, textContainer: container)
        textView.hiddenSyntax = context.coordinator.hiddenSyntax
        layoutManager.delegate = context.coordinator.hiddenSyntax
        textView.proxy = proxy
        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = .textColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        // Markdown is punctuation, not prose: smart quotes would turn
        // `"` into a curly quote inside a link, and dash substitution
        // would rewrite `---` (a divider) as an em dash.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.string = text
        context.coordinator.restyle(textView)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        proxy.textView = textView
        proxy.refreshUndoState()
        scrollView.isHidden = !isVisible
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        scrollView.isHidden = !isVisible
        context.coordinator.text = $text
        proxy.textView = textView
        let modeChanged = context.coordinator.rendersMarkdown != rendersMarkdown
        context.coordinator.rendersMarkdown = rendersMarkdown
        // Only sync when the model genuinely diverges (a note reloaded from
        // disk, say). Rewriting the string on every pass would fight the
        // user's own typing and reset the selection.
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let length = (textView.string as NSString).length
            let location = min(selection.location, length)
            textView.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
            context.coordinator.restyle(textView)
        } else if modeChanged {
            context.coordinator.restyle(textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        /// Mirrored from the view so `textDidChange` -- which has no access
        /// to the current SwiftUI value -- knows which mode to restyle in.
        var rendersMarkdown: Bool
        private let proxy: MarkdownEditorProxy
        /// Owned here so it outlives `makeNSView`: `NSLayoutManager` holds
        /// its delegate weakly.
        let hiddenSyntax = MarkdownHiddenSyntaxLayout()
        /// The line range whose syntax is currently shown, so a caret moving
        /// within one line does not repaint the document.
        private var revealedLine: NSRange?

        init(text: Binding<String>, proxy: MarkdownEditorProxy, rendersMarkdown: Bool) {
            self.text = text
            self.proxy = proxy
            self.rendersMarkdown = rendersMarkdown
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if text.wrappedValue != textView.string {
                text.wrappedValue = textView.string
            }
            restyle(textView)
            proxy.refreshUndoState()
        }

        /// Moving the caret onto another line uncovers that line's syntax
        /// and covers the last one's, which is a restyle like any other.
        ///
        /// Guarded on the line rather than the offset: moving along a line
        /// changes nothing that is drawn, and repainting on every arrow key
        /// would be work for nothing.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard rendersMarkdown, let textView = notification.object as? NSTextView else { return }
            let line = (textView.string as NSString).lineRange(for: textView.selectedRange())
            guard line != revealedLine else { return }
            restyle(textView)
        }

        /// Repaints the storage for the current mode.
        ///
        /// Attributes only: no character is added, removed, or replaced, so
        /// this never reaches the undo stack and never moves the caret.
        /// Typing attributes are pinned to the plain baseline afterwards, or
        /// the next character typed beside a bullet would inherit its
        /// substituted glyph.
        func restyle(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            if rendersMarkdown {
                let selection = textView.selectedRange()
                revealedLine = (textView.string as NSString).lineRange(for: selection)
                MarkdownLiveStyler.style(storage, revealing: selection)
            } else {
                revealedLine = nil
                MarkdownLiveStyler.reset(storage)
            }
            textView.typingAttributes = MarkdownLiveStyler.plainAttributes
            invalidateGlyphs(in: textView)
        }

        /// Attribute changes invalidate layout but not glyphs, and whether a
        /// character is drawn at all is decided during glyph generation --
        /// so hiding or revealing syntax only takes effect once the glyphs
        /// are asked for again.
        private func invalidateGlyphs(in textView: NSTextView) {
            guard let layoutManager = textView.layoutManager, let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            layoutManager.invalidateGlyphs(forCharacterRange: full, changeInLength: 0, actualCharacterRange: nil)
            layoutManager.invalidateLayout(forCharacterRange: full, actualCharacterRange: nil)
        }
    }
}

/// `NSTextView` with the keyboard and Return behaviour a Markdown editor is
/// expected to have.
///
/// The app is an accessory with no application menu bar, so SwiftUI's
/// `.keyboardShortcut` has nothing to hang ⌘B off; the text view that owns
/// the keystroke handles it instead.
private final class MarkdownNSTextView: NSTextView {
    weak var proxy: MarkdownEditorProxy?

    /// Retained so the layout manager's weak delegate lives as long as the
    /// view whose glyphs it suppresses.
    var hiddenSyntax: MarkdownHiddenSyntaxLayout?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), let proxy else {
            return super.performKeyEquivalent(with: event)
        }
        let shift = flags.contains(.shift)
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b" where !shift:
            proxy.apply(.bold)
            return true
        case "i" where !shift:
            proxy.apply(.italic)
            return true
        case "k" where !shift:
            proxy.apply(.link)
            return true
        case "e" where !shift:
            proxy.apply(.inlineCode)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    /// Continues the current list or quote on Return, and clears an empty
    /// marker instead of stacking another one -- the behaviour every
    /// Markdown editor has, and tedious to live without.
    override func insertNewline(_ sender: Any?) {
        let text = string as NSString
        let lineRange = text.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)

        guard let continuation = MarkdownListContinuation.continuation(for: line) else {
            super.insertNewline(sender)
            return
        }

        switch continuation {
        case .clear(let emptyLine):
            // "- " on its own: Return ends the list rather than adding a
            // second empty bullet.
            let replacement = NSRange(location: lineRange.location, length: line.utf16.count)
            guard shouldChangeText(in: replacement, replacementString: emptyLine) else { return }
            textStorage?.replaceCharacters(in: replacement, with: emptyLine)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location + (emptyLine as NSString).length, length: 0))
            super.insertNewline(sender)
        case .marker(let marker):
            super.insertNewline(sender)
            insertText(marker, replacementRange: selectedRange())
        }
        proxy?.refreshUndoState()
    }
}
