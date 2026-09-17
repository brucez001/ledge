import Foundation
import UniformTypeIdentifiers

/// The drag payload used to reorder tiles on the home grids and rows in the
/// rail.
///
/// It rides on plain text (which needs no declared custom type) but is
/// prefixed, so a stray drop of text from another app cannot be mistaken for a
/// reorder, and dragging a site into a text field produces something
/// recognisable rather than a bare UUID.
///
/// The prefix is also the only thing separating one grid from another: both
/// home grids accept plain text, so each decodes only its own prefix and
/// declines everything else.
enum SiteDragPayload {
    static let type = UTType.plainText

    /// What is being dragged, and the prefix its payload carries. Each
    /// surface reads only its own kind, so a Home shortcut cannot be dropped
    /// into the open session order and a note cannot be dropped into the
    /// favourites grid.
    enum Kind: String, CaseIterable {
        case homeFavourite = "ledge.home-favourite:"
        case homeNote = "ledge.home-note:"
        case railFavourite = "ledge.rail-favourite:"
        case railTab = "ledge.rail-tab:"
        case railNote = "ledge.rail-note:"
    }

    /// What is being dragged around the rail.
    enum Item: Equatable {
        /// A session associated with a Home favourite.
        case site(UUID)
        /// An ordinary session with no Home favourite.
        case tab(UUID)
        /// An open note tab.
        case note(UUID)
    }

    static func encode(_ kind: Kind, _ id: UUID) -> String {
        kind.rawValue + id.uuidString
    }

    /// Reads an id only when the payload is the kind asked for.
    static func decode(_ kind: Kind, from string: String) -> UUID? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(kind.rawValue) else { return nil }
        return UUID(uuidString: String(trimmed.dropFirst(kind.rawValue.count)))
    }

    /// Rail-only decode, so a Home shortcut cannot be dragged into the open
    /// session order before it has actually been opened.
    static func decodeItem(_ string: String) -> Item? {
        if let id = decode(.railFavourite, from: string) { return .site(id) }
        if let id = decode(.railTab, from: string) { return .tab(id) }
        if let id = decode(.railNote, from: string) { return .note(id) }
        return nil
    }
}
