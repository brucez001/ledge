import XCTest
@testable import Ledge

final class MarkdownDocumentTests: XCTestCase {
    func testEmptyInputReturnsNoBlocks() {
        XCTAssertEqual(MarkdownDocument.parse(""), [])
        XCTAssertEqual(MarkdownDocument.parse("   \n\n\t\n"), [])
    }

    func testHeadingLevelsAndTrailingHashesAreTrimmed() {
        let blocks = MarkdownDocument.parse("""
        # One
        ## Two
        ####### Seven clamps to six
        ### Trailing ###
        """)

        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "One"),
            .heading(level: 2, text: "Two"),
            .heading(level: 6, text: "Seven clamps to six"),
            .heading(level: 3, text: "Trailing")
        ])
    }

    func testConsecutivePlainLinesGroupIntoOneParagraph() {
        let blocks = MarkdownDocument.parse("""
        First line
        second line

        A new paragraph
        """)

        XCTAssertEqual(blocks, [
            .paragraph("First line\nsecond line"),
            .paragraph("A new paragraph")
        ])
    }

    func testBulletListWithIndent() {
        let blocks = MarkdownDocument.parse("""
        - top
          - nested once
        * still bullets
        """)

        XCTAssertEqual(blocks, [
            .bulletList([
                MarkdownListItem(text: "top", indent: 0),
                MarkdownListItem(text: "nested once", indent: 1),
                MarkdownListItem(text: "still bullets", indent: 0)
            ])
        ])
    }

    func testNumberedListWithIndent() {
        let blocks = MarkdownDocument.parse("""
        1. first
        2) second
            3. deeper
        """)

        XCTAssertEqual(blocks, [
            .numberedList([
                MarkdownListItem(text: "first", indent: 0),
                MarkdownListItem(text: "second", indent: 0),
                MarkdownListItem(text: "deeper", indent: 2)
            ])
        ])
    }

    func testTaskListTracksDoneAndUndoneAndIndent() {
        let blocks = MarkdownDocument.parse("""
        - [ ] undone
        - [x] done
          - [X] also done, nested
        """)

        XCTAssertEqual(blocks, [
            .taskList([
                MarkdownTaskItem(text: "undone", isDone: false, indent: 0),
                MarkdownTaskItem(text: "done", isDone: true, indent: 0),
                MarkdownTaskItem(text: "also done, nested", isDone: true, indent: 1)
            ])
        ])
    }

    func testTaskItemInsideABulletRunPromotesTheWholeRunToATaskList() {
        let blocks = MarkdownDocument.parse("""
        - plain bullet
        - [x] task bullet
        """)

        XCTAssertEqual(blocks, [
            .taskList([
                MarkdownTaskItem(text: "plain bullet", isDone: false, indent: 0),
                MarkdownTaskItem(text: "task bullet", isDone: true, indent: 0)
            ])
        ])
    }

    func testConsecutiveBlockquoteLinesCollapseIntoOneQuote() {
        let blocks = MarkdownDocument.parse("""
        > first
        > second

        Not quoted
        """)

        XCTAssertEqual(blocks, [
            .quote(["first", "second"]),
            .paragraph("Not quoted")
        ])
    }

    func testFencedCodeBlockWithLanguage() {
        let blocks = MarkdownDocument.parse("""
        ```swift
        let x = 1
        print(x)
        ```
        """)

        XCTAssertEqual(blocks, [
            .codeBlock(language: "swift", code: "let x = 1\nprint(x)")
        ])
    }

    func testFencedCodeBlockWithoutLanguage() {
        let blocks = MarkdownDocument.parse("""
        ```
        plain code
        ```
        """)

        XCTAssertEqual(blocks, [
            .codeBlock(language: nil, code: "plain code")
        ])
    }

    func testUnterminatedFenceRunsToTheEndOfTheText() {
        let blocks = MarkdownDocument.parse("""
        ```swift
        let x = 1
        """)

        XCTAssertEqual(blocks, [
            .codeBlock(language: "swift", code: "let x = 1")
        ])
    }

    func testDividerVariants() {
        let blocks = MarkdownDocument.parse("""
        ---

        ***

        ___

        - - -
        """)

        XCTAssertEqual(blocks, [.divider, .divider, .divider, .divider])
    }

    func testTablePadsShortRowsAndTruncatesLongRows() {
        let blocks = MarkdownDocument.parse("""
        | A | B | C |
        |---|---|---|
        | 1 | 2 | 3 |
        | short |
        | too | many | cells | here |
        """)

        XCTAssertEqual(blocks, [
            .table(
                header: ["A", "B", "C"],
                rows: [
                    ["1", "2", "3"],
                    ["short", "", ""],
                    ["too", "many", "cells"]
                ]
            )
        ])
    }
}
