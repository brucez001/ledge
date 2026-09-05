import XCTest
@testable import Ledge

final class MarkdownListContinuationTests: XCTestCase {
    func testPlainLineDoesNotContinue() {
        XCTAssertNil(MarkdownListContinuation.continuation(for: "just prose"))
        XCTAssertNil(MarkdownListContinuation.continuation(for: ""))
        XCTAssertNil(MarkdownListContinuation.continuation(for: "# Heading"))
    }

    func testBulletContinues() {
        XCTAssertEqual(MarkdownListContinuation.continuation(for: "- first"), .marker("- "))
        XCTAssertEqual(MarkdownListContinuation.continuation(for: "* first"), .marker("* "))
        XCTAssertEqual(MarkdownListContinuation.continuation(for: "+ first"), .marker("+ "))
    }

    func testIndentIsPreserved() {
        XCTAssertEqual(MarkdownListContinuation.continuation(for: "    - nested"), .marker("    - "))
        XCTAssertEqual(MarkdownListContinuation.continuation(for: "\t> quoted"), .marker("\t> "))
    }

    func testNumberedListIncrements() {
        XCTAssertEqual(MarkdownListContinuation.continuation(for: "1. first"), .marker("2. "))
        XCTAssertEqual(MarkdownListContinuation.continuation(for: "9) ninth"), .marker("10) "))
    }

    func testTaskContinuesUnchecked() {
        XCTAssertEqual(MarkdownListContinuation.continuation(for: "- [ ] todo"), .marker("- [ ] "))
        XCTAssertEqual(MarkdownListContinuation.continuation(for: "- [x] done"), .marker("- [ ] "))
        XCTAssertEqual(MarkdownListContinuation.continuation(for: "- [X] done"), .marker("- [ ] "))
    }

    func testQuoteContinues() {
        XCTAssertEqual(MarkdownListContinuation.continuation(for: "> quoted"), .marker("> "))
    }

    func testEmptyItemEndsTheRun() {
        XCTAssertEqual(MarkdownListContinuation.continuation(for: "- "), .clear(""))
        XCTAssertEqual(MarkdownListContinuation.continuation(for: "-"), .clear(""))
        XCTAssertEqual(MarkdownListContinuation.continuation(for: "1."), .clear(""))
        XCTAssertEqual(MarkdownListContinuation.continuation(for: "  - [ ]  "), .clear(""))
        XCTAssertEqual(MarkdownListContinuation.continuation(for: ">"), .clear(""))
    }

    func testNumberWithoutASeparatorIsNotAList() {
        XCTAssertNil(MarkdownListContinuation.continuation(for: "2024 was busy"))
    }
}

@MainActor
final class MarkdownEditorProxyTests: XCTestCase {
    func testMinimalChangeCoversOnlyTheEditedSpan() {
        let (range, replacement) = MarkdownEditorProxy.minimalChange(
            from: "one two three",
            to: "one **two** three"
        )

        XCTAssertEqual(range, NSRange(location: 4, length: 3))
        XCTAssertEqual(replacement, "**two**")
    }

    func testMinimalChangeOfIdenticalTextIsEmpty() {
        let (range, replacement) = MarkdownEditorProxy.minimalChange(from: "same", to: "same")

        XCTAssertEqual(range.length, 0)
        XCTAssertEqual(replacement, "")
    }

    func testMinimalChangeNeverSplitsASurrogatePair() {
        // Two different emoji can share a high surrogate, so a naive
        // code-unit prefix would stop between the halves of one glyph.
        let (range, replacement) = MarkdownEditorProxy.minimalChange(from: "a😀b", to: "a😁b")
        let old = "a😀b" as NSString

        XCTAssertEqual(old.substring(with: range), "😀")
        XCTAssertEqual(replacement, "😁")
    }

    func testMinimalChangeHandlesDeletion() {
        let (range, replacement) = MarkdownEditorProxy.minimalChange(from: "- item", to: "item")

        XCTAssertEqual(range, NSRange(location: 0, length: 2))
        XCTAssertEqual(replacement, "")
    }
}
