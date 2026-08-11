import Foundation

/// A shortcut shown on Home. Opening it focuses or creates a live session,
/// but the shortcut itself never owns that session.
///
/// `symbol` and `tint` are retained only so payloads written by earlier builds
/// keep decoding cleanly; the current UI derives icons from favicons. Fields for
/// the removed per-site user-agent and reload-on-focus options are gone
/// entirely: unknown keys in a stored payload decode harmlessly.
struct Favourite: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var address: String
    var symbol: String? = nil
    var tint: CodableColor? = nil

    var url: URL {
        URL(string: address) ?? URL(string: "https://www.google.com")!
    }

    /// Longest page title still worth using as a rail label; anything longer
    /// is truncated to nothing useful in a 56pt-wide dock.
    static let maxDerivedNameLength = 24

    /// Picks the label for a site being saved from a page the user is looking
    /// at. Page titles are frequently long and marketing-heavy ("ChatGPT —
    /// the fastest way to…"), so the host wins whenever the title is empty or
    /// too long to read at rail size.
    static func preferredName(pageTitle: String, host: String) -> String {
        let title = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= maxDerivedNameLength else { return host }
        return title
    }

    /// Host used to look up the favicon and as the default favourite name,
    /// with a leading "www." stripped for a cleaner label.
    var host: String {
        let host = url.host ?? address
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static let starter: [Favourite] = [
        .init(name: "ChatGPT", address: "https://chatgpt.com"),
        .init(name: "Slack", address: "https://app.slack.com"),
        .init(name: "Calendar", address: "https://calendar.google.com"),
        .init(name: "YouTube", address: "https://youtube.com"),
        .init(name: "Gmail", address: "https://mail.google.com"),
        .init(name: "Notion", address: "https://www.notion.so")
    ]
}

/// Legacy accent-colour payload kept only for backward-compatible decoding
/// of favourites saved before the symbol/colour picker was removed.
struct CodableColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double = 1
}

@MainActor
final class FavouritesStore: ObservableObject {
    @Published private(set) var items: [Favourite]

    private let key = "ledge.favourites"
    /// Where an unreadable payload is copied before the starter set is
    /// seeded, so a decoding failure can never quietly destroy someone's
    /// list on the next write.
    private let salvageKey = "ledge.favourites.unreadable"
    private let defaults: UserDefaults

    /// `defaults` is injectable so tests never touch the real user's saved
    /// favourites.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: key) else {
            // Genuinely first run: seed the starter set.
            items = Favourite.starter
            return
        }
        if let decoded = try? JSONDecoder().decode([Favourite].self, from: data) {
            // A previously persisted *empty* list is respected: someone who
            // deletes every site should not find the starter set silently
            // back after the next launch.
            items = decoded
        } else {
            // Unreadable payload (corruption, or a shape written by a newer
            // build). Keep the bytes aside for recovery rather than letting
            // the next edit overwrite them, then fall back to the starters.
            if defaults.data(forKey: salvageKey) == nil {
                defaults.set(data, forKey: salvageKey)
            }
            items = Favourite.starter
        }
    }

    /// Adds a favourite from just a URL (required) and an optional name;
    /// the caller is expected to have already defaulted `name` to the
    /// domain when the user left it blank.
    @discardableResult
    func add(name: String, address: String) -> Favourite {
        let favourite = Favourite(name: name, address: address)
        items.append(favourite)
        persist()
        return favourite
    }

    func remove(_ item: Favourite) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    /// Renames a favourite in place (used by the favourites manager sheet).
    /// No-op if the trimmed name is empty or the favourite can't be found.
    func rename(_ item: Favourite, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].name = trimmed
        persist()
    }

    /// Reorders favourites (drag-to-reorder in the manager sheet / grid).
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Updates the stored address (used when a site permanently moves).
    @discardableResult
    func setAddress(_ address: String, for item: Favourite) -> Favourite? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return mutate(item) { $0.address = trimmed }
    }

    func favourite(withID id: Favourite.ID) -> Favourite? {
        items.first { $0.id == id }
    }

    /// A name that no existing site is already using, disambiguated Finder
    /// style. Two sites saved from the same host would otherwise be
    /// indistinguishable in the rail, where all there is to go on is an
    /// identical favicon and a tooltip.
    func uniqueName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Site" : trimmed
        let taken = Set(items.map(\.name))
        guard taken.contains(base) else { return base }

        var suffix = 2
        while taken.contains("\(base) \(suffix)") {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }

    @discardableResult
    private func mutate(_ item: Favourite, _ change: (inout Favourite) -> Void) -> Favourite? {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        change(&items[index])
        persist()
        return items[index]
    }

    /// Moves one favourite directly before another. This is used by the
    /// compact rail, whose icons support drag-to-reorder without showing a
    /// full List edit control.
    func move(id: Favourite.ID, before targetID: Favourite.ID) {
        guard id != targetID,
              let sourceIndex = items.firstIndex(where: { $0.id == id }) else { return }

        let movedItem = items.remove(at: sourceIndex)
        guard let targetIndex = items.firstIndex(where: { $0.id == targetID }) else {
            items.append(movedItem)
            persist()
            return
        }

        items.insert(movedItem, at: targetIndex)
        persist()
    }

    /// Moves one favourite to the end of the list. `move(id:before:)` cannot
    /// express this, so a grid that only drops "before" a tile has no way to
    /// reorder something past the final item without it.
    func moveToEnd(id: Favourite.ID) {
        guard let sourceIndex = items.firstIndex(where: { $0.id == id }),
              sourceIndex != items.count - 1 else { return }
        let movedItem = items.remove(at: sourceIndex)
        items.append(movedItem)
        persist()
    }

    /// Rewrites the Home shortcut order to match `ids`. Unknown ids are
    /// ignored, and omitted favourites keep their relative order at the end, so
    /// a stale list can never drop a shortcut.
    func setOrder(_ ids: [Favourite.ID]) {
        var remaining = items
        var reordered: [Favourite] = []
        reordered.reserveCapacity(items.count)

        for id in ids {
            guard let index = remaining.firstIndex(where: { $0.id == id }) else { continue }
            reordered.append(remaining.remove(at: index))
        }
        reordered += remaining

        guard reordered.map(\.id) != items.map(\.id) else { return }
        items = reordered
        persist()
    }

    /// Moves one favourite directly after another, which is what dropping on
    /// the lower half of a row means. Dropping after the final row appends,
    /// so this covers the end of the list too.
    func move(id: Favourite.ID, after targetID: Favourite.ID) {
        guard id != targetID,
              let sourceIndex = items.firstIndex(where: { $0.id == id }) else { return }

        let movedItem = items.remove(at: sourceIndex)
        guard let targetIndex = items.firstIndex(where: { $0.id == targetID }) else {
            items.append(movedItem)
            persist()
            return
        }

        items.insert(movedItem, at: targetIndex + 1)
        persist()
    }

    /// Nudges one favourite one place towards the top of the list. Offered
    /// alongside dragging because a 36pt target in a narrow rail is fiddly to
    /// hit precisely, and it keeps reordering reachable from the keyboard.
    func moveUp(id: Favourite.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }), index > 0 else { return }
        items.swapAt(index, index - 1)
        persist()
    }

    func moveDown(id: Favourite.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }), index < items.count - 1 else { return }
        items.swapAt(index, index + 1)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key)
    }
}
