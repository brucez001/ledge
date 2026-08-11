import Foundation
import UniformTypeIdentifiers

/// The drag payload used to reorder open rail sessions.
///
/// It rides on plain text (which needs no declared custom type) but is
/// prefixed, so a stray drop of text from another app cannot be mistaken for a
/// reorder, and dragging a site into a text field produces something
/// recognisable rather than a bare UUID.
enum SiteDragPayload {
    static let type = UTType.plainText
    private static let homeFavouritePrefix = "ledge.home-favourite:"
    private static let railFavouritePrefix = "ledge.rail-favourite:"
    private static let railTabPrefix = "ledge.rail-tab:"

    /// What is being dragged around the rail.
    enum Item: Equatable {
        /// A session associated with a Home favourite.
        case site(UUID)
        /// An ordinary session with no Home favourite.
        case tab(UUID)
    }

    static func encode(_ id: UUID) -> String {
        homeFavouritePrefix + id.uuidString
    }

    static func encodeRailFavourite(_ id: UUID) -> String {
        railFavouritePrefix + id.uuidString
    }

    static func encodeRailTab(_ id: UUID) -> String {
        railTabPrefix + id.uuidString
    }

    /// Home-only decode, so a rail session cannot reorder shortcut tiles.
    static func decode(_ string: String) -> UUID? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(homeFavouritePrefix) else { return nil }
        return UUID(uuidString: String(trimmed.dropFirst(homeFavouritePrefix.count)))
    }

    /// Rail-only decode, so a Home shortcut cannot be dragged into the open
    /// session order before it has actually been opened.
    static func decodeItem(_ string: String) -> Item? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(railFavouritePrefix),
           let id = UUID(uuidString: String(trimmed.dropFirst(railFavouritePrefix.count))) {
            return .site(id)
        }
        if trimmed.hasPrefix(railTabPrefix),
           let id = UUID(uuidString: String(trimmed.dropFirst(railTabPrefix.count))) {
            return .tab(id)
        }
        return nil
    }
}
