import Foundation

extension Array where Element: Identifiable {
    /// Moves one element directly before another, and reports whether the
    /// order actually changed, so a caller only persists a real move.
    ///
    /// An unknown target appends rather than failing: a drop past the last
    /// element still has to land somewhere.
    @discardableResult
    mutating func move(id: Element.ID, before targetID: Element.ID) -> Bool {
        guard id != targetID, let source = firstIndex(where: { $0.id == id }) else { return false }
        let moved = remove(at: source)
        if let target = firstIndex(where: { $0.id == targetID }) {
            insert(moved, at: target)
        } else {
            append(moved)
        }
        return true
    }

    /// Moves one element directly after another, which is what dropping on
    /// the lower half of a row means.
    @discardableResult
    mutating func move(id: Element.ID, after targetID: Element.ID) -> Bool {
        guard id != targetID, let source = firstIndex(where: { $0.id == id }) else { return false }
        let moved = remove(at: source)
        if let target = firstIndex(where: { $0.id == targetID }) {
            insert(moved, at: target + 1)
        } else {
            append(moved)
        }
        return true
    }

    /// Moves one element to the end. `move(id:before:)` cannot express this,
    /// so a grid that only drops "before" a tile cannot otherwise reach the
    /// last position.
    @discardableResult
    mutating func moveToEnd(id: Element.ID) -> Bool {
        guard let source = firstIndex(where: { $0.id == id }), source != count - 1 else { return false }
        append(remove(at: source))
        return true
    }

    /// Nudges one element one place towards the front.
    @discardableResult
    mutating func moveUp(id: Element.ID) -> Bool {
        guard let index = firstIndex(where: { $0.id == id }), index > 0 else { return false }
        swapAt(index, index - 1)
        return true
    }

    @discardableResult
    mutating func moveDown(id: Element.ID) -> Bool {
        guard let index = firstIndex(where: { $0.id == id }), index < count - 1 else { return false }
        swapAt(index, index + 1)
        return true
    }
}
