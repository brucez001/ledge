import XCTest
@testable import Ledge

final class MarkdownEditingTests: XCTestCase {

    // MARK: - Helpers

    /// Finds the UTF-16 range of `substring` within `text`, so tests can
    /// describe selections in terms of readable text rather than hand-counted
    /// offsets.
    private func range(of substring: String, in text: String) -> NSRange {
        (text as NSString).range(of: substring)
    }

    private func caret(at substring: String, in text: String) -> NSRange {
        let found = range(of: substring, in: text)
        return NSRange(location: found.location, length: 0)
    }

    // MARK: - Inline wrap / unwrap

    func testBoldWrapsANonEmptySelection() {
        let text = "hello world"
        let edit = MarkdownEditing.apply(.bold, to: text, selection: range(of: "world", in: text))

        XCTAssertEqual(edit.text, "hello **world**")
        XCTAssertEqual(edit.selection, range(of: "world", in: edit.text))
    }

    func testBoldUnwrapsWhenTheSelectionIsExactlyWrapped() {
        let text = "hello **world**"
        let edit = MarkdownEditing.apply(.bold, to: text, selection: range(of: "**world**", in: text))

        XCTAssertEqual(edit.text, "hello world")
        XCTAssertEqual(edit.selection, range(of: "world", in: edit.text))
    }

    func testBoldUnwrapsWhenMarkersSitImmediatelyOutsideTheSelection() {
        let text = "hello **world**"
        let edit = MarkdownEditing.apply(.bold, to: text, selection: range(of: "world", in: text))

        XCTAssertEqual(edit.text, "hello world")
        XCTAssertEqual(edit.selection, range(of: "world", in: edit.text))
    }

    func testItalicWrapsANonEmptySelection() {
        let text = "a plain word"
        let edit = MarkdownEditing.apply(.italic, to: text, selection: range(of: "plain", in: text))

        XCTAssertEqual(edit.text, "a *plain* word")
        XCTAssertEqual(edit.selection, range(of: "plain", in: edit.text))
    }

    func testItalicUnwrapsAnExactlyWrappedSelection() {
        let text = "a *plain* word"
        let edit = MarkdownEditing.apply(.italic, to: text, selection: range(of: "*plain*", in: text))

        XCTAssertEqual(edit.text, "a plain word")
    }

    func testStrikethroughWrapsANonEmptySelection() {
        let text = "keep dropped word"
        let edit = MarkdownEditing.apply(.strikethrough, to: text, selection: range(of: "dropped", in: text))

        XCTAssertEqual(edit.text, "keep ~~dropped~~ word")
        XCTAssertEqual(edit.selection, range(of: "dropped", in: edit.text))
    }

    func testStrikethroughUnwrapsAnExactlyWrappedSelection() {
        let text = "keep ~~dropped~~ word"
        let edit = MarkdownEditing.apply(.strikethrough, to: text, selection: range(of: "~~dropped~~", in: text))

        XCTAssertEqual(edit.text, "keep dropped word")
    }

    func testInlineCodeWrapsANonEmptySelection() {
        let text = "run make build"
        let edit = MarkdownEditing.apply(.inlineCode, to: text, selection: range(of: "make build", in: text))

        XCTAssertEqual(edit.text, "run `make build`")
        XCTAssertEqual(edit.selection, range(of: "make build", in: edit.text))
    }

    func testInlineCodeUnwrapsAnExactlyWrappedSelection() {
        let text = "run `make build`"
        let edit = MarkdownEditing.apply(.inlineCode, to: text, selection: range(of: "`make build`", in: text))

        XCTAssertEqual(edit.text, "run make build")
    }

    // MARK: - Inline caret behaviour

    func testBoldOnACaretInsertsAnEmptyMarkerPairWithTheCaretBetween() {
        let text = "  "
        let edit = MarkdownEditing.apply(.bold, to: text, selection: NSRange(location: 1, length: 0))

        XCTAssertEqual(edit.text, " **** ")
        XCTAssertEqual(edit.selection, NSRange(location: 3, length: 0))
    }

    func testBoldOnACaretInsideAWordWrapsTheWholeWord() {
        let text = "hello world"
        // Caret between the two 'l's in "hello".
        let caretLocation = range(of: "hello", in: text).location + 3
        let edit = MarkdownEditing.apply(.bold, to: text, selection: NSRange(location: caretLocation, length: 0))

        XCTAssertEqual(edit.text, "**hello** world")
        XCTAssertEqual(edit.selection, range(of: "hello", in: edit.text))
    }

    // MARK: - Multi-line list/quote toggling

    func testBulletListMarksEveryAffectedLine() {
        let text = "milk\neggs\nbread"
        let selection = NSRange(location: 0, length: (text as NSString).length)
        let edit = MarkdownEditing.apply(.bulletList, to: text, selection: selection)

        XCTAssertEqual(edit.text, "- milk\n- eggs\n- bread")
    }

    func testBulletListTogglesOffWhenEveryLineAlreadyHasIt() {
        let text = "- milk\n- eggs"
        let selection = NSRange(location: 0, length: (text as NSString).length)
        let edit = MarkdownEditing.apply(.bulletList, to: text, selection: selection)

        XCTAssertEqual(edit.text, "milk\neggs")
    }

    func testNumberedListRenumbersTheAffectedRun() {
        let text = "milk\neggs\nbread"
        let selection = NSRange(location: 0, length: (text as NSString).length)
        let edit = MarkdownEditing.apply(.numberedList, to: text, selection: selection)

        XCTAssertEqual(edit.text, "1. milk\n2. eggs\n3. bread")
    }

    func testNumberedListTogglesOffRegardlessOfExistingNumbers() {
        let text = "1. milk\n7. eggs"
        let selection = NSRange(location: 0, length: (text as NSString).length)
        let edit = MarkdownEditing.apply(.numberedList, to: text, selection: selection)

        XCTAssertEqual(edit.text, "milk\neggs")
    }

    func testTaskListMarksACaretLine() {
        let text = "buy milk"
        let edit = MarkdownEditing.apply(.taskList, to: text, selection: NSRange(location: 2, length: 0))

        XCTAssertEqual(edit.text, "- [ ] buy milk")
    }

    func testTaskListTogglesOff() {
        let text = "- [ ] buy milk"
        let edit = MarkdownEditing.apply(.taskList, to: text, selection: NSRange(location: 2, length: 0))

        XCTAssertEqual(edit.text, "buy milk")
    }

    func testQuoteMarksEveryAffectedLine() {
        let text = "line one\nline two"
        let selection = NSRange(location: 0, length: (text as NSString).length)
        let edit = MarkdownEditing.apply(.quote, to: text, selection: selection)

        XCTAssertEqual(edit.text, "> line one\n> line two")
    }

    func testQuoteTogglesOff() {
        let text = "> line one\n> line two"
        let selection = NSRange(location: 0, length: (text as NSString).length)
        let edit = MarkdownEditing.apply(.quote, to: text, selection: selection)

        XCTAssertEqual(edit.text, "line one\nline two")
    }

    // MARK: - Marker replacement, indentation, and mixed runs

    func testSwitchingFromBulletToNumberedReplacesTheMarker() {
        let text = "- milk\n- eggs"
        let selection = NSRange(location: 0, length: (text as NSString).length)
        let edit = MarkdownEditing.apply(.numberedList, to: text, selection: selection)

        XCTAssertEqual(edit.text, "1. milk\n2. eggs")
    }

    func testApplyingAMarkerToAMixedRunNormalisesAllLines() {
        // Only one of the two lines is a bullet, so pressing bullet again
        // should normalise both rather than toggle off.
        let text = "- milk\neggs"
        let selection = NSRange(location: 0, length: (text as NSString).length)
        let edit = MarkdownEditing.apply(.bulletList, to: text, selection: selection)

        XCTAssertEqual(edit.text, "- milk\n- eggs")
    }

    func testLeadingIndentationIsPreservedWhenAddingAMarker() {
        let text = "  milk"
        let edit = MarkdownEditing.apply(.bulletList, to: text, selection: NSRange(location: 2, length: 0))

        XCTAssertEqual(edit.text, "  - milk")
    }

    func testLeadingIndentationIsPreservedWhenRemovingAMarker() {
        let text = "  - milk"
        let edit = MarkdownEditing.apply(.bulletList, to: text, selection: NSRange(location: 2, length: 0))

        XCTAssertEqual(edit.text, "  milk")
    }

    // MARK: - Headings

    func testHeadingAppliesTheRequestedLevel() {
        let text = "Title"
        let edit = MarkdownEditing.apply(.heading(2), to: text, selection: NSRange(location: 0, length: 0))

        XCTAssertEqual(edit.text, "## Title")
    }

    func testHeadingTogglesOffAtTheSameLevel() {
        let text = "## Title"
        let edit = MarkdownEditing.apply(.heading(2), to: text, selection: NSRange(location: 0, length: 0))

        XCTAssertEqual(edit.text, "Title")
    }

    func testHeadingReplacesADifferentLevel() {
        let text = "## Title"
        let edit = MarkdownEditing.apply(.heading(1), to: text, selection: NSRange(location: 0, length: 0))

        XCTAssertEqual(edit.text, "# Title")
    }

    // MARK: - Code block

    func testCodeBlockWrapsTheAffectedLines() {
        let text = "let x = 1\nlet y = 2"
        let selection = NSRange(location: 0, length: (text as NSString).length)
        let edit = MarkdownEditing.apply(.codeBlock, to: text, selection: selection)

        XCTAssertEqual(edit.text, "```\nlet x = 1\nlet y = 2\n```")
    }

    func testCodeBlockUnwrapsAnExactlyFencedSelection() {
        let text = "```\nlet x = 1\n```"
        let selection = NSRange(location: 0, length: (text as NSString).length)
        let edit = MarkdownEditing.apply(.codeBlock, to: text, selection: selection)

        XCTAssertEqual(edit.text, "let x = 1")
    }

    func testCodeBlockOnABlankCaretLineInsertsAnEmptyFenceWithTheCaretInside() {
        let text = ""
        let edit = MarkdownEditing.apply(.codeBlock, to: text, selection: NSRange(location: 0, length: 0))

        XCTAssertEqual(edit.text, "```\n\n```")
        XCTAssertEqual(edit.selection, NSRange(location: 4, length: 0))
    }

    // MARK: - Link

    func testLinkWrapsSelectedTextAndSelectsTheURLPlaceholder() {
        let text = "see the docs"
        let edit = MarkdownEditing.apply(.link, to: text, selection: range(of: "the docs", in: text))

        XCTAssertEqual(edit.text, "see [the docs](url)")
        XCTAssertEqual(edit.selection, range(of: "url", in: edit.text))
    }

    func testLinkOnASelectedURLSelectsTheTextPlaceholder() {
        let text = "see https://example.com later"
        let edit = MarkdownEditing.apply(.link, to: text, selection: range(of: "https://example.com", in: text))

        XCTAssertEqual(edit.text, "see [text](https://example.com) later")
        XCTAssertEqual(edit.selection, range(of: "text", in: edit.text))
    }

    func testLinkOnACaretInsertsAnEmptyLinkAndSelectsTheURLPlaceholder() {
        let text = "notes: "
        let edit = MarkdownEditing.apply(.link, to: text, selection: NSRange(location: (text as NSString).length, length: 0))

        XCTAssertEqual(edit.text, "notes: [](url)")
        XCTAssertEqual(edit.selection, range(of: "url", in: edit.text))
    }

    // MARK: - Divider and table

    func testDividerMidLineInsertsItAfterTheCurrentLine() {
        let text = "first line\nsecond line"
        // Caret in the middle of "first line".
        let caretLocation = range(of: "first", in: text).location + 2
        let edit = MarkdownEditing.apply(.divider, to: text, selection: NSRange(location: caretLocation, length: 0))

        XCTAssertEqual(edit.text, "first line\n---\nsecond line")
        XCTAssertEqual(edit.selection, caret(at: "second line", in: edit.text))
    }

    func testDividerAtTheEndOfTheDocumentAddsALineForTheCaret() {
        let text = "only line"
        let edit = MarkdownEditing.apply(.divider, to: text, selection: NSRange(location: (text as NSString).length, length: 0))

        XCTAssertEqual(edit.text, "only line\n---\n")
        XCTAssertEqual(edit.selection, NSRange(location: (edit.text as NSString).length, length: 0))
    }

    func testTableInsertsAStarterTableAndSelectsTheFirstHeaderCell() {
        let text = "notes"
        let edit = MarkdownEditing.apply(.table, to: text, selection: NSRange(location: (text as NSString).length, length: 0))

        XCTAssertEqual(edit.text, "notes\n| Column | Column |\n| --- | --- |\n|  |  |")
        XCTAssertEqual(edit.selection, range(of: "Column", in: edit.text))
    }

    // MARK: - Clear formatting

    func testClearFormattingStripsLineMarkersAndInlineMarkers() {
        let text = "## **Title** with `code` and ~~gone~~"
        let edit = MarkdownEditing.apply(.clearFormatting, to: text, selection: NSRange(location: 0, length: 0))

        XCTAssertEqual(edit.text, "Title with code and gone")
    }

    func testClearFormattingCollapsesLinksToTheirText() {
        let text = "- see [the guide](https://example.com/guide) first"
        let edit = MarkdownEditing.apply(.clearFormatting, to: text, selection: NSRange(location: 0, length: 0))

        XCTAssertEqual(edit.text, "see the guide first")
    }

    // MARK: - Selection safety

    func testOutOfBoundsSelectionIsClampedRatherThanTrapping() {
        let text = "short "
        let edit = MarkdownEditing.apply(.bold, to: text, selection: NSRange(location: 100, length: 20))

        XCTAssertEqual(edit.text, "short ****")
        XCTAssertEqual(edit.selection, NSRange(location: 8, length: 0))
    }

    func testNegativeSelectionLocationIsClampedToTheStartOfTheDocument() {
        let text = " short"
        let edit = MarkdownEditing.apply(.italic, to: text, selection: NSRange(location: -5, length: -3))

        XCTAssertEqual(edit.text, "** short")
        XCTAssertEqual(edit.selection, NSRange(location: 1, length: 0))
    }

    // MARK: - UTF-16 / emoji offsets

    func testBoldAfterAnEmojiUsesUTF16OffsetsNotCharacterCounts() {
        // "🎉" is two UTF-16 code units, so a naive `String.count`-based
        // implementation would misplace the wrap by one unit here.
        let text = "🎉 party time"
        let edit = MarkdownEditing.apply(.bold, to: text, selection: range(of: "party", in: text))

        XCTAssertEqual(edit.text, "🎉 **party** time")
        XCTAssertEqual(edit.selection, range(of: "party", in: edit.text))
        XCTAssertEqual(edit.selection.location, ("🎉 **" as NSString).length)
    }
}
