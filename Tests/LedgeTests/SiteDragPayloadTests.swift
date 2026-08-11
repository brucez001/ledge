import XCTest
@testable import Ledge

final class SiteDragPayloadTests: XCTestCase {
    func testHomeAndRailPayloadsCannotCrossSurfaces() {
        let id = UUID()
        let home = SiteDragPayload.encode(id)
        let railFavourite = SiteDragPayload.encodeRailFavourite(id)
        let railTab = SiteDragPayload.encodeRailTab(id)

        XCTAssertEqual(SiteDragPayload.decode(home), id)
        XCTAssertNil(SiteDragPayload.decode(railFavourite))
        XCTAssertNil(SiteDragPayload.decode(railTab))

        XCTAssertNil(SiteDragPayload.decodeItem(home))
        XCTAssertEqual(SiteDragPayload.decodeItem(railFavourite), .site(id))
        XCTAssertEqual(SiteDragPayload.decodeItem(railTab), .tab(id))
    }

    func testUnrelatedTextIsRejected() {
        XCTAssertNil(SiteDragPayload.decode("not a Ledge payload"))
        XCTAssertNil(SiteDragPayload.decodeItem("not a Ledge payload"))
    }
}
