import Foundation

/// One open rail row: a live session or an open note tab.
///
/// The session cases preserve whether a live session is associated with a
/// Home favourite, but that association does not change its rail behaviour.
/// Note tabs share the same close, menu, reordering, and keyboard rules as
/// sessions; only their content is plain text rather than a web view.
enum RailEntry: Hashable, Identifiable {
    case favourite(UUID)
    case tab(UUID)
    case note(UUID)

    init(_ kind: SessionKind) {
        switch kind {
        case .favourite(let id): self = .favourite(id)
        case .tab(let id): self = .tab(id)
        }
    }

    var id: Self { self }

    /// The session behind this entry, or `nil` for a note tab.
    var sessionKind: SessionKind? {
        switch self {
        case .favourite(let id): .favourite(id)
        case .tab(let id): .tab(id)
        case .note: nil
        }
    }

    var tabID: UUID? {
        guard case .tab(let id) = self else { return nil }
        return id
    }

    var noteID: UUID? {
        guard case .note(let id) = self else { return nil }
        return id
    }
}

/// The rail edge that should show an insertion line during a drag: the line is
/// drawn on `isBelow ? bottom : top` of the row identified by `entry`.
struct RailDropLine: Equatable {
    let entry: RailEntry
    let isBelow: Bool
}

/// Pure ordering arithmetic for the rail.
///
/// Favourite order belongs to Home and never participates here. Reordering a
/// rail row only rewrites the in-memory order of currently open items.
enum RailLayout {
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

/// Which rail item to select after closing one.
enum RailSelection {
    /// Mirrors a browser: the row that slides into the closed one's place, or
    /// the row before it when the last one is closed.
    static func successor<Entry: Equatable>(after entry: Entry, in entries: [Entry]) -> Entry? {
        guard let index = entries.firstIndex(of: entry) else { return nil }
        var remaining = entries
        remaining.remove(at: index)
        guard !remaining.isEmpty else { return nil }
        return remaining[min(index, remaining.count - 1)]
    }
}
