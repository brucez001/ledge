import AppKit
import XCTest
@testable import Ledge

/// The live editor's defining behaviour: the Markdown syntax is in the
/// buffer and out of the picture, and it comes back exactly where the caret
/// is so it can still be edited.
@MainActor
final class MarkdownHiddenSyntaxTests: XCTestCase {

    // MARK: - What is hidden

    func testHeadingHashesAreHiddenAwayFromTheCaret() {
        let storage = NSTextStorage(string: "# Title\nbody")

        MarkdownLiveStyler.style(storage)

        XCTAssertTrue(isHidden(at: 0, in: storage))
        XCTAssertTrue(isHidden(at: 1, in: storage))
        XCTAssertFalse(isHidden(at: 2, in: storage))
        XCTAssertEqual(storage.string, "# Title\nbody")
    }

    func testEmphasisDelimitersAreHiddenButTheirTextIsNot() {
        let storage = NSTextStorage(string: "a **bold** b")

        MarkdownLiveStyler.style(storage)

        XCTAssertTrue(isHidden(at: 2, in: storage))
        XCTAssertTrue(isHidden(at: 3, in: storage))
        XCTAssertFalse(isHidden(at: 4, in: storage))
        XCTAssertTrue(isHidden(at: 8, in: storage))
        XCTAssertTrue(isHidden(at: 9, in: storage))
    }

    /// A link keeps its label and loses its plumbing: the brackets, the
    /// parentheses, and the URL itself.
    func testLinkShowsItsLabelAndHidesItsURL() {
        let source = "see [docs](https://example.com) now"
        let storage = NSTextStorage(string: source)

        MarkdownLiveStyler.style(storage)

        let label = (source as NSString).range(of: "docs")
        let url = (source as NSString).range(of: "https://example.com")
        XCTAssertTrue(isHidden(at: label.location - 1, in: storage))
        XCTAssertFalse(isHidden(at: label.location, in: storage))
        XCTAssertTrue(isHidden(at: url.location, in: storage))
        XCTAssertTrue(isHidden(at: url.upperBound, in: storage))
    }

    func testQuoteMarkerIsHiddenAndItsIndentIsPaidForByTheParagraph() {
        let storage = NSTextStorage(string: "> quoted")

        MarkdownLiveStyler.style(storage)

        XCTAssertTrue(isHidden(at: 0, in: storage))
        let style = storage.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.firstLineHeadIndent, style?.headIndent)
    }

    /// `- [x] ` becomes a single ticked box: the hyphen's glyph is swapped
    /// and the brackets behind it are not drawn.
    func testTaskMarkerCollapsesToABox() {
        let storage = NSTextStorage(string: "- [x] done")

        MarkdownLiveStyler.style(storage)

        XCTAssertNotNil(storage.attribute(.glyphInfo, at: 0, effectiveRange: nil))
        XCTAssertTrue(isHidden(at: 2, in: storage))
        XCTAssertTrue(isHidden(at: 4, in: storage))
        // The space before the text is left drawn, so the label stands off
        // its box.
        XCTAssertFalse(isHidden(at: 5, in: storage))
        XCTAssertEqual(storage.string, "- [x] done")
    }

    /// A fence is left visible: hidden, it would leave an unexplained blank
    /// line with nothing to put the caret on.
    func testCodeFencesStayVisible() {
        let storage = NSTextStorage(string: "```\nlet x = 1\n```")

        MarkdownLiveStyler.style(storage)

        XCTAssertFalse(isHidden(at: 0, in: storage))
    }

    // MARK: - What the caret brings back

    func testTheCaretsOwnLineShowsItsSyntax() {
        let storage = NSTextStorage(string: "# Title\n## Other")

        MarkdownLiveStyler.style(storage, revealing: NSRange(location: 3, length: 0))

        XCTAssertFalse(isHidden(at: 0, in: storage))
        XCTAssertTrue(isHidden(at: 8, in: storage))
    }

    func testTheCaretAtTheEndOfALineStillCountsAsBeingOnIt() {
        let storage = NSTextStorage(string: "# Title\nbody")

        MarkdownLiveStyler.style(storage, revealing: NSRange(location: 7, length: 0))

        XCTAssertFalse(isHidden(at: 0, in: storage))
    }

    func testASelectionRevealsEveryLineItTouches() {
        let storage = NSTextStorage(string: "# One\n# Two\n# Three")

        MarkdownLiveStyler.style(storage, revealing: NSRange(location: 4, length: 4))

        XCTAssertFalse(isHidden(at: 0, in: storage))
        XCTAssertFalse(isHidden(at: 6, in: storage))
        XCTAssertTrue(isHidden(at: 12, in: storage))
    }

    func testRevealedSyntaxIsDimmedRatherThanFullyInked() {
        let storage = NSTextStorage(string: "# Title")

        MarkdownLiveStyler.style(storage, revealing: NSRange(location: 0, length: 0))

        let marker = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let text = storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        XCTAssertEqual(marker, Theme.NS.inkTertiary)
        XCTAssertNotEqual(marker, text)
    }

    func testResetClearsHiding() {
        let storage = NSTextStorage(string: "# Title")
        MarkdownLiveStyler.style(storage)

        MarkdownLiveStyler.reset(storage)

        XCTAssertFalse(isHidden(at: 0, in: storage))
    }

    // MARK: - Glyph generation

    /// The attribute only marks the text; this is the part that actually
    /// stops it being drawn, and it is worth proving against a real layout
    /// manager rather than trusting the flag.
    func testHiddenCharactersGenerateNoGlyph() {
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        let storage = NSTextStorage(string: "# Title")
        storage.addLayoutManager(layoutManager)
        let hiding = MarkdownHiddenSyntaxLayout()
        layoutManager.delegate = hiding

        MarkdownLiveStyler.style(storage)
        layoutManager.ensureLayout(for: container)

        XCTAssertEqual(layoutManager.propertyForGlyph(at: 0), .null)
        XCTAssertEqual(layoutManager.propertyForGlyph(at: 1), .null)
        XCTAssertNotEqual(layoutManager.propertyForGlyph(at: 2), .null)
        // Hidden means undrawn, not deleted: the character is still there to
        // be saved, copied, and moved over.
        XCTAssertEqual(storage.string, "# Title")
    }

    func testHidingNarrowsTheDrawnLineWithoutShorteningTheText() {
        let hidden = drawnWidth(of: "**bold**", revealing: nil)
        let shown = drawnWidth(of: "**bold**", revealing: NSRange(location: 0, length: 0))

        XCTAssertLessThan(hidden, shown)
    }

    // MARK: - Helpers

    private func isHidden(at index: Int, in storage: NSTextStorage) -> Bool {
        storage.attribute(.markdownHidden, at: index, effectiveRange: nil) != nil
    }

    private func drawnWidth(of source: String, revealing selection: NSRange?) -> CGFloat {
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        let storage = NSTextStorage(string: source)
        storage.addLayoutManager(layoutManager)
        let hiding = MarkdownHiddenSyntaxLayout()
        layoutManager.delegate = hiding

        MarkdownLiveStyler.style(storage, revealing: selection)
        layoutManager.ensureLayout(for: container)
        return layoutManager.usedRect(for: container).width
    }
}
