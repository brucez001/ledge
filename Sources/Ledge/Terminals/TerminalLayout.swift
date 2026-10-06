import CoreGraphics
import Foundation

/// How a split divides its space.
enum TerminalSplitOrientation: String, Codable, Sendable {
    /// Side by side, with a vertical divider ("Split Right").
    case sideBySide
    /// One above the other, with a horizontal divider ("Split Down").
    case stacked
}

/// A direction to move focus between panes.
enum TerminalPaneDirection: Sendable {
    case left
    case right
    case up
    case down
}

/// The panes of one terminal tab: a binary tree of splits whose leaves are
/// shells, identified by the shell's id.
///
/// Geometry is in a flipped coordinate space -- y grows downwards -- so the
/// first side of a stacked split is the upper one.
indirect enum TerminalLayout: Equatable, Sendable {
    case pane(UUID)
    case split(TerminalSplit)

    /// Neither side of a split may shrink below this share of it.
    static let fractionRange: ClosedRange<Double> = 0.15...0.85

    /// Every pane, left to right and top to bottom.
    var paneIDs: [UUID] {
        switch self {
        case .pane(let id): [id]
        case .split(let split): split.first.paneIDs + split.second.paneIDs
        }
    }

    var paneCount: Int { paneIDs.count }

    /// Divides pane `id` in two, with `newPane` to its right or below it.
    /// Unchanged if there is no such pane.
    func splitting(_ id: UUID, _ orientation: TerminalSplitOrientation, newPane: UUID) -> TerminalLayout {
        switch self {
        case .pane(let existing):
            guard existing == id else { return self }
            return .split(TerminalSplit(
                id: UUID(),
                orientation: orientation,
                fraction: 0.5,
                first: self,
                second: .pane(newPane)
            ))
        case .split(var split):
            split.first = split.first.splitting(id, orientation, newPane: newPane)
            split.second = split.second.splitting(id, orientation, newPane: newPane)
            return .split(split)
        }
    }

    /// The layout without pane `id`: its sibling takes over the space the two
    /// shared. `nil` when `id` was the only pane.
    func removing(_ id: UUID) -> TerminalLayout? {
        switch self {
        case .pane(let existing):
            return existing == id ? nil : self
        case .split(var split):
            guard let first = split.first.removing(id) else { return split.second }
            guard let second = split.second.removing(id) else { return split.first }
            split.first = first
            split.second = second
            return .split(split)
        }
    }

    /// Moves the divider of split `id`, kept within `fractionRange`.
    func settingFraction(_ fraction: Double, forSplit id: UUID) -> TerminalLayout {
        guard case .split(var split) = self else { return self }
        if split.id == id {
            split.fraction = Self.clampedFraction(fraction)
        } else {
            split.first = split.first.settingFraction(fraction, forSplit: id)
            split.second = split.second.settingFraction(fraction, forSplit: id)
        }
        return .split(split)
    }

    static func clampedFraction(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0.5 }
        return min(max(fraction, fractionRange.lowerBound), fractionRange.upperBound)
    }

    // MARK: - Geometry

    /// Where every pane and divider sits within `rect`. Each divider takes
    /// `dividerThickness` points out of its split; pane edges land on whole
    /// points so text stays sharp.
    func geometry(in rect: CGRect, dividerThickness: CGFloat) -> TerminalGeometry {
        var geometry = TerminalGeometry()
        layOut(in: rect, dividerThickness: dividerThickness, into: &geometry)
        return geometry
    }

    private func layOut(in rect: CGRect, dividerThickness: CGFloat, into geometry: inout TerminalGeometry) {
        switch self {
        case .pane(let id):
            geometry.panes.append(TerminalGeometry.Pane(id: id, frame: rect))
        case .split(let split):
            let (first, divider, second) = split.divide(rect, dividerThickness: dividerThickness)
            split.first.layOut(in: first, dividerThickness: dividerThickness, into: &geometry)
            geometry.dividers.append(TerminalGeometry.Divider(
                splitID: split.id,
                orientation: split.orientation,
                frame: divider,
                span: rect,
                thickness: dividerThickness
            ))
            split.second.layOut(in: second, dividerThickness: dividerThickness, into: &geometry)
        }
    }

    // MARK: - Focus movement

    /// The pane `offset` places after `id` in reading order, wrapping round.
    func pane(from id: UUID, movedBy offset: Int) -> UUID? {
        let ids = paneIDs
        guard let index = ids.firstIndex(of: id) else { return nil }
        let count = ids.count
        return ids[((index + offset) % count + count) % count]
    }
}

struct TerminalSplit: Equatable, Sendable {
    let id: UUID
    var orientation: TerminalSplitOrientation
    /// The share of the space given to `first`.
    var fraction: Double
    var first: TerminalLayout
    var second: TerminalLayout

    func divide(_ rect: CGRect, dividerThickness: CGFloat) -> (CGRect, CGRect, CGRect) {
        switch orientation {
        case .sideBySide:
            let available = max(rect.width - dividerThickness, 0)
            let firstWidth = (available * fraction).rounded(.down)
            let first = CGRect(x: rect.minX, y: rect.minY, width: firstWidth, height: rect.height)
            let divider = CGRect(x: first.maxX, y: rect.minY, width: dividerThickness, height: rect.height)
            let second = CGRect(
                x: divider.maxX, y: rect.minY,
                width: max(rect.maxX - divider.maxX, 0), height: rect.height
            )
            return (first, divider, second)
        case .stacked:
            let available = max(rect.height - dividerThickness, 0)
            let firstHeight = (available * fraction).rounded(.down)
            let first = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstHeight)
            let divider = CGRect(x: rect.minX, y: first.maxY, width: rect.width, height: dividerThickness)
            let second = CGRect(
                x: rect.minX, y: divider.maxY,
                width: rect.width, height: max(rect.maxY - divider.maxY, 0)
            )
            return (first, divider, second)
        }
    }
}

/// Laid-out frames for one terminal tab, in the layout's flipped space.
struct TerminalGeometry: Equatable {
    struct Pane: Equatable {
        let id: UUID
        let frame: CGRect
    }

    struct Divider: Equatable {
        let splitID: UUID
        let orientation: TerminalSplitOrientation
        let frame: CGRect
        /// The whole space the split divides.
        let span: CGRect
        let thickness: CGFloat

        /// The split fraction that puts this divider under `point`.
        func fraction(at point: CGPoint) -> Double {
            switch orientation {
            case .sideBySide:
                let available = span.width - thickness
                guard available > 0 else { return 0.5 }
                return TerminalLayout.clampedFraction((point.x - span.minX - thickness / 2) / available)
            case .stacked:
                let available = span.height - thickness
                guard available > 0 else { return 0.5 }
                return TerminalLayout.clampedFraction((point.y - span.minY - thickness / 2) / available)
            }
        }
    }

    /// In reading order.
    var panes: [Pane] = []
    var dividers: [Divider] = []

    func frame(of id: UUID) -> CGRect? {
        panes.first { $0.id == id }?.frame
    }

    /// The nearest pane beside `id` in `direction`: of the panes whose edge
    /// faces it, the closest, then the one sharing the most of that edge,
    /// then the first in reading order.
    func neighbour(of id: UUID, toward direction: TerminalPaneDirection) -> UUID? {
        guard let from = frame(of: id) else { return nil }
        let tolerance: CGFloat = 0.5
        var best: (id: UUID, distance: CGFloat, overlap: CGFloat)?
        for pane in panes where pane.id != id {
            let rect = pane.frame
            let distance: CGFloat
            let overlap: CGFloat
            switch direction {
            case .left:
                guard rect.maxX <= from.minX + tolerance else { continue }
                distance = from.minX - rect.maxX
                overlap = min(rect.maxY, from.maxY) - max(rect.minY, from.minY)
            case .right:
                guard rect.minX >= from.maxX - tolerance else { continue }
                distance = rect.minX - from.maxX
                overlap = min(rect.maxY, from.maxY) - max(rect.minY, from.minY)
            case .up:
                guard rect.maxY <= from.minY + tolerance else { continue }
                distance = from.minY - rect.maxY
                overlap = min(rect.maxX, from.maxX) - max(rect.minX, from.minX)
            case .down:
                guard rect.minY >= from.maxY - tolerance else { continue }
                distance = rect.minY - from.maxY
                overlap = min(rect.maxX, from.maxX) - max(rect.minX, from.minX)
            }
            guard overlap > 0 else { continue }
            if let current = best {
                let closer = distance < current.distance - tolerance
                let tied = abs(distance - current.distance) <= tolerance
                guard closer || (tied && overlap > current.overlap + tolerance) else { continue }
            }
            best = (pane.id, distance, overlap)
        }
        return best?.id
    }
}

/// Where a pane's title bar and terminal sit within the pane's frame, in the
/// layout's flipped space.
///
/// Only split panes have a title bar: a tab with one pane is already named,
/// and closed, by its rail row.
enum TerminalPaneChrome {
    static let headerHeight: CGFloat = 24
    /// Between the title bar and the terminal beneath it.
    static let headerGap: CGFloat = 4

    static func frames(for pane: CGRect, showsHeader: Bool) -> (header: CGRect?, terminal: CGRect) {
        guard showsHeader else { return (nil, pane) }
        let header = CGRect(x: pane.minX, y: pane.minY, width: pane.width, height: min(headerHeight, pane.height))
        let top = min(header.maxY + headerGap, pane.maxY)
        let terminal = CGRect(x: pane.minX, y: top, width: pane.width, height: pane.maxY - top)
        return (header, terminal)
    }
}

/// A terminal tab's panes as they survive a quit: the shape of the splits and
/// each pane's directory, never what any of them printed or ran.
indirect enum TerminalArrangement: Codable, Equatable, Sendable {
    case pane(directory: URL?)
    case split(
        orientation: TerminalSplitOrientation,
        fraction: Double,
        first: TerminalArrangement,
        second: TerminalArrangement
    )

    /// The same shape, with each directory passed through `transform`.
    func mappingDirectories(_ transform: (URL?) -> URL?) -> TerminalArrangement {
        switch self {
        case .pane(let directory):
            .pane(directory: transform(directory))
        case .split(let orientation, let fraction, let first, let second):
            .split(
                orientation: orientation,
                fraction: fraction,
                first: first.mappingDirectories(transform),
                second: second.mappingDirectories(transform)
            )
        }
    }
}
