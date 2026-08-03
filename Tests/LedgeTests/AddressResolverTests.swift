import XCTest
@testable import Ledge

final class AddressResolverTests: XCTestCase {

    // MARK: - Addresses

    func testFullHTTPSAddressStaysAnAddress() throws {
        let result = try XCTUnwrap(AddressResolver.resolve("https://example.com/a?b=c"))
        XCTAssertEqual(result.absoluteString, "https://example.com/a?b=c")
    }

    func testBareDomainGetsHTTPS() throws {
        let result = try XCTUnwrap(AddressResolver.resolve("notion.so"))
        XCTAssertEqual(result.absoluteString, "https://notion.so")
    }

    func testBareDomainWithPathAndQueryGetsHTTPS() throws {
        let result = try XCTUnwrap(AddressResolver.resolve("chatgpt.com/c/abc?x=1"))
        XCTAssertEqual(result.absoluteString, "https://chatgpt.com/c/abc?x=1")
    }

    func testLocalhostWithPortIsAnAddress() throws {
        let result = try XCTUnwrap(AddressResolver.resolve("localhost:3000/health"))
        XCTAssertEqual(result.absoluteString, "https://localhost:3000/health")
    }

    func testIPAddressIsAnAddress() throws {
        let result = try XCTUnwrap(AddressResolver.resolve("192.168.0.14:8080"))
        XCTAssertEqual(result.host, "192.168.0.14")
        XCTAssertEqual(result.port, 8080)
    }

    func testHTTPSchemeIsPreserved() throws {
        let result = try XCTUnwrap(AddressResolver.resolve("http://intranet.local/status"))
        XCTAssertEqual(result.scheme, "http")
    }

    func testSurroundingWhitespaceIsTrimmed() throws {
        let result = try XCTUnwrap(AddressResolver.resolve("   notion.so \n"))
        XCTAssertEqual(result.absoluteString, "https://notion.so")
    }

    // MARK: - Searches

    func testKeywordsBecomeGoogleSearch() throws {
        let result = try XCTUnwrap(AddressResolver.resolve("weekly planning notes"))
        let components = try XCTUnwrap(URLComponents(url: result, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "www.google.com")
        XCTAssertEqual(components.path, "/search")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "q" })?.value, "weekly planning notes")
    }

    /// A decimal comparison must not be mistaken for a host: `4.5` has no
    /// alphabetic top-level domain, so it belongs in the search engine.
    func testDecimalNumbersAreSearchedNotNavigated() throws {
        let result = try XCTUnwrap(AddressResolver.resolve("4.5"))
        XCTAssertEqual(result.host, "www.google.com")
        XCTAssertEqual(
            URLComponents(url: result, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value,
            "4.5"
        )
    }

    func testPartialIPIsSearched() throws {
        let result = try XCTUnwrap(AddressResolver.resolve("192.168.0"))
        XCTAssertEqual(result.host, "www.google.com")
    }

    func testTrailingDotHostIsSearched() throws {
        let result = try XCTUnwrap(AddressResolver.resolve("example."))
        XCTAssertEqual(result.host, "www.google.com")
    }

    func testSingleWordWithoutDotIsSearched() throws {
        let result = try XCTUnwrap(AddressResolver.resolve("standup"))
        XCTAssertEqual(result.host, "www.google.com")
    }

    func testNonExistentAbsolutePathIsSearchedNotOpenedAsAFile() throws {
        let result = try XCTUnwrap(AddressResolver.resolve("/definitely/not/a/real/path-\(UUID().uuidString)"))
        XCTAssertEqual(result.host, "www.google.com")
    }

    func testExistingLocalFileResolvesToFileURL() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledge-test-\(UUID().uuidString).html")
        try "<html></html>".write(to: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: path) }

        let result = try XCTUnwrap(AddressResolver.resolve(path.path))
        XCTAssertTrue(result.isFileURL)
        XCTAssertEqual(result.standardizedFileURL, path.standardizedFileURL)
    }

    // MARK: - Engines

    func testSearchEngineIsHonoured() throws {
        let result = try XCTUnwrap(AddressResolver.resolve("mac launcher", using: .duckDuckGo))
        XCTAssertEqual(result.host, "duckduckgo.com")
        XCTAssertEqual(
            URLComponents(url: result, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value,
            "mac launcher"
        )
    }

    func testEverySearchEngineBuildsAQueryURL() throws {
        for engine in SearchEngine.allCases {
            let url = try XCTUnwrap(engine.searchURL(for: "slide over"), "\(engine) produced no URL")
            XCTAssertEqual(url.scheme, "https", "\(engine)")
            XCTAssertEqual(url.host, engine.host, "\(engine)")
            XCTAssertTrue(
                url.query?.contains("q=slide%20over") == true || url.query?.contains("q=slide+over") == true,
                "\(engine) query was \(url.query ?? "nil")"
            )
        }
    }

    // MARK: - Empty input

    func testEmptyInputResolvesToNothing() {
        XCTAssertNil(AddressResolver.resolve(""))
        XCTAssertNil(AddressResolver.resolve("   \n "))
    }
}
