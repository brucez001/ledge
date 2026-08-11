import SwiftUI

/// Tracks the live rail drag so every row can draw the insertion line in the
/// same place the drop will actually land.
///
/// One coordinator is shared by the whole rail: each row's drop delegate
/// reports the pointer, and each row asks whether the line belongs on its own
/// top or bottom edge.
@MainActor
final class RailDropCoordinator: ObservableObject {
    /// The row edge currently showing the line, or `nil` when no drag is in
    /// flight and when the drop would change nothing.
    @Published private(set) var line: RailDropLine?

    /// The row that picked up the drag. Needed to recognise a hover over the
    /// dragged row itself as a no-op rather than drawing it as a move.
    private var dragged: RailEntry?
    /// The row the pointer was last seen over, tracked separately from `line`
    /// because a no-op hover produces no line but still owns the pointer.
    private var pointer: RailEntry?

    func begin(dragging entry: RailEntry) {
        dragged = entry
    }

    /// Recomputes the line for a pointer sitting over `target`.
    func pointerMoved(over target: RailEntry, isBelow: Bool, in entries: [RailEntry]) {
        guard let dragged else { return }
        pointer = target
        line = RailLayout.insertionLine(
            dragging: dragged,
            over: target,
            isBelow: isBelow,
            in: entries
        )
    }

    /// Clears the line as the pointer leaves `target`.
    ///
    /// SwiftUI can deliver the previous row's exit *after* the next row's
    /// enter, so a stale exit must not wipe a line the newer row has already
    /// claimed. Only the row still being pointed at may clear it.
    func pointerLeft(_ target: RailEntry) {
        guard pointer == target else { return }
        line = nil
        pointer = nil
    }

    /// Ends the drag, whether it was dropped, cancelled, or left the rail.
    func end() {
        dragged = nil
        pointer = nil
        line = nil
    }

    /// Whether `entry` should draw the line on the given edge.
    func showsLine(for entry: RailEntry, isBelow: Bool) -> Bool {
        line == RailDropLine(entry: entry, isBelow: isBelow)
    }
}
