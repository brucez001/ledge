import Foundation

/// One locally persisted note.
///
/// Notes are plain Markdown text files under
/// `~/Library/Application Support/Ledge/Notes/`, one file per note, named
/// by UUID. Only the text itself is stored: the title is the first
/// non-empty line and the timestamps come from the file's own dates. The
/// *window* that shows a note is ephemeral, exactly like an open web
/// session, but the note itself survives across launches.
struct Note: Identifiable, Equatable {
    let id: UUID
    var body: String
    var createdAt: Date
    var updatedAt: Date

    /// Longest title worth showing on a Home tile or window title before
    /// truncation.
    static let maxTitleLength = 32

    /// The first non-empty line, with a leading Markdown heading marker
    /// removed and the result truncated to a tile-friendly length.
    var title: String {
        Self.title(from: body)
    }

    static func title(from body: String) -> String {
        let firstLine = body
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        // A Markdown heading marker ("#" / "## ") is the title's own
        // decoration; strip it so tiles and window titles stay clean.
        let heading = firstLine.hasPrefix("#")
            ? String(firstLine.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces))
            : firstLine
        guard !heading.isEmpty else { return "Note" }
        if heading.count <= Self.maxTitleLength { return heading }
        return String(heading.prefix(Self.maxTitleLength)) + "…"
    }

    /// A one-line peek for a Home tile, dropping the title line itself.
    var preview: String {
        var lines = body.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return "No text yet" }
        lines.removeFirst()
        guard let line = lines.first?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !line.isEmpty else { return "No text yet" }
        let collapsed = line.replacingOccurrences(of: "\n", with: " ")
        return collapsed.count <= 60
            ? collapsed
            : String(collapsed.prefix(59)) + "…"
    }
}
