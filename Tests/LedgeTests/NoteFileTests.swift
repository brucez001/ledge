import XCTest
@testable import Ledge

final class NoteFileTests: XCTestCase {
    func testParsesTheTitleAndKeepsTheBody() {
        let parsed = NoteFile.parse("---\ntitle: Shopping list\n---\n# Weekend\n- milk")

        XCTAssertEqual(parsed.title, "Shopping list")
        XCTAssertEqual(parsed.body, "# Weekend\n- milk")
        XCTAssertTrue(parsed.extraFrontMatter.isEmpty)
    }

    func testAFileWithoutFrontMatterIsAllBody() {
        let parsed = NoteFile.parse("# Weekend\n- milk")

        XCTAssertEqual(parsed.title, "")
        XCTAssertEqual(parsed.body, "# Weekend\n- milk")
    }

    func testALeadingDividerIsNotFrontMatter() {
        // A note may legitimately open with a horizontal rule; without a
        // closing delimiter the text is all body.
        let parsed = NoteFile.parse("---\n# Real title")

        XCTAssertEqual(parsed.title, "")
        XCTAssertEqual(parsed.body, "---\n# Real title")
    }

    func testUnknownKeysAreKept() {
        let parsed = NoteFile.parse("---\ntitle: Kept\ntags: work\n---\nbody")

        XCTAssertEqual(parsed.extraFrontMatter, ["tags: work"])
        XCTAssertEqual(
            NoteFile.serialise(
                title: parsed.title,
                extraFrontMatter: parsed.extraFrontMatter,
                body: parsed.body
            ),
            "---\ntitle: Kept\ntags: work\n---\nbody"
        )
    }

    func testHorizontalRulesWithoutATitleFieldStayInTheBody() {
        let text = "---\nordinary text\n---\nbody"
        let parsed = NoteFile.parse(text)

        XCTAssertEqual(parsed.title, "")
        XCTAssertEqual(parsed.body, text)
    }

    func testSerialiseOmitsFrontMatterForAnUnnamedNote() {
        XCTAssertEqual(NoteFile.serialise(title: "  ", body: "just text"), "just text")
    }

    func testRoundTripsATitleThatLooksLikeAKeyValuePair() {
        let text = NoteFile.serialise(title: "todo: today", body: "body")

        XCTAssertEqual(NoteFile.parse(text).title, "todo: today")
        XCTAssertEqual(NoteFile.parse(text).body, "body")
    }

    func testRoundTripsAQuotedTitle() {
        let text = NoteFile.serialise(title: "\"quoted\"", body: "body")

        XCTAssertEqual(NoteFile.parse(text).title, "\"quoted\"")
    }

    func testABodyThatStartsWithADividerSurvivesARoundTrip() {
        let text = NoteFile.serialise(title: "Rules", body: "---\nfirst rule")

        XCTAssertEqual(NoteFile.parse(text).title, "Rules")
        XCTAssertEqual(NoteFile.parse(text).body, "---\nfirst rule")
    }
}
