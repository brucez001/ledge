import XCTest
@testable import Ledge

final class CloseCommandTests: XCTestCase {
    private let site = UUID()
    private let tab = UUID()

    func testCommandWClosesAnOrdinarySession() {
        XCTAssertEqual(
            CloseCommand.resolve(destination: .tab(tab)),
            .closeSession(.tab(tab))
        )
    }

    func testCommandWClosesAFavouriteAssociatedSessionWithoutRemovingTheShortcut() {
        XCTAssertEqual(
            CloseCommand.resolve(destination: .favourite(site)),
            .closeSession(.favourite(site))
        )
    }

    func testHomeHasNoSessionToClose() {
        XCTAssertEqual(CloseCommand.resolve(destination: .home), .nothing)
    }
}
