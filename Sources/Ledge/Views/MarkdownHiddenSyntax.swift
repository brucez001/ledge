import AppKit

extension NSAttributedString.Key {
    /// Marks a run of Markdown syntax that is present in the buffer but not
    /// drawn: the `#` of a heading, the `**` around bold, a link's URL.
    ///
    /// The attribute changes nothing by itself. `MarkdownHiddenSyntaxLayout`
    /// is what acts on it, and only while it is a layout manager's delegate,
    /// so the same styled storage is still perfectly legible source anywhere
    /// else it is used.
    static let markdownHidden = NSAttributedString.Key("ledge.markdownHidden")
}

/// Stops marked-up syntax from being drawn, without deleting it.
///
/// A live note holds the plain Markdown source the file will be saved as, so
/// the syntax cannot be removed from the text -- but leaving `**` and `#`
/// on screen is not "rendering" either. The way out is the one layer between
/// characters and pixels: glyph generation. Every character marked
/// `.markdownHidden` is given the `.null` glyph property, which means the
/// layout manager keeps the character, keeps its character index, and simply
/// draws nothing and advances by nothing.
///
/// So the buffer, the file, `⌘C`, and word-by-word movement all still see
/// `**bold**`, while the reader sees the formatted text.
///
/// This is TextKit 1 only -- `NSTextLayoutManager` has no equivalent hook --
/// which is why the editor builds its text stack by hand.
final class MarkdownHiddenSyntaxLayout: NSObject, NSLayoutManagerDelegate {
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let storage = layoutManager.textStorage, glyphRange.length > 0 else { return 0 }
        let length = storage.length

        var replacements = [NSLayoutManager.GlyphProperty](repeating: [], count: glyphRange.length)
        var hidesAnything = false
        for offset in 0..<glyphRange.length {
            let index = characterIndexes[offset]
            guard index >= 0, index < length else {
                replacements[offset] = properties[offset]
                continue
            }
            if storage.attribute(.markdownHidden, at: index, effectiveRange: nil) != nil {
                replacements[offset] = .null
                hidesAnything = true
            } else {
                replacements[offset] = properties[offset]
            }
        }

        // Returning 0 leaves the layout manager's own glyphs in place, which
        // is the cheaper path for the majority of runs that hide nothing.
        guard hidesAnything else { return 0 }
        layoutManager.setGlyphs(
            glyphs,
            properties: &replacements,
            characterIndexes: characterIndexes,
            font: font,
            forGlyphRange: glyphRange
        )
        return glyphRange.length
    }
}
