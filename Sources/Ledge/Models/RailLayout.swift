import Foundation

/// One row of the rail. The rail is a single ordered list of these, so a
/// position in it is expressible for a transient tab as well as a saved site --
/// which is the whole point. Previously order came from two unrelated places
/// (the persisted favourites array and the order sessions happened to be
/// created in), so "third from the top" simply was not a position a tab could
/// hold, and the only way to place an icon among the saved sites was to make it
/// a favourite. Position and persistence are now independent.
enum RailEntry: Hashable, Identifiable {
    case favourite(UUID)
    case tab(UUID)

    var id: Self { self }

    var favouriteID: UUID? {
        guard case .favourite(let id) = self else { return nil }
        return id
    }

    var tabID: UUID? {
        guard case .tab(let id) = self else { return nil }
        return id
    }
}

/// Where a transient tab sits, expressed relative to the saved sites rather
/// than as an absolute index.
///
/// Favourites own a persisted order of their own, so an index would be
/// invalidated every time one was added, removed, or reordered. An anchor
/// survives all three: the tab stays with the site it was placed after.
enum RailAnchor: Hashable {
    /// Above every saved site.
    case start
    /// Immediately after this saved site.
    case after(UUID)
}

/// Pure ordering arithmetic for the rail.
///
/// The displayed list is the working representation; the two stores are
/// projections of it. Every move -- by drag or by menu -- is expressed as a
/// reinsertion in this list, and the favourite order, tab order, and tab
/// anchors are then derived back out of the result. That keeps one rule for
/// reordering rather than one per kind of row, and keeps all of it testable
/// without AppKit or WebKit.
enum RailLayout {
    /// The rail's rows, built from the persisted favourite order, the live tab
    /// order, and the tabs' anchors.
    static func entries(
        favourites: [UUID],
        tabs: [UUID],
        anchors: [UUID: RailAnchor]
    ) -> [RailEntry] {
        let knownFavourites = Set(favourites)

        /// A tab with no anchor is new, and a tab anchored to a site that has
        /// since been removed has lost its place. Both go to the end, which is
        /// where tabs have always appeared.
        func resolvedAnchor(for tab: UUID) -> RailAnchor {
            switch anchors[tab] {
            case .start:
                return .start
            case .after(let favourite) where knownFavourites.contains(favourite):
                return .after(favourite)
            default:
                return favourites.last.map(RailAnchor.after) ?? .start
            }
        }

        func rows(anchoredTo anchor: RailAnchor) -> [RailEntry] {
            tabs.filter { resolvedAnchor(for: $0) == anchor }.map(RailEntry.tab)
        }

        var rail = rows(anchoredTo: .start)
        for favourite in favourites {
            rail.append(.favourite(favourite))
            rail += rows(anchoredTo: .after(favourite))
        }
        return rail
    }

    /// The rail after dropping `entry` immediately above (`isBelow == false`) or
    /// below `target`.
    ///
    /// When the requested side is where the row already sits, the other side of
    /// `target` is used instead: the rail draws no insertion indicator, so a
    /// drop resolving to "stay exactly where you are" is indistinguishable from
    /// a drag that failed. Dropping on a row other than your own always moves
    /// you across it.
    static func moved(
        _ entry: RailEntry,
        relativeTo target: RailEntry,
        isBelow: Bool,
        in entries: [RailEntry]
    ) -> [RailEntry]? {
        guard entry != target,
              entries.contains(entry),
              entries.contains(target) else { return nil }

        for side in [isBelow, !isBelow] {
            var reordered = entries
            reordered.removeAll { $0 == entry }
            guard let index = reordered.firstIndex(of: target) else { return nil }
            reordered.insert(entry, at: side ? index + 1 : index)
            if reordered != entries { return reordered }
        }
        return nil
    }

    /// The rail after moving `entry` by `offset` rows, for the menu's Move Up
    /// and Move Down. `nil` when the row is already at the end it is moving
    /// towards, so the caller can disable the item.
    static func moved(
        _ entry: RailEntry,
        by offset: Int,
        in entries: [RailEntry]
    ) -> [RailEntry]? {
        guard offset != 0, let index = entries.firstIndex(of: entry) else { return nil }
        let destination = index + offset
        guard entries.indices.contains(destination) else { return nil }

        var reordered = entries
        reordered.remove(at: index)
        reordered.insert(entry, at: destination)
        return reordered
    }

    /// The favourite order implied by a rail list.
    static func favourites(in entries: [RailEntry]) -> [UUID] {
        entries.compactMap(\.favouriteID)
    }

    /// The tab order implied by a rail list.
    static func tabs(in entries: [RailEntry]) -> [UUID] {
        entries.compactMap(\.tabID)
    }

    /// The anchors implied by a rail list: each tab is anchored to the nearest
    /// saved site above it, or to the start of the rail if there is none.
    static func anchors(in entries: [RailEntry]) -> [UUID: RailAnchor] {
        var anchors: [UUID: RailAnchor] = [:]
        var current = RailAnchor.start
        for entry in entries {
            switch entry {
            case .favourite(let id):
                current = .after(id)
            case .tab(let id):
                anchors[id] = current
            }
        }
        return anchors
    }

    /// The rail with one row swapped for another, keeping its exact position.
    ///
    /// This is how a tab is kept as a favourite in place: the row it occupied
    /// becomes the new favourite, so its position among neighbouring tabs is
    /// preserved rather than only its anchor.
    static func replacing(
        _ entry: RailEntry,
        with replacement: RailEntry,
        in entries: [RailEntry]
    ) -> [RailEntry] {
        entries.map { $0 == entry ? replacement : $0 }
    }

    /// The rail with one row removed.
    ///
    /// Deriving anchors from the result re-homes any tab that was anchored to a
    /// removed saved site onto the row above it, rather than letting it fall to
    /// the end of the rail.
    static func removing(_ entry: RailEntry, from entries: [RailEntry]) -> [RailEntry] {
        entries.filter { $0 != entry }
    }
}
