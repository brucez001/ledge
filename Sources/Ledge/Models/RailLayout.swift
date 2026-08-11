import Foundation

/// One open session in the rail.
///
/// The two cases preserve whether a live session is associated with a Home
/// favourite, but that association does not change its rail behaviour. The
/// rail is simply the in-memory order of `SessionManager.sessions`.
enum RailEntry: Hashable, Identifiable {
    case favourite(UUID)
    case tab(UUID)

    init(_ kind: SessionKind) {
        switch kind {
        case .favourite(let id): self = .favourite(id)
        case .tab(let id): self = .tab(id)
        }
    }

    var id: Self { self }

    var sessionKind: SessionKind {
        switch self {
        case .favourite(let id): .favourite(id)
        case .tab(let id): .tab(id)
        }
    }

    var favouriteID: UUID? {
        guard case .favourite(let id) = self else { return nil }
        return id
    }

    var tabID: UUID? {
        guard case .tab(let id) = self else { return nil }
        return id
    }
}

/// The rail edge that should show an insertion line during a drag: the line is
/// drawn on `isBelow ? bottom : top` of the row identified by `entry`.
struct RailDropLine: Equatable {
    let entry: RailEntry
    let isBelow: Bool
}

/// Pure ordering arithmetic for the live-session rail.
///
/// Favourite order belongs to Home and never participates here. Reordering a
/// rail row only rewrites the in-memory order of currently open sessions.
enum RailLayout {
    static func entries(sessions: [SessionKind]) -> [RailEntry] {
        sessions.map(RailEntry.init)
    }

    /// The rail after dropping `entry` immediately above (`isBelow == false`)
    /// or below `target`.
    static func moved(
        _ entry: RailEntry,
        relativeTo target: RailEntry,
        isBelow: Bool,
        in entries: [RailEntry]
    ) -> [RailEntry]? {
        guard entry != target,
              let sourceIndex = entries.firstIndex(of: entry),
              entries.contains(target) else { return nil }

        var result = entries
        result.remove(at: sourceIndex)

        guard let adjustedTarget = result.firstIndex(of: target) else { return nil }
        var insertionIndex = adjustedTarget + (isBelow ? 1 : 0)

        // Dropping on the side that resolves to the row's existing position is
        // indistinguishable from a failed drop. Prefer the other side instead.
        if insertionIndex == sourceIndex {
            insertionIndex = adjustedTarget + (isBelow ? 0 : 1)
        }

        result.insert(entry, at: min(max(insertionIndex, 0), result.count))
        return result == entries ? nil : result
    }

    /// The rail after moving one row by `offset` whole positions.
    static func moved(
        _ entry: RailEntry,
        by offset: Int,
        in entries: [RailEntry]
    ) -> [RailEntry]? {
        guard offset != 0, let sourceIndex = entries.firstIndex(of: entry) else { return nil }
        let destination = sourceIndex + offset
        guard entries.indices.contains(destination) else { return nil }

        var result = entries
        result.remove(at: sourceIndex)
        result.insert(entry, at: destination)
        return result
    }

    static func sessionKinds(in entries: [RailEntry]) -> [SessionKind] {
        entries.map(\.sessionKind)
    }

    /// The row a ⌘1…⌘9 shortcut names. `number` is 1-based, as printed on the
    /// key, and counts rail rows from the top -- so it follows the user's own
    /// reordering rather than Home's favourite order.
    ///
    /// Returns `nil` when the rail has no such row: pressing ⌘4 with three
    /// sessions open does nothing rather than clamping to the last row, which
    /// would make the shortcut land somewhere the user did not name.
    static func entry(numbered number: Int, in entries: [RailEntry]) -> RailEntry? {
        let index = number - 1
        guard entries.indices.contains(index) else { return nil }
        return entries[index]
    }

    /// Which row edge should show the insertion line while `dragged` hovers
    /// over `target`, or `nil` when releasing would change nothing.
    ///
    /// This deliberately reports where the row *will land* rather than which
    /// half of the target the pointer is in, because `moved(_:relativeTo:
    /// isBelow:)` flips to the opposite side when the pointer's own side would
    /// be a no-op. Deriving the line from the resulting order means the
    /// indicator can never promise a position the drop will not honour.
    static func insertionLine(
        dragging dragged: RailEntry,
        over target: RailEntry,
        isBelow: Bool,
        in entries: [RailEntry]
    ) -> RailDropLine? {
        guard let reordered = moved(dragged, relativeTo: target, isBelow: isBelow, in: entries),
              let landing = reordered.firstIndex(of: dragged) else { return nil }

        // Rows do not move during the drag, so anchor the line to whichever
        // neighbour the dragged row will sit against: below the row that will
        // precede it, or above the row that will follow it at the very top.
        if landing > 0 {
            return RailDropLine(entry: reordered[landing - 1], isBelow: true)
        }
        guard reordered.count > 1 else { return nil }
        return RailDropLine(entry: reordered[1], isBelow: false)
    }
}
