import XCTest
@testable import Ledge

final class ScreenEdgeTests: XCTestCase {

    /// A real three-display layout that broke edge reveal: a built-in laptop
    /// display at the origin with two externals above it, offset sideways.
    /// The right-hand external's left edge (x = 725) is an interior *seam*
    /// against the left-hand external's right edge, not a hoverable edge.
    private let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let rightExternal = CGRect(x: 725, y: 982, width: 1920, height: 1080)
    private let leftExternal = CGRect(x: -1195, y: 982, width: 1920, height: 1080)

    private var threeDisplays: [CGRect] { [builtIn, rightExternal, leftExternal] }

    func testSingleDisplayHasBothEdgesExposed() {
        let only = [builtIn]
        XCTAssertTrue(ScreenEdge.isExposed(.left, of: builtIn, among: only))
        XCTAssertTrue(ScreenEdge.isExposed(.right, of: builtIn, among: only))
    }

    func testInteriorSeamIsNotAnExposedEdge() {
        // The seam that caused the bug: another display sits flush against it.
        XCTAssertFalse(ScreenEdge.isExposed(.left, of: rightExternal, among: threeDisplays))
        XCTAssertFalse(ScreenEdge.isExposed(.right, of: leftExternal, among: threeDisplays))
    }

    func testOuterEdgesAreExposed() {
        XCTAssertTrue(ScreenEdge.isExposed(.left, of: leftExternal, among: threeDisplays))
        XCTAssertTrue(ScreenEdge.isExposed(.right, of: rightExternal, among: threeDisplays))
    }

    /// The built-in sits below both externals, so nothing overlaps it
    /// vertically and both of its edges remain hoverable.
    func testVerticallyDisjointNeighboursDoNotBlockAnEdge() {
        XCTAssertTrue(ScreenEdge.isExposed(.left, of: builtIn, among: threeDisplays))
        XCTAssertTrue(ScreenEdge.isExposed(.right, of: builtIn, among: threeDisplays))
    }

    func testExposedEdgeFiltering() {
        // `CGRect: Hashable` needs macOS 15, so compare as sorted arrays.
        let left = ScreenEdge.framesWithExposedEdge(.left, among: threeDisplays)
        XCTAssertEqual(left.sorted { $0.minX < $1.minX }, [leftExternal, builtIn])

        let right = ScreenEdge.framesWithExposedEdge(.right, among: threeDisplays)
        XCTAssertEqual(right.sorted { $0.minX < $1.minX }, [builtIn, rightExternal])
    }

    /// Side-by-side displays with identical bounds: the shared boundary is a
    /// seam for both, and only the outer two edges are hoverable.
    func testSideBySideDisplays() {
        let leftScreen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let rightScreen = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let pair = [leftScreen, rightScreen]

        XCTAssertTrue(ScreenEdge.isExposed(.left, of: leftScreen, among: pair))
        XCTAssertFalse(ScreenEdge.isExposed(.right, of: leftScreen, among: pair))
        XCTAssertFalse(ScreenEdge.isExposed(.left, of: rightScreen, among: pair))
        XCTAssertTrue(ScreenEdge.isExposed(.right, of: rightScreen, among: pair))
    }

    /// A gap between displays leaves both facing edges hoverable: the pointer
    /// really does stop at each one.
    func testDisplaysWithAGapKeepBothFacingEdges() {
        let a = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let b = CGRect(x: 1200, y: 0, width: 1000, height: 1000)
        let pair = [a, b]

        XCTAssertTrue(ScreenEdge.isExposed(.right, of: a, among: pair))
        XCTAssertTrue(ScreenEdge.isExposed(.left, of: b, among: pair))
    }

    func testDesktopBoundsSpansEveryDisplay() {
        let bounds = ScreenEdge.desktopBounds(among: threeDisplays)
        XCTAssertEqual(bounds, CGRect(x: -1195, y: 0, width: 3840, height: 2062))
    }

    /// The hidden panel must clear the whole desktop, not just its own
    /// display -- otherwise it parks in plain sight on a neighbouring monitor.
    func testDesktopBoundsIsLeftOfEveryDisplayOrigin() {
        let bounds = ScreenEdge.desktopBounds(among: threeDisplays)
        for frame in threeDisplays {
            XCTAssertLessThanOrEqual(bounds.minX, frame.minX)
            XCTAssertGreaterThanOrEqual(bounds.maxX, frame.maxX)
        }
    }

    // MARK: - Floating toolbar reveal band

    /// An 880x807 panel docked at the origin, as the app actually sizes it.
    private let panel = CGRect(x: 0, y: 100, width: 880, height: 807)

    func testPointerNearTopArmsOnlyCloseToTheTopEdge() {
        let justInside = CGPoint(x: 400, y: panel.maxY - 10)
        let justOutside = CGPoint(x: 400, y: panel.maxY - 40)

        XCTAssertTrue(ScreenEdge.isPointerNearTop(justInside, panelFrame: panel, wasNear: false))
        XCTAssertFalse(ScreenEdge.isPointerNearTop(justOutside, panelFrame: panel, wasNear: false))
    }

    /// Once revealed, the toolbar must stay revealed while the pointer rests
    /// on it -- the toolbar is taller than the arming band, so a single
    /// threshold would flicker.
    func testRevealedToolbarSurvivesThePointerRestingOnIt() {
        let onToolbar = CGPoint(x: 400, y: panel.maxY - 50)
        XCTAssertFalse(ScreenEdge.isPointerNearTop(onToolbar, panelFrame: panel, wasNear: false))
        XCTAssertTrue(ScreenEdge.isPointerNearTop(onToolbar, panelFrame: panel, wasNear: true))
    }

    func testMovingWellDownThePageDismissesTheToolbar() {
        let deepInPage = CGPoint(x: 400, y: panel.maxY - 200)
        XCTAssertFalse(ScreenEdge.isPointerNearTop(deepInPage, panelFrame: panel, wasNear: true))
    }

    func testPointerOutsideThePanelIsNeverNearTheTop() {
        let beside = CGPoint(x: panel.maxX + 30, y: panel.maxY - 5)
        let below = CGPoint(x: 400, y: panel.minY - 5)

        XCTAssertFalse(ScreenEdge.isPointerNearTop(beside, panelFrame: panel, wasNear: true))
        XCTAssertFalse(ScreenEdge.isPointerNearTop(below, panelFrame: panel, wasNear: true))
    }

    func testKeepRevealedBandIsWiderThanTheToolbar() {
        // Otherwise the hysteresis cannot cover the control it is protecting.
        XCTAssertGreaterThan(ScreenEdge.toolbarKeepRevealedBand, Theme.Metrics.toolbarHeight + 12)
        XCTAssertLessThan(ScreenEdge.toolbarRevealBand, ScreenEdge.toolbarKeepRevealedBand)
    }
}
