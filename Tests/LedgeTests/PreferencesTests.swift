import XCTest
@testable import Ledge

@MainActor
final class PreferencesTests: XCTestCase {

    func testDefaultsFavourEdgeRevealWithoutStealingFocus() {
        let preferences = Preferences(defaults: makeSuite())

        XCTAssertTrue(preferences.edgeTriggerEnabled)
        XCTAssertTrue(preferences.followsMouseDisplay)
        XCTAssertFalse(preferences.edgeRevealTakesFocus)
        XCTAssertEqual(preferences.animationSpeed, .standard)
        XCTAssertEqual(preferences.appearance, .system)
        XCTAssertEqual(preferences.searchEngine, .google)
        XCTAssertEqual(preferences.faviconSource, .siteThenService)
        XCTAssertEqual(preferences.edgeTriggerDelay, 0.12, accuracy: 0.0001)
    }

    /// Notes render their Markdown as it is typed unless the user turns that
    /// off, so a bullet looks like a bullet without having to be told to.
    func testNotesRenderMarkdownByDefault() {
        XCTAssertTrue(Preferences(defaults: makeSuite()).notesRenderMarkdown)
    }

    func testNotesRenderMarkdownRoundTripsAndSurvivesRubbish() {
        let suite = makeSuite()
        Preferences(defaults: suite).notesRenderMarkdown = false
        XCTAssertFalse(Preferences(defaults: suite).notesRenderMarkdown)

        suite.set("nonsense", forKey: "ledge.notes.renderMarkdown")
        XCTAssertTrue(Preferences(defaults: suite).notesRenderMarkdown)
    }

    func testChangesRoundTripThroughDefaults() {
        let suite = makeSuite()

        let first = Preferences(defaults: suite)
        first.edgeTriggerEnabled = false
        first.edgeTriggerDelay = 0.4
        first.followsMouseDisplay = false
        first.edgeRevealTakesFocus = true
        first.animationSpeed = .snappy
        first.appearance = .dark
        first.searchEngine = .kagi
        first.faviconSource = .monogramOnly

        let reopened = Preferences(defaults: suite)
        XCTAssertFalse(reopened.edgeTriggerEnabled)
        XCTAssertEqual(reopened.edgeTriggerDelay, 0.4, accuracy: 0.0001)
        XCTAssertFalse(reopened.followsMouseDisplay)
        XCTAssertTrue(reopened.edgeRevealTakesFocus)
        XCTAssertEqual(reopened.animationSpeed, .snappy)
        XCTAssertEqual(reopened.appearance, .dark)
        XCTAssertEqual(reopened.searchEngine, .kagi)
        XCTAssertEqual(reopened.faviconSource, .monogramOnly)
    }

    /// An out-of-range delay must never make the edge trigger fire instantly
    /// or take multiple seconds.
    func testDelayIsClamped() {
        XCTAssertEqual(Preferences.clampDelay(-3), 0, accuracy: 0.0001)
        XCTAssertEqual(Preferences.clampDelay(9), 1.0, accuracy: 0.0001)
        XCTAssertEqual(Preferences.clampDelay(0.25), 0.25, accuracy: 0.0001)

        let suite = makeSuite()
        suite.set(42.0, forKey: "ledge.edgeTriggerDelay")
        XCTAssertEqual(Preferences(defaults: suite).edgeTriggerDelay, 1.0, accuracy: 0.0001)
    }

    func testUnknownStoredValuesFallBackToDefaults() {
        let suite = makeSuite()
        suite.set("nonsense", forKey: "ledge.animationSpeed")
        suite.set("nonsense", forKey: "ledge.appearance")
        suite.set("nonsense", forKey: "ledge.searchEngine")
        suite.set("nonsense", forKey: "ledge.faviconSource")

        let preferences = Preferences(defaults: suite)
        XCTAssertEqual(preferences.animationSpeed, .standard)
        XCTAssertEqual(preferences.appearance, .system)
        XCTAssertEqual(preferences.searchEngine, .google)
        XCTAssertEqual(preferences.faviconSource, .siteThenService)
    }

    func testFaviconSourceCapabilities() {
        XCTAssertTrue(FaviconSource.siteThenService.allowsSiteFetch)
        XCTAssertTrue(FaviconSource.siteThenService.allowsServiceFallback)
        XCTAssertTrue(FaviconSource.siteOnly.allowsSiteFetch)
        XCTAssertFalse(FaviconSource.siteOnly.allowsServiceFallback)
        XCTAssertFalse(FaviconSource.monogramOnly.allowsSiteFetch)
        XCTAssertFalse(FaviconSource.monogramOnly.allowsServiceFallback)
    }

    func testAnimationSpeedsAreOrdered() {
        XCTAssertLessThan(AnimationSpeed.snappy.slideDuration, AnimationSpeed.standard.slideDuration)
        XCTAssertLessThan(AnimationSpeed.standard.slideDuration, AnimationSpeed.relaxed.slideDuration)
    }

    private func makeSuite() -> UserDefaults {
        let name = "ledge.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        addTeardownBlock { suite.removePersistentDomain(forName: name) }
        return suite
    }
}
