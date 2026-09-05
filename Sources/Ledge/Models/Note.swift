import Foundation

/// One locally persisted note.
///
/// Notes are plain Markdown text files under
/// `~/Library/Application Support/Ledge/Notes/`, one file per note, named
/// by UUID. The note's title is its own field, kept in a small Markdown
/// front-matter block at the top of the file, and the timestamps come from
/// the file's own dates. The title and the note's text are independent:
/// renaming a note never rewrites its Markdown, and writing a heading
/// never renames the note. The open tab that shows a note is ephemeral,
/// exactly like an open web session, but the note itself survives across
/// launches.
struct Note: Identifiable, Equatable {
    let id: UUID
    /// The note's own name, as the user typed it. Never derived from the
    /// body once it exists.
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var extraFrontMatter: [String]

    init(
        id: UUID,
        title: String = "",
        body: String,
        createdAt: Date,
        updatedAt: Date,
        extraFrontMatter: [String] = []
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.extraFrontMatter = extraFrontMatter
    }

    /// Longest title worth showing on a Home tile or rail item before
    /// truncation.
    static let maxTitleLength = 32

    /// The name a note carries until it is given one.
    static let untitledTitle = "New Note"

    /// The title as a tile, rail tooltip, or header can show it: trimmed,
    /// truncated, and never blank.
    var displayTitle: String {
        Self.displayTitle(for: title)
    }

    static func displayTitle(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Self.untitledTitle }
        if trimmed.count <= Self.maxTitleLength { return trimmed }
        return String(trimmed.prefix(Self.maxTitleLength)) + "…"
    }

    /// A title is one line by definition, so a pasted paragraph collapses
    /// into one before it is stored.
    static func sanitisedTitle(_ raw: String) -> String {
        raw
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name to give a note file written before titles were stored:
    /// its first line, read the way a tile used to read it. Used once, at
    /// load, so an existing note keeps the name its owner already knows.
    static func inferredTitle(from body: String) -> String {
        // Markdown markers are the heading's own decoration, not part of
        // the name: "## **Plans**" names a note "Plans".
        let heading = MarkdownSummary.firstProseLine(in: body) ?? ""
        guard !heading.isEmpty else { return Self.untitledTitle }
        return heading
    }

    /// A one-line peek for a Home tile.
    var preview: String {
        // Flattened: raw table pipes, fences, and list markers tell the
        // reader nothing about what is in the note. A body that opens by
        // repeating the note's own name is skipped -- the tile already
        // says it on the line above.
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = MarkdownSummary.firstProseLine(in: body)
        let line = (first == name && !name.isEmpty)
            ? MarkdownSummary.firstProseLine(in: body, skippingFirstProseLine: true)
            : first
        guard let line else {
            return "No text yet"
        }
        return line.count <= 60 ? line : String(line.prefix(59)) + "…"
    }
}
