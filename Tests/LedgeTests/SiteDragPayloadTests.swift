import XCTest
@testable import Ledge

final class SiteDragPayloadTests: XCTestCase {
    func testHomeAndRailPayloadsCannotCrossSurfaces() {
        let id = UUID()
        let home = SiteDragPayload.encode(.homeFavourite, id)
        let railFavourite = SiteDragPayload.encode(.railFavourite, id)
        let railTab = SiteDragPayload.encode(.railTab, id)

        XCTAssertEqual(SiteDragPayload.decode(.homeFavourite, from: home), id)
        XCTAssertNil(SiteDragPayload.decode(.homeFavourite, from: railFavourite))
        XCTAssertNil(SiteDragPayload.decode(.homeFavourite, from: railTab))

        XCTAssertNil(SiteDragPayload.decodeEntry(home))
        XCTAssertEqual(SiteDragPayload.decodeEntry(railFavourite), .favourite(id))
        XCTAssertEqual(SiteDragPayload.decodeEntry(railTab), .tab(id))
    }

    /// The two home grids share plain text, so only the prefix keeps a note
    /// out of the favourites grid and a favourite out of the notes grid.
    func testTheTwoHomeGridsCannotDecodeEachOther() {
        let id = UUID()

        let favourite = SiteDragPayload.encode(.homeFavourite, id)
        let note = SiteDragPayload.encode(.homeNote, id)

        XCTAssertNil(SiteDragPayload.decode(.homeNote, from: favourite))
        XCTAssertNil(SiteDragPayload.decode(.homeFavourite, from: note))
        XCTAssertEqual(SiteDragPayload.decode(.homeNote, from: note), id)
    }

    /// Every kind must round-trip, so adding one cannot quietly skip a prefix.
    func testEveryKindRoundTrips() {
        let id = UUID()

        for kind in SiteDragPayload.Kind.allCases {
            XCTAssertEqual(
                SiteDragPayload.decode(kind, from: SiteDragPayload.encode(kind, id)),
                id,
                "\(kind) did not round-trip"
            )
        }
    }

    func testUnrelatedTextIsRejected() {
        XCTAssertNil(SiteDragPayload.decode(.homeFavourite, from: "not a Ledge payload"))
        XCTAssertNil(SiteDragPayload.decodeEntry("not a Ledge payload"))
    }

    /// Every rail row encodes to a payload the rail decodes back to it.
    func testEveryRailEntryRoundTrips() {
        let id = UUID()
        let entries: [RailEntry] = [.favourite(id), .tab(id), .note(id), .terminal(id)]

        for entry in entries {
            XCTAssertEqual(SiteDragPayload.decodeEntry(SiteDragPayload.encode(entry)), entry)
        }
    }
}
