import XCTest
@testable import Ledge

final class MarkdownLiveStyleTests: XCTestCase {

    // MARK: - Helpers

    /// Finds the UTF-16 range of the `occurrence`-th match of `substring`
    /// within `text` (0-based), so tests can describe expected ranges in
    /// terms of readable text rather than hand-counted offsets.
    private func range(of substring: String, in text: String, occurrence: Int = 0) -> NSRange {
        let ns = text as NSString
        var searchStart = 0
        var found = NSRange(location: NSNotFound, length: 0)
        for _ in 0...occurrence {
            let remaining = NSRange(location: searchStart, length: ns.length - searchStart)
            found = ns.range(of: substring, options: [], range: remaining)
            guard found.location != NSNotFound else { return found }
            searchStart = found.location + found.length
        }
        return found
    }

    // MARK: - The headline behaviour: "- " becomes a bullet, "-" alone does not

    func testLoneDashStaysAPlainParagraph() {
        let lines = MarkdownLiveStyle.lines(in: "-")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].kind, .paragraph)
        XCTAssertEqual(lines[0].marker, NSRange(location: 0, length: 0))
        XCTAssertNil(lines[0].bulletCharacter)
    }

    func testDashFollowedByTextButNoSpaceStaysAPlainParagraph() {
        XCTAssertEqual(MarkdownLiveStyle.lines(in: "-foo").first!.kind, .paragraph)
    }

    func testDashSpaceBecomesABulletTheInstantTheSpaceIsTyped() {
        let source = "- "
        let lines = MarkdownLiveStyle.lines(in: source)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].kind, .bullet(depth: 0))
        XCTAssertEqual(lines[0].marker, NSRange(location: 0, length: 2))
        XCTAssertEqual(lines[0].bulletCharacter, NSRange(location: 0, length: 1))
    }

    func testAllThreeBulletCharactersAreRecognised() {
        for character in ["-", "*", "+"] {
            let source = "\(character) item"
            let line = MarkdownLiveStyle.lines(in: source).first!
            XCTAssertEqual(line.kind, .bullet(depth: 0), character)
            XCTAssertEqual(line.marker, NSRange(location: 0, length: 2), character)
            XCTAssertEqual(line.bulletCharacter, NSRange(location: 0, length: 1), character)
        }
    }

    // MARK: - Tasks

    func testTaskLinesTrackDoneAndUndoneState() {
        let undone = MarkdownLiveStyle.lines(in: "- [ ] todo").first!
        XCTAssertEqual(undone.kind, .task(depth: 0, isDone: false))
        XCTAssertEqual(undone.marker, NSRange(location: 0, length: 6))
        XCTAssertEqual(undone.bulletCharacter, NSRange(location: 0, length: 1))

        let done = MarkdownLiveStyle.lines(in: "- [x] done").first!
        XCTAssertEqual(done.kind, .task(depth: 0, isDone: true))
        XCTAssertEqual(done.marker, NSRange(location: 0, length: 6))

        let doneUppercase = MarkdownLiveStyle.lines(in: "- [X] done").first!
        XCTAssertEqual(doneUppercase.kind, .task(depth: 0, isDone: true))
    }

    func testInvalidTaskStatusFallsBackToAPlainBullet() {
        let line = MarkdownLiveStyle.lines(in: "- [y] not a task").first!
        XCTAssertEqual(line.kind, .bullet(depth: 0))
        XCTAssertEqual(line.marker, NSRange(location: 0, length: 2))
    }

    // MARK: - Numbered lists

    func testNumberedListsSupportDotAndParenDelimiters() {
        let dot = MarkdownLiveStyle.lines(in: "1. first").first!
        XCTAssertEqual(dot.kind, .numbered(depth: 0))
        XCTAssertEqual(dot.marker, NSRange(location: 0, length: 3))
        XCTAssertNil(dot.bulletCharacter)

        let paren = MarkdownLiveStyle.lines(in: "2) second").first!
        XCTAssertEqual(paren.kind, .numbered(depth: 0))
        XCTAssertEqual(paren.marker, NSRange(location: 0, length: 3))
    }

    func testNumberWithoutASpaceStaysAPlainParagraph() {
        XCTAssertEqual(MarkdownLiveStyle.lines(in: "1.").first!.kind, .paragraph)
        XCTAssertEqual(MarkdownLiveStyle.lines(in: "2024 was busy").first!.kind, .paragraph)
    }

    func testNumberedListIndentationDepth() {
        let source = "1. first\n    2. nested"
        let lines = MarkdownLiveStyle.lines(in: source)
        XCTAssertEqual(lines[0].kind, .numbered(depth: 0))
        XCTAssertEqual(lines[1].kind, .numbered(depth: 2))
        XCTAssertEqual(lines[1].indentColumns, 4)
    }

    // MARK: - Headings

    func testHeadingLevelsAndClamping() {
        let source = """
        # One
        ## Two
        ###### Six
        ####### Seven clamps to six
        """
        let lines = MarkdownLiveStyle.lines(in: source)
        XCTAssertEqual(lines.count, 4)

        XCTAssertEqual(lines[0].kind, .heading(level: 1))
        XCTAssertEqual(lines[0].marker, range(of: "# ", in: source))

        XCTAssertEqual(lines[1].kind, .heading(level: 2))
        XCTAssertEqual(lines[1].marker, range(of: "## ", in: source))

        XCTAssertEqual(lines[2].kind, .heading(level: 6))
        XCTAssertEqual(lines[2].marker, range(of: "###### ", in: source))

        XCTAssertEqual(lines[3].kind, .heading(level: 6))
        XCTAssertEqual(lines[3].marker, range(of: "####### ", in: source))
    }

    func testHeadingWithNoTrailingTextIsStillAHeading() {
        XCTAssertEqual(MarkdownLiveStyle.lines(in: "##").first!.kind, .heading(level: 2))
    }

    // MARK: - Quotes

    func testQuoteLine() {
        let line = MarkdownLiveStyle.lines(in: "> quoted").first!
        XCTAssertEqual(line.kind, .quote)
        XCTAssertEqual(line.marker, NSRange(location: 0, length: 2))
    }

    func testBareQuoteMarkerWithNoFollowingSpace() {
        let line = MarkdownLiveStyle.lines(in: ">").first!
        XCTAssertEqual(line.kind, .quote)
        XCTAssertEqual(line.marker, NSRange(location: 0, length: 1))
    }

    // MARK: - Dividers vs. bullets

    func testDividerVariants() {
        for source in ["---", "***", "___", "- - -", "* * *", "-----"] {
            XCTAssertEqual(MarkdownLiveStyle.lines(in: source).first!.kind, .divider, source)
        }
    }

    func testTwoDashesIsNotADividerButIsStillABullet() {
        // Once spaces are stripped, "- -" is only two dashes, short of the
        // three a divider needs, so it falls through to bullet matching
        // with a lone trailing dash as its (unstyled) text.
        let line = MarkdownLiveStyle.lines(in: "- -").first!
        XCTAssertEqual(line.kind, .bullet(depth: 0))
    }

    func testDividerWinsOverBulletForThreeDashesSeparatedBySpaces() {
        let line = MarkdownLiveStyle.lines(in: "- - -").first!
        XCTAssertEqual(line.kind, .divider)
    }

    func testDividerAndCodeLinesHaveZeroLengthMarkers() {
        XCTAssertEqual(MarkdownLiveStyle.lines(in: "---").first!.marker.length, 0)
        let codeLines = MarkdownLiveStyle.lines(in: "```\ncode\n```")
        XCTAssertTrue(codeLines.allSatisfy { $0.marker.length == 0 })
    }

    // MARK: - Indentation

    func testIndentationDepthWithSpaces() {
        let source = "- top\n  - nested once\n    - nested twice"
        let lines = MarkdownLiveStyle.lines(in: source)
        XCTAssertEqual(lines[0].kind, .bullet(depth: 0))
        XCTAssertEqual(lines[0].indentColumns, 0)
        XCTAssertEqual(lines[1].kind, .bullet(depth: 1))
        XCTAssertEqual(lines[1].indentColumns, 2)
        XCTAssertEqual(lines[2].kind, .bullet(depth: 2))
        XCTAssertEqual(lines[2].indentColumns, 4)
    }

    func testTabIndentCountsAsFourColumnsAndTwoDepthLevels() {
        let line = MarkdownLiveStyle.lines(in: "\t- nested").first!
        XCTAssertEqual(line.indentColumns, 4)
        XCTAssertEqual(line.kind, .bullet(depth: 2))
    }

    // MARK: - Fenced code

    func testFencedCodeBlockClassifiesLinesAsCodeAndSuppressesInlineSpans() {
        let source = """
        before
        ```
        **not bold** `still code`
        ```
        after
        """
        let lines = MarkdownLiveStyle.lines(in: source)
        XCTAssertEqual(lines.map(\.kind), [.paragraph, .code, .code, .code, .paragraph])

        // Only "before" and "after" are outside the fence, and neither
        // contains inline syntax, so no spans should be produced at all.
        XCTAssertTrue(MarkdownLiveStyle.inlineSpans(in: source).isEmpty)
    }

    func testUnterminatedFenceRunsToTheEndOfTheDocument() {
        let lines = MarkdownLiveStyle.lines(in: "```\ncode\nmore code")
        XCTAssertEqual(lines.map(\.kind), [.code, .code, .code])
    }

    func testTildeFenceIsRecognisedTheSameAsBacktick() {
        let lines = MarkdownLiveStyle.lines(in: "~~~\ncode\n~~~\nafter")
        XCTAssertEqual(lines.map(\.kind), [.code, .code, .code, .paragraph])
    }

    // MARK: - Inline spans

    func testStrongSpanAndItsSyntaxRanges() {
        let source = "a **bold** b"
        let spans = MarkdownLiveStyle.inlineSpans(in: source)
        XCTAssertEqual(spans, [
            MarkdownLiveInline(kind: .syntax, range: range(of: "**", in: source, occurrence: 0)),
            MarkdownLiveInline(kind: .strong, range: range(of: "bold", in: source)),
            MarkdownLiveInline(kind: .syntax, range: range(of: "**", in: source, occurrence: 1))
        ])
    }

    func testEmphasisSpanAndItsSyntaxRanges() {
        let source = "a *italic* b"
        let spans = MarkdownLiveStyle.inlineSpans(in: source)
        XCTAssertEqual(spans, [
            MarkdownLiveInline(kind: .syntax, range: range(of: "*", in: source, occurrence: 0)),
            MarkdownLiveInline(kind: .emphasis, range: range(of: "italic", in: source)),
            MarkdownLiveInline(kind: .syntax, range: range(of: "*", in: source, occurrence: 1))
        ])
    }

    func testUnderscoreVariantsOfStrongAndEmphasis() {
        XCTAssertEqual(MarkdownLiveStyle.inlineSpans(in: "__bold__").map(\.kind), [.syntax, .strong, .syntax])
        XCTAssertEqual(MarkdownLiveStyle.inlineSpans(in: "_italic_").map(\.kind), [.syntax, .emphasis, .syntax])
    }

    func testStrikethroughSpanAndItsSyntaxRanges() {
        let source = "a ~~gone~~ b"
        let spans = MarkdownLiveStyle.inlineSpans(in: source)
        XCTAssertEqual(spans, [
            MarkdownLiveInline(kind: .syntax, range: range(of: "~~", in: source, occurrence: 0)),
            MarkdownLiveInline(kind: .strikethrough, range: range(of: "gone", in: source)),
            MarkdownLiveInline(kind: .syntax, range: range(of: "~~", in: source, occurrence: 1))
        ])
    }

    func testInlineCodeSpanAndItsSyntaxRanges() {
        let source = "a `code` b"
        let spans = MarkdownLiveStyle.inlineSpans(in: source)
        XCTAssertEqual(spans, [
            MarkdownLiveInline(kind: .syntax, range: range(of: "`", in: source, occurrence: 0)),
            MarkdownLiveInline(kind: .code, range: range(of: "code", in: source)),
            MarkdownLiveInline(kind: .syntax, range: range(of: "`", in: source, occurrence: 1))
        ])
    }

    func testInlineCodeWinsOverEmphasisInsideIt() {
        let spans = MarkdownLiveStyle.inlineSpans(in: "`a * b`")
        XCTAssertEqual(spans.map(\.kind), [.syntax, .code, .syntax])
    }

    func testLinkSpanAndItsSyntaxRanges() {
        let source = "see [a link](https://example.com) now"
        let spans = MarkdownLiveStyle.inlineSpans(in: source)
        XCTAssertEqual(spans, [
            MarkdownLiveInline(kind: .syntax, range: range(of: "[", in: source)),
            MarkdownLiveInline(kind: .link, range: range(of: "a link", in: source)),
            MarkdownLiveInline(kind: .syntax, range: range(of: "]", in: source)),
            MarkdownLiveInline(kind: .syntax, range: range(of: "(", in: source)),
            MarkdownLiveInline(kind: .linkURL, range: range(of: "https://example.com", in: source)),
            MarkdownLiveInline(kind: .syntax, range: range(of: ")", in: source))
        ])
    }

    func testMultipleInlineSpansOnOneLine() {
        let source = "**a** and *b*"
        let spans = MarkdownLiveStyle.inlineSpans(in: source)
        XCTAssertEqual(spans.map(\.kind), [.syntax, .strong, .syntax, .syntax, .emphasis, .syntax])
    }

    func testUnclosedDelimitersProduceNoSpan() {
        XCTAssertTrue(MarkdownLiveStyle.inlineSpans(in: "**bold").isEmpty)
        XCTAssertTrue(MarkdownLiveStyle.inlineSpans(in: "*italic").isEmpty)
        XCTAssertTrue(MarkdownLiveStyle.inlineSpans(in: "~~gone").isEmpty)
        XCTAssertTrue(MarkdownLiveStyle.inlineSpans(in: "`code").isEmpty)
        XCTAssertTrue(MarkdownLiveStyle.inlineSpans(in: "[label](url").isEmpty)
        XCTAssertTrue(MarkdownLiveStyle.inlineSpans(in: "[label without a url").isEmpty)
        XCTAssertTrue(MarkdownLiveStyle.inlineSpans(in: "a lone **").isEmpty)
    }

    // MARK: - Emoji-safe UTF-16 offsets

    func testEmojiSafeUTF16OffsetsForLinesAndInlineSpans() {
        let source = "😀 **bold** 🎉"
        let ns = source as NSString

        let lines = MarkdownLiveStyle.lines(in: source)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].range, NSRange(location: 0, length: ns.length))

        let spans = MarkdownLiveStyle.inlineSpans(in: source)
        XCTAssertEqual(spans.map(\.kind), [.syntax, .strong, .syntax])
        // "😀 " is a 2-unit surrogate pair plus a space, so the opening
        // "**" starts at UTF-16 offset 3, not character offset 2.
        XCTAssertEqual(spans[0].range, NSRange(location: 3, length: 2))
        XCTAssertEqual(ns.substring(with: spans[1].range), "bold")
        XCTAssertEqual(spans[2].range, NSRange(location: 9, length: 2))
    }

    // MARK: - Empty input

    func testEmptyInputReturnsOneEmptyParagraphLine() {
        XCTAssertEqual(MarkdownLiveStyle.lines(in: ""), [
            MarkdownLiveLine(
                kind: .paragraph,
                range: NSRange(location: 0, length: 0),
                marker: NSRange(location: 0, length: 0),
                bulletCharacter: nil,
                indentColumns: 0
            )
        ])
        XCTAssertTrue(MarkdownLiveStyle.inlineSpans(in: "").isEmpty)
    }

    func testEmptyLinesAreIncludedAtTheirOwnIndex() {
        let lines = MarkdownLiveStyle.lines(in: "first\n\nthird")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[1].kind, .paragraph)
        XCTAssertEqual(lines[1].range, NSRange(location: 6, length: 0))
    }

    // MARK: - Line endings

    func testCRLFLineEndingIsExcludedFromTheLineRange() {
        let lines = MarkdownLiveStyle.lines(in: "one\r\ntwo")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].range, NSRange(location: 0, length: 3))
        XCTAssertEqual(lines[1].range, NSRange(location: 5, length: 3))
    }

    func testLoneCarriageReturnIsTreatedAsALineBreak() {
        let lines = MarkdownLiveStyle.lines(in: "one\rtwo")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].range, NSRange(location: 0, length: 3))
        XCTAssertEqual(lines[1].range, NSRange(location: 4, length: 3))
    }

    func testTrailingNewlineProducesOneMoreEmptyLine() {
        let lines = MarkdownLiveStyle.lines(in: "a\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[1].kind, .paragraph)
        XCTAssertEqual(lines[1].range, NSRange(location: 2, length: 0))
    }
}
