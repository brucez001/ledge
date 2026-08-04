import XCTest
@testable import Ledge

@MainActor
final class FavouritesStoreTests: XCTestCase {

    /// Favourites written by earlier builds carried an SF Symbol + accent
    /// colour and no user-agent/reload fields. They must keep decoding, and
    /// the new fields must fall back to sensible defaults.
    func testLegacyPayloadStillDecodesWithDefaults() throws {
        let json = """
        [{
          "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
          "name": "Legacy",
          "address": "https://example.com",
          "symbol": "star.fill",
          "tint": { "red": 0.1, "green": 0.2, "blue": 0.3, "opacity": 1 }
        }]
        """
        let decoded = try JSONDecoder().decode([Favourite].self, from: Data(json.utf8))
        let favourite = try XCTUnwrap(decoded.first)

        XCTAssertEqual(favourite.name, "Legacy")
        XCTAssertEqual(favourite.symbol, "star.fill")
        XCTAssertEqual(favourite.resolvedUserAgentMode, .desktop)
        XCTAssertFalse(favourite.resolvedReloadsOnFocus)
    }

    func testRoundTripPreservesNewFields() throws {
        var favourite = Favourite(name: "Docs", address: "https://example.com")
        favourite.userAgentMode = .mobile
        favourite.reloadsOnFocus = true

        let data = try JSONEncoder().encode([favourite])
        let decoded = try JSONDecoder().decode([Favourite].self, from: data)

        XCTAssertEqual(decoded.first?.resolvedUserAgentMode, .mobile)
        XCTAssertEqual(decoded.first?.resolvedReloadsOnFocus, true)
    }

    func testHostStripsWWWPrefix() {
        XCTAssertEqual(Favourite(name: "N", address: "https://www.notion.so/x").host, "notion.so")
        XCTAssertEqual(Favourite(name: "N", address: "https://notion.so").host, "notion.so")
    }

    func testAddRenameAndRemove() {
        let store = makeStore()
        let added = store.add(name: "Example", address: "https://example.com")

        XCTAssertTrue(store.items.contains(added))
        XCTAssertEqual(store.favourite(withID: added.id)?.name, "Example")

        store.rename(added, to: "  Renamed  ")
        XCTAssertEqual(store.favourite(withID: added.id)?.name, "Renamed")

        // A blank rename must be ignored rather than producing a nameless tile.
        store.rename(added, to: "   ")
        XCTAssertEqual(store.favourite(withID: added.id)?.name, "Renamed")

        store.remove(added)
        XCTAssertNil(store.favourite(withID: added.id))
    }

    func testPerSiteFlagsPersistOnTheStoredItem() throws {
        let store = makeStore()
        let added = store.add(name: "Chat", address: "https://example.com")

        let mobile = try XCTUnwrap(store.setUserAgentMode(.mobile, for: added))
        XCTAssertEqual(mobile.resolvedUserAgentMode, .mobile)
        XCTAssertEqual(store.favourite(withID: added.id)?.resolvedUserAgentMode, .mobile)

        let reloading = try XCTUnwrap(store.setReloadsOnFocus(true, for: added))
        XCTAssertTrue(reloading.resolvedReloadsOnFocus)
        // The earlier change must not have been clobbered.
        XCTAssertEqual(reloading.resolvedUserAgentMode, .mobile)
    }

    func testSetAddressRejectsBlankInput() {
        let store = makeStore()
        let added = store.add(name: "Site", address: "https://example.com")

        XCTAssertNil(store.setAddress("   ", for: added))
        XCTAssertEqual(store.favourite(withID: added.id)?.address, "https://example.com")

        XCTAssertNotNil(store.setAddress("https://example.org", for: added))
        XCTAssertEqual(store.favourite(withID: added.id)?.address, "https://example.org")
    }

    func testMoveBeforeReordersInPlace() {
        let store = makeStore()
        let first = store.add(name: "A", address: "https://a.example")
        let second = store.add(name: "B", address: "https://b.example")
        let third = store.add(name: "C", address: "https://c.example")

        store.move(id: third.id, before: first.id)
        XCTAssertEqual(store.items.map(\.name), ["C", "A", "B"])

        // Moving an item before itself must be a no-op, not a duplication.
        store.move(id: second.id, before: second.id)
        XCTAssertEqual(store.items.map(\.name), ["C", "A", "B"])
    }

    /// `move(id:before:)` alone cannot express "put this last", which is why
    /// the grid needs an explicit end target.
    func testMoveToEnd() {
        let store = makeStore()
        let first = store.add(name: "A", address: "https://a.example")
        store.add(name: "B", address: "https://b.example")
        let third = store.add(name: "C", address: "https://c.example")

        store.moveToEnd(id: first.id)
        XCTAssertEqual(store.items.map(\.name), ["B", "C", "A"])

        // Already last: no reordering, no duplication.
        store.moveToEnd(id: store.items[2].id)
        XCTAssertEqual(store.items.map(\.name), ["B", "C", "A"])

        store.moveToEnd(id: third.id)
        XCTAssertEqual(store.items.map(\.name), ["B", "A", "C"])

        // An unknown id must not mutate anything.
        store.moveToEnd(id: UUID())
        XCTAssertEqual(store.items.map(\.name), ["B", "A", "C"])
    }

    // MARK: - Drag-to-reorder placement

    func testMoveAfterInsertsDirectlyBelowTheTarget() {
        let store = makeStore()
        let a = store.add(name: "A", address: "https://a.example")
        store.add(name: "B", address: "https://b.example")
        let c = store.add(name: "C", address: "https://c.example")

        store.move(id: a.id, after: c.id)
        XCTAssertEqual(store.items.map(\.name), ["B", "C", "A"])

        store.move(id: c.id, after: a.id)
        XCTAssertEqual(store.items.map(\.name), ["B", "A", "C"])
    }

    /// Dropping below the final row is how a site reaches the very end, so
    /// "after the last item" has to append rather than no-op.
    func testMoveAfterTheLastItemAppends() {
        let store = makeStore()
        let a = store.add(name: "A", address: "https://a.example")
        store.add(name: "B", address: "https://b.example")
        let c = store.add(name: "C", address: "https://c.example")

        store.move(id: a.id, after: c.id)
        XCTAssertEqual(store.items.last?.name, "A")
    }

    func testMoveAfterItselfIsANoOp() {
        let store = makeStore()
        store.add(name: "A", address: "https://a.example")
        let b = store.add(name: "B", address: "https://b.example")

        store.move(id: b.id, after: b.id)
        XCTAssertEqual(store.items.map(\.name), ["A", "B"])
    }

    // MARK: - Applying an order from the rail

    func testSetOrderRewritesTheOrder() {
        let store = makeStore()
        let a = store.add(name: "A", address: "https://a.example")
        let b = store.add(name: "B", address: "https://b.example")
        let c = store.add(name: "C", address: "https://c.example")

        store.setOrder([c.id, a.id, b.id])
        XCTAssertEqual(store.items.map(\.name), ["C", "A", "B"])
    }

    /// The rail derives its order from a snapshot, so it can hand back a list
    /// that has fallen behind. A favourite the list omits must keep its place
    /// rather than disappearing.
    func testSetOrderKeepsFavouritesTheListOmits() {
        let store = makeStore()
        let a = store.add(name: "A", address: "https://a.example")
        let b = store.add(name: "B", address: "https://b.example")
        store.add(name: "C", address: "https://c.example")

        store.setOrder([b.id, a.id])
        XCTAssertEqual(store.items.map(\.name), ["B", "A", "C"])
    }

    func testSetOrderIgnoresUnknownIdentifiers() {
        let store = makeStore()
        let a = store.add(name: "A", address: "https://a.example")
        let b = store.add(name: "B", address: "https://b.example")

        store.setOrder([UUID(), b.id, UUID(), a.id])
        XCTAssertEqual(store.items.map(\.name), ["B", "A"])
    }

    func testSetOrderSurvivesAReopen() throws {
        let suite = "ledge.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FavouritesStore(defaults: defaults)
        // A brand-new store seeds the starter set; clear it so the assertion is
        // about the order that was applied, not the seeds.
        for item in store.items {
            store.remove(item)
        }
        let a = store.add(name: "A", address: "https://a.example")
        let b = store.add(name: "B", address: "https://b.example")
        store.setOrder([b.id, a.id])

        let reopened = FavouritesStore(defaults: defaults)
        XCTAssertEqual(reopened.items.map(\.name), ["B", "A"])
    }

    func testMoveUpAndDownStopAtTheEnds() {
        let store = makeStore()
        let a = store.add(name: "A", address: "https://a.example")
        let b = store.add(name: "B", address: "https://b.example")
        let c = store.add(name: "C", address: "https://c.example")

        store.moveUp(id: b.id)
        XCTAssertEqual(store.items.map(\.name), ["B", "A", "C"])

        // Already first: nothing moves, and nothing is lost.
        store.moveUp(id: b.id)
        XCTAssertEqual(store.items.map(\.name), ["B", "A", "C"])

        store.moveDown(id: c.id)
        XCTAssertEqual(store.items.map(\.name), ["B", "A", "C"])

        store.moveDown(id: a.id)
        XCTAssertEqual(store.items.map(\.name), ["B", "C", "A"])
    }

    // MARK: - Drag payload

    func testDragPayloadRoundTrips() {
        let id = UUID()
        XCTAssertEqual(SiteDragPayload.decode(SiteDragPayload.encode(id)), id)
    }

    func testTabPayloadRoundTrips() {
        let id = UUID()
        XCTAssertEqual(SiteDragPayload.decodeItem(SiteDragPayload.encodeTab(id)), .tab(id))
        XCTAssertEqual(SiteDragPayload.decodeItem(SiteDragPayload.encode(id)), .site(id))
    }

    /// The site-only decoder must not accept a tab, or dragging a tab would be
    /// treated as reordering a favourite that does not exist.
    func testSiteDecoderRejectsATabPayload() {
        XCTAssertNil(SiteDragPayload.decode(SiteDragPayload.encodeTab(UUID())))
    }

    func testItemDecoderRejectsForeignText() {
        XCTAssertNil(SiteDragPayload.decodeItem("hello"))
        XCTAssertNil(SiteDragPayload.decodeItem(UUID().uuidString))
        XCTAssertNil(SiteDragPayload.decodeItem("ledge.tab:not-a-uuid"))
    }

    /// Text dropped from another app must not be mistaken for a reorder.
    func testDragPayloadRejectsForeignText() {
        XCTAssertNil(SiteDragPayload.decode("hello"))
        XCTAssertNil(SiteDragPayload.decode(UUID().uuidString))
        XCTAssertNil(SiteDragPayload.decode(""))
        XCTAssertNil(SiteDragPayload.decode("ledge.site:not-a-uuid"))
    }

    func testDragPayloadToleratesSurroundingWhitespace() {
        let id = UUID()
        XCTAssertEqual(SiteDragPayload.decode("  \(SiteDragPayload.encode(id))\n"), id)
    }

    /// An unreadable payload must be salvaged, not silently overwritten by
    /// the next edit -- otherwise one bad write loses every saved site.
    func testUnreadablePayloadIsSalvagedRatherThanOverwritten() throws {
        let suite = makeSuite()
        let corrupt = Data("this is not JSON".utf8)
        suite.set(corrupt, forKey: "ledge.favourites")

        let store = FavouritesStore(defaults: suite)
        XCTAssertEqual(store.items.count, Favourite.starter.count)
        XCTAssertEqual(suite.data(forKey: "ledge.favourites.unreadable"), corrupt)

        // A later edit overwrites the live key but must leave the salvage
        // copy intact, and must not salvage a second time over the original.
        store.add(name: "New", address: "https://example.com")
        XCTAssertEqual(suite.data(forKey: "ledge.favourites.unreadable"), corrupt)

        _ = FavouritesStore(defaults: suite)
        XCTAssertEqual(suite.data(forKey: "ledge.favourites.unreadable"), corrupt)
    }

    func testUserAgentModeToggles() {
        XCTAssertEqual(UserAgentMode.desktop.toggled, .mobile)
        XCTAssertEqual(UserAgentMode.mobile.toggled, .desktop)
        XCTAssertNil(UserAgentMode.desktop.customUserAgent)
        XCTAssertNotNil(UserAgentMode.mobile.customUserAgent)
    }

    // MARK: - Naming a site saved from the page you are looking at

    func testShortPageTitleBecomesTheName() {
        XCTAssertEqual(Favourite.preferredName(pageTitle: "Linear", host: "linear.app"), "Linear")
    }

    func testEmptyOrBlankTitleFallsBackToHost() {
        XCTAssertEqual(Favourite.preferredName(pageTitle: "", host: "example.com"), "example.com")
        XCTAssertEqual(Favourite.preferredName(pageTitle: "   \n ", host: "example.com"), "example.com")
    }

    /// A long marketing title is unreadable at rail size, so the host wins.
    func testLongTitleFallsBackToHost() {
        let long = "ChatGPT — the fastest way to get things done today"
        XCTAssertGreaterThan(long.count, Favourite.maxDerivedNameLength)
        XCTAssertEqual(Favourite.preferredName(pageTitle: long, host: "chatgpt.com"), "chatgpt.com")
    }

    func testTitleAtTheLengthLimitIsKept() {
        let atLimit = String(repeating: "a", count: Favourite.maxDerivedNameLength)
        XCTAssertEqual(Favourite.preferredName(pageTitle: atLimit, host: "example.com"), atLimit)

        let overLimit = String(repeating: "a", count: Favourite.maxDerivedNameLength + 1)
        XCTAssertEqual(Favourite.preferredName(pageTitle: overLimit, host: "example.com"), "example.com")
    }

    func testTitleIsTrimmedBeforeUse() {
        XCTAssertEqual(Favourite.preferredName(pageTitle: "  Notion  ", host: "notion.so"), "Notion")
    }

    func testStarterSetIsSeededOnlyWhenNothingWasEverPersisted() {
        let suite = makeSuite()

        let fresh = FavouritesStore(defaults: suite)
        XCTAssertEqual(fresh.items.count, Favourite.starter.count)

        for item in fresh.items {
            fresh.remove(item)
        }
        XCTAssertTrue(fresh.items.isEmpty)

        // Deliberately empty is remembered as empty, not re-seeded.
        let reopened = FavouritesStore(defaults: suite)
        XCTAssertTrue(reopened.items.isEmpty)
    }

    func testChangesSurviveAReopen() throws {
        let suite = makeSuite()
        let store = FavouritesStore(defaults: suite)
        let added = store.add(name: "Persisted", address: "https://example.com")
        store.setUserAgentMode(.mobile, for: added)

        let reopened = FavouritesStore(defaults: suite)
        let restored = try XCTUnwrap(reopened.favourite(withID: added.id))
        XCTAssertEqual(restored.name, "Persisted")
        XCTAssertEqual(restored.resolvedUserAgentMode, .mobile)
    }

    // MARK: - Helpers

    /// An isolated defaults suite per test, so the real app's saved
    /// favourites are never read or overwritten.
    private func makeSuite() -> UserDefaults {
        let name = "ledge.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        addTeardownBlock { suite.removePersistentDomain(forName: name) }
        return suite
    }

    private func makeStore() -> FavouritesStore {
        let store = FavouritesStore(defaults: makeSuite())
        for item in store.items {
            store.remove(item)
        }
        return store
    }
}

@MainActor
final class UniqueNameTests: XCTestCase {
    /// Two sites saved from the same host would otherwise share a label, and in
    /// the rail an identical favicon is all there is to go on.
    func testDuplicateNamesAreDisambiguated() {
        let store = makeStore()
        store.add(name: "Jarvis", address: "https://jarvis.example/")
        XCTAssertEqual(store.uniqueName("Jarvis"), "Jarvis 2")

        store.add(name: "Jarvis 2", address: "https://jarvis.example/other")
        XCTAssertEqual(store.uniqueName("Jarvis"), "Jarvis 3")
    }

    func testUnusedNameIsReturnedUnchanged() {
        let store = makeStore()
        store.add(name: "Jarvis", address: "https://jarvis.example/")
        XCTAssertEqual(store.uniqueName("Notion"), "Notion")
    }

    func testBlankNameFallsBackRatherThanProducingAnEmptyLabel() {
        let store = makeStore()
        XCTAssertEqual(store.uniqueName("   "), "Site")
        XCTAssertEqual(store.uniqueName("  Notion  "), "Notion")
    }

    private func makeStore() -> FavouritesStore {
        let name = "ledge.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        addTeardownBlock { suite.removePersistentDomain(forName: name) }
        let store = FavouritesStore(defaults: suite)
        for item in store.items { store.remove(item) }
        return store
    }
}
