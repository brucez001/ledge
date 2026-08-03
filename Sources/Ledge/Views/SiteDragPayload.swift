import Foundation
import UniformTypeIdentifiers
import SwiftUI

/// The drag payload used to reorder saved sites.
///
/// It rides on plain text (which needs no declared custom type) but is
/// prefixed, so a stray drop of text from another app cannot be mistaken for a
/// reorder, and dragging a site into a text field produces something
/// recognisable rather than a bare UUID.
enum SiteDragPayload {
    static let type = UTType.plainText
    private static let sitePrefix = "ledge.site:"
    private static let tabPrefix = "ledge.tab:"

    /// What is being dragged around the rail.
    enum Item: Equatable {
        /// A saved site being reordered.
        case site(UUID)
        /// A transient tab being dragged into the saved sites to pin it.
        case tab(UUID)
    }

    static func encode(_ id: UUID) -> String {
        sitePrefix + id.uuidString
    }

    static func encodeTab(_ id: UUID) -> String {
        tabPrefix + id.uuidString
    }

    /// Site-only decode, for the drop targets that can accept nothing else.
    static func decode(_ string: String) -> UUID? {
        guard case .site(let id) = decodeItem(string) else { return nil }
        return id
    }

    static func decodeItem(_ string: String) -> Item? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(sitePrefix),
           let id = UUID(uuidString: String(trimmed.dropFirst(sitePrefix.count))) {
            return .site(id)
        }
        if trimmed.hasPrefix(tabPrefix),
           let id = UUID(uuidString: String(trimmed.dropFirst(tabPrefix.count))) {
            return .tab(id)
        }
        return nil
    }
}

/// Where a dragged site would land: above or below the row being hovered.
struct SiteDropInsertion: Equatable {
    let targetID: UUID
    let isBelow: Bool
}

extension View {
    /// Attaches `.onDrag` only when `condition` holds. An empty tab has nothing
    /// to pin, so it should not offer a drag at all rather than starting one
    /// that can never be dropped anywhere useful.
    @ViewBuilder
    func onDrag(if condition: Bool, payload: @escaping () -> NSItemProvider) -> some View {
        if condition {
            onDrag(payload)
        } else {
            self
        }
    }
}
