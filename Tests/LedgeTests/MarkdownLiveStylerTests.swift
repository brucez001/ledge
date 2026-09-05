import AppKit
import XCTest
@testable import Ledge

/// The live styler is UI-adjacent but not UI-bound: it only ever reads and
/// writes an `NSTextStorage`, so its whole contract -- "restyle without
/// touching a character" -- is testable without a window.
@MainActor
final class MarkdownLiveStylerTests: XCTestCase {

    func testStylingNeverChangesTheText() {
        let source = "# Title\n- milk\n- [x] done\n\n> quoted\n"
        let storage = NSTextStorage(string: source)

        MarkdownLiveStyler.style(storage)

        XCTAssertEqual(storage.string, source)
    }

    /// The headline behaviour: a typed "- " is drawn as a bullet while the
    /// buffer still holds a hyphen, so the file stays plain Markdown.
    func testBulletMarkerIsDrawnWithASubstitutedGlyph() {
        let storage = NSTextStorage(string: "- milk")

        MarkdownLiveStyler.style(storage)

        XCTAssertNotNil(glyphInfo(at: 0, in: storage))
        XCTAssertEqual(storage.string.first, "-")
    }

    func testDashWithoutASpaceIsNotDrawnAsABullet() {
        let storage = NSTextStorage(string: "-milk")

        MarkdownLiveStyler.style(storage)

        XCTAssertNil(glyphInfo(at: 0, in: storage))
    }

    /// Text typed after the marker must not inherit the bullet's glyph: the
    /// substitution belongs to that one hyphen, not to the run it starts.
    func testTypingAfterTheMarkerDoesNotInheritTheBulletGlyph() {
        let storage = NSTextStorage(string: "- milk")
        MarkdownLiveStyler.style(storage)

        storage.replaceCharacters(in: NSRange(location: 6, length: 0), with: "-")
        MarkdownLiveStyler.style(storage)

        XCTAssertEqual(storage.string, "- milk-")
        XCTAssertNotNil(glyphInfo(at: 0, in: storage))
        XCTAssertNil(glyphInfo(at: 6, in: storage))
    }

    func testResetReturnsPlainSourceAttributes() {
        let storage = NSTextStorage(string: "# Title\n- milk")
        MarkdownLiveStyler.style(storage)

        MarkdownLiveStyler.reset(storage)

        XCTAssertNil(glyphInfo(at: 8, in: storage))
        XCTAssertEqual(font(at: 0, in: storage)?.pointSize, MarkdownLiveStyler.bodySize)
        XCTAssertEqual(font(at: 8, in: storage)?.pointSize, MarkdownLiveStyler.bodySize)
    }

    func testHeadingsAreLargerThanBodyTextAndStepDownByLevel() {
        let storage = NSTextStorage(string: "# One\n### Three\nbody")
        MarkdownLiveStyler.style(storage)

        let one = font(at: 2, in: storage)?.pointSize ?? 0
        let three = font(at: 10, in: storage)?.pointSize ?? 0
        let body = font(at: 17, in: storage)?.pointSize ?? 0

        XCTAssertGreaterThan(one, three)
        XCTAssertGreaterThan(three, body)
        XCTAssertEqual(body, MarkdownLiveStyler.bodySize)
    }

    func testFencedCodeIsSetInAMonospacedFace() {
        let storage = NSTextStorage(string: "```\nlet x = 1\n```\nprose")
        MarkdownLiveStyler.style(storage)

        XCTAssertTrue(font(at: 5, in: storage)?.isFixedPitch ?? false)
        XCTAssertFalse(font(at: 19, in: storage)?.isFixedPitch ?? true)
    }

    func testBoldInsideAHeadingKeepsTheHeadingSize() {
        let storage = NSTextStorage(string: "# A **big** title")
        MarkdownLiveStyler.style(storage)

        let heading = font(at: 2, in: storage)
        let bold = font(at: 7, in: storage)

        XCTAssertEqual(bold?.pointSize, heading?.pointSize)
        XCTAssertTrue(
            NSFontManager.shared.traits(of: bold ?? .systemFont(ofSize: 14)).contains(.boldFontMask)
        )
    }

    /// A pasted-in monster of a document is left plain rather than reparsed
    /// on every keystroke: plain text beats a stuttering editor.
    func testOversizedDocumentsAreLeftUnstyled() {
        let storage = NSTextStorage(string: String(repeating: "- item\n", count: 40_000))

        MarkdownLiveStyler.style(storage)

        XCTAssertNil(glyphInfo(at: 0, in: storage))
    }

    // MARK: - Helpers

    private func glyphInfo(at index: Int, in storage: NSTextStorage) -> NSGlyphInfo? {
        storage.attribute(.glyphInfo, at: index, effectiveRange: nil) as? NSGlyphInfo
    }

    private func font(at index: Int, in storage: NSTextStorage) -> NSFont? {
        storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }
}
