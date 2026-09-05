import AppKit

/// Draws a note's Markdown as it is typed, without rewriting a single
/// character of it.
///
/// This is the whole trick behind the notes' live mode: the text storage
/// still holds the plain Markdown source the file will be saved as, and only
/// its *attributes* change. A heading grows, `**bold**` goes bold, and the
/// `-` of a list item is drawn as a bullet -- but the buffer underneath is
/// still `- milk`, so the note stays a plain-text file any other editor can
/// open, the caret still moves over real characters, and nothing has to be
/// converted back on save.
///
/// The bullet is the one place where the drawing genuinely differs from the
/// text: `NSGlyphInfo` swaps the hyphen's *glyph* for the bullet glyph of the
/// same font, which is a display-time substitution and leaves the character
/// itself untouched.
///
/// `MarkdownLiveStyle` does all of the parsing; this file only turns its
/// ranges into `NSAttributedString` attributes.
@MainActor
enum MarkdownLiveStyler {
    /// Body text size for a note, and the size every other measurement here
    /// is derived from.
    static let bodySize: CGFloat = 14

    /// Documents past this length are left unstyled rather than reparsed on
    /// every keystroke: a note that big is a paste of something else, and a
    /// stutter while typing would be a worse failure than plain text.
    private static let styleLimit = 200_000

    /// The attributes raw Markdown mode uses, and the baseline live mode
    /// paints over.
    static var plainAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: Theme.NS.ink, .paragraphStyle: NSParagraphStyle.default]
    }

    /// Restyles the whole document from its own text.
    ///
    /// Whole-document rather than incremental: notes are short, and one
    /// keystroke can change the meaning of everything after it (opening a
    /// code fence, say), so a partial pass would be both wrong and barely
    /// faster.
    ///
    /// `selection` is the caret or selected range, and it decides where the
    /// syntax shows. Everywhere else the markers are hidden outright -- that
    /// is what makes this a renderer rather than a highlighter -- but on the
    /// line the caret is in they come back, so the thing being edited is
    /// always the thing on screen. Pass `nil` to hide every marker.
    static func style(_ storage: NSTextStorage, revealing selection: NSRange? = nil) {
        let source = storage.string
        let full = NSRange(location: 0, length: (source as NSString).length)
        guard full.length <= styleLimit else {
            reset(storage)
            return
        }

        storage.beginEditing()
        storage.setAttributes(plainAttributes, range: full)
        var revealedLines: [NSRange] = []
        for line in MarkdownLiveStyle.lines(in: source) {
            let revealed = isRevealed(line.range, by: selection)
            if revealed { revealedLines.append(line.range) }
            apply(line, to: storage, revealed: revealed)
        }
        for span in MarkdownLiveStyle.inlineSpans(in: source) {
            let revealed = revealedLines.contains { NSLocationInRange(span.range.location, $0) }
            apply(span, to: storage, revealed: revealed)
        }
        storage.endEditing()
    }

    /// The line the caret sits in, or every line a selection touches.
    ///
    /// Touching counts: a caret at the very end of a line is not "in" its
    /// range by `NSLocationInRange`, but it is unmistakably on that line as
    /// far as the person typing is concerned.
    private static func isRevealed(_ line: NSRange, by selection: NSRange?) -> Bool {
        guard let selection else { return false }
        return selection.location <= line.upperBound && selection.upperBound >= line.location
    }

    /// Returns the storage to unstyled source text -- raw Markdown mode, and
    /// the state live mode must leave behind when it is switched off.
    static func reset(_ storage: NSTextStorage) {
        let full = NSRange(location: 0, length: (storage.string as NSString).length)
        storage.beginEditing()
        storage.setAttributes(plainAttributes, range: full)
        storage.endEditing()
    }

    // MARK: - Block styling

    private static func apply(_ line: MarkdownLiveLine, to storage: NSTextStorage, revealed: Bool) {
        guard line.range.length > 0 else { return }
        let content = NSRange(
            location: line.marker.upperBound,
            length: max(0, line.range.upperBound - line.marker.upperBound)
        )

        switch line.kind {
        case .paragraph:
            break

        case .heading(let level):
            let font = headingFont(level: level)
            storage.addAttributes(
                [.font: font, .paragraphStyle: headingParagraph(level: level)],
                range: line.range
            )
            if revealed {
                // Back in view because the caret is here: the hashes are
                // what the user is editing, so they are dimmed rather than
                // hidden and set at body size to take as little room as
                // possible.
                dim(line.marker, in: storage, to: Theme.NS.inkTertiary, font: markerFont(for: font))
            } else {
                hide(line.marker, in: storage)
            }

        case .bullet, .task:
            var isTicked = false
            if case .task(_, let isDone) = line.kind { isTicked = isDone }
            storage.addAttributes(
                [.paragraphStyle: listParagraph(indentColumns: line.indentColumns, hanging: width(of: "\u{2022} ", in: bulletFont))],
                range: line.range
            )
            dim(line.marker, in: storage, to: Theme.NS.inkSecondary, font: nil)
            // The bullet is not syntax to hide: it is the rendering. The
            // hyphen's glyph is swapped for a dot -- or, on a task, for a
            // box -- and the characters behind it are left alone.
            var isBox = false
            var substitute = bulletGlyph
            if case .task = line.kind, !revealed, let box = isTicked ? tickedBoxGlyph : emptyBoxGlyph {
                substitute = box
                isBox = true
            }
            if let bullet = line.bulletCharacter, let substitute {
                // Semibold so the dot reads as a bullet rather than as a
                // stray full stop, and the glyph is taken from that same
                // font so its advance matches what is drawn.
                storage.addAttributes(
                    [.font: bulletFont, .glyphInfo: substitute],
                    range: bullet
                )
                // `- [x] ` collapses to the box: with the caret elsewhere
                // the brackets are noise, and the box says the same thing.
                // The marker's trailing space is left drawn, so the text
                // still stands off its box.
                if isBox {
                    hide(
                        NSRange(
                            location: bullet.upperBound,
                            length: max(0, line.marker.upperBound - bullet.upperBound - 1)
                        ),
                        in: storage
                    )
                }
            }
            // A ticked task is done with: it reads as struck through and
            // faded, the same as it does in the read-only preview.
            if isTicked, content.length > 0 {
                storage.addAttributes(
                    [
                        .foregroundColor: Theme.NS.inkTertiary,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .strikethroughColor: Theme.NS.inkTertiary
                    ],
                    range: content
                )
            }

        case .numbered:
            let hanging = width(of: String(repeating: "0", count: max(2, line.marker.length)))
            storage.addAttributes(
                [.paragraphStyle: listParagraph(indentColumns: line.indentColumns, hanging: hanging)],
                range: line.range
            )
            dim(line.marker, in: storage, to: Theme.NS.inkSecondary, font: nil)

        case .quote:
            storage.addAttributes(
                [
                    .paragraphStyle: listParagraph(
                        indentColumns: line.indentColumns,
                        hanging: width(of: "> "),
                        // With the marker hidden the first line has nothing
                        // occupying its width, so the indent has to be paid
                        // for by the paragraph instead or the quote's first
                        // line would sit left of its own wrapped text.
                        markerHidden: !revealed
                    )
                ],
                range: line.range
            )
            if revealed {
                dim(line.marker, in: storage, to: Theme.NS.inkTertiary, font: nil)
            } else {
                hide(line.marker, in: storage)
            }
            if content.length > 0 {
                storage.addAttributes(
                    [.font: italic(bodyFont), .foregroundColor: Theme.NS.inkSecondary],
                    range: content
                )
            }

        case .code:
            // No background fill: a run of per-line rectangles ending at each
            // line's last character reads as ragged scraps rather than as one
            // block, so a fenced block is set in mono and left at that.
            storage.addAttributes(
                [.font: monoFont, .paragraphStyle: codeParagraph()],
                range: line.range
            )
            // The fences themselves recede but stay drawn: hidden, they
            // would leave blank lines around the code with nothing to
            // explain them and nothing to put the caret on.
            let text = (storage.string as NSString)
                .substring(with: line.range)
                .trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("```") || text.hasPrefix("~~~") {
                dim(line.range, in: storage, to: Theme.NS.inkTertiary, font: nil)
            }

        case .divider:
            storage.addAttribute(.foregroundColor, value: Theme.NS.inkTertiary, range: line.range)
        }
    }

    private static func dim(
        _ range: NSRange,
        in storage: NSTextStorage,
        to colour: NSColor,
        font: NSFont?
    ) {
        guard range.length > 0 else { return }
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: colour]
        if let font { attributes[.font] = font }
        storage.addAttributes(attributes, range: range)
    }

    /// Marks a run as syntax that is kept in the text but not drawn.
    ///
    /// Only `MarkdownHiddenSyntaxLayout`, installed on the editor's layout
    /// manager, acts on this; the characters themselves are untouched.
    private static func hide(_ range: NSRange, in storage: NSTextStorage) {
        guard range.length > 0 else { return }
        storage.addAttribute(.markdownHidden, value: true, range: range)
        // A hidden glyph has no width but a decoration drawn across it still
        // finds the line: an underline or strikethrough left on a hidden run
        // shows up as a stray tick, most visibly where a link wraps.
        storage.addAttributes(
            [
                .underlineStyle: 0,
                .strikethroughStyle: 0
            ],
            range: range
        )
    }

    // MARK: - Inline styling

    private static func apply(_ span: MarkdownLiveInline, to storage: NSTextStorage, revealed: Bool) {
        guard span.range.length > 0 else { return }

        switch span.kind {
        case .strong:
            restyleFonts(in: span.range, of: storage) { bold($0) }
        case .emphasis:
            restyleFonts(in: span.range, of: storage) { italic($0) }
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.range)
        case .code:
            storage.addAttributes([.font: monoFont, .backgroundColor: Theme.NS.card], range: span.range)
        case .link:
            // Colour alone, no underline: with the `[` hidden and zero
            // width, AppKit still draws the label's underline across the
            // break when a link wraps, leaving a blue tick floating in the
            // right margin.
            storage.addAttributes(
                [
                    .foregroundColor: NSColor.controlAccentColor
                ],
                range: span.range
            )
        case .linkURL, .syntax:
            // The delimiters and the URL are the markup itself: shown only
            // where the caret is, and then only faintly.
            if revealed {
                storage.addAttribute(.foregroundColor, value: Theme.NS.inkTertiary, range: span.range)
            } else {
                hide(span.range, in: storage)
            }
        }
    }

    /// Adds a trait to whatever font each run in `range` already has, so bold
    /// inside a heading stays heading-sized.
    private static func restyleFonts(
        in range: NSRange,
        of storage: NSTextStorage,
        transform: (NSFont) -> NSFont
    ) {
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? bodyFont
            storage.addAttribute(.font, value: transform(font), range: subrange)
        }
    }

    // MARK: - Fonts and metrics

    private static let bodyFont = NSFont.systemFont(ofSize: bodySize)

    private static let monoFont = NSFont.monospacedSystemFont(ofSize: bodySize - 1, weight: .regular)

    /// Heading sizes match `MarkdownPreview`, so switching between live mode
    /// and the read-only preview is not a change of typography.
    private static func headingFont(level: Int) -> NSFont {
        let size: CGFloat
        switch level {
        case 1: size = 22
        case 2: size = 19
        case 3: size = 17
        case 4: size = 15
        case 5: size = 14
        default: size = 13
        }
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        // Rounded for the display sizes only, exactly as the preview does it.
        guard level <= 2,
              let descriptor = base.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: size)
        else { return base }
        return rounded
    }

    /// The `#` run is drawn at body size whatever the heading's size, so it
    /// takes as little room as possible in a narrow panel.
    private static func markerFont(for font: NSFont) -> NSFont {
        NSFont.systemFont(ofSize: min(bodySize, font.pointSize), weight: .regular)
    }

    private static func bold(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    private static func italic(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    private static func width(of marker: String) -> CGFloat {
        width(of: marker, in: bodyFont)
    }

    private static func width(of marker: String, in font: NSFont) -> CGFloat {
        (marker as NSString).size(withAttributes: [.font: font]).width
    }

    /// One indent level of a nested list, in points.
    private static let indentStep: CGFloat = 14

    private static func listParagraph(
        indentColumns: Int,
        hanging: CGFloat,
        markerHidden: Bool = false
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let indent = CGFloat(indentColumns / 2) * indentStep
        style.firstLineHeadIndent = indent + (markerHidden ? hanging : 0)
        // Wrapped text lines up under the item's own text rather than back
        // under its marker -- the thing that makes a wrapped bullet read as
        // one item.
        style.headIndent = indent + hanging
        style.lineSpacing = 2
        return style
    }

    private static func headingParagraph(level: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        // A heading belongs to what follows it, so the air goes above.
        style.paragraphSpacingBefore = level <= 2 ? 10 : 6
        style.paragraphSpacing = 2
        return style
    }

    /// Fenced code is indented instead of filled, which is enough to set it
    /// apart from prose without a ragged background.
    private static func codeParagraph() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 6
        style.headIndent = 6
        return style
    }

    /// The bullet is drawn from a semibold face, so it needs its own font.
    private static let bulletFont = NSFont.systemFont(ofSize: bodySize, weight: .semibold)

    /// The bullet drawn in place of a `-`.
    ///
    /// Built once: resolving a glyph means a Core Text lookup, and this is
    /// wanted on every list line of every restyle.
    private static let bulletGlyph = substitution(for: "\u{2022}")

    /// An empty box, drawn in place of a task's `-` while its `[ ]` is
    /// hidden. `U+25A1` rather than the ballot box `U+2610`, which the
    /// system font does not have.
    private static let emptyBoxGlyph = substitution(for: "\u{25A1}")

    /// A ticked ballot box, likewise standing in for the `-` of `- [x]`.
    private static let tickedBoxGlyph = substitution(for: "\u{2611}")

    /// Resolves `character` to a glyph of `bulletFont`, ready to be drawn in
    /// place of a `-`.
    ///
    /// `baseString` is the character actually stored, so the substitution
    /// never reaches the text: copying still yields `"- "`. A character the
    /// font lacks yields `nil`, and the marker is left as written rather
    /// than drawn blank.
    private static func substitution(for character: String) -> NSGlyphInfo? {
        var characters = Array(character.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(bulletFont as CTFont, &characters, &glyphs, characters.count),
              let glyph = glyphs.first,
              glyph != 0
        else { return nil }
        return NSGlyphInfo(cgGlyph: glyph, for: bulletFont, baseString: "-")
    }
}
