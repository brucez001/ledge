import Foundation

/// How a note's title and text share one plain-text file.
///
/// The title is not the first line of the note: it is its own value, held
/// in a short Markdown front-matter block above the text.
///
///     ---
///     title: Shopping list
///     ---
///     # Weekend
///     - milk
///
/// This keeps the two independent -- renaming a note leaves its Markdown
/// alone, and typing a heading leaves its name alone -- while the file
/// stays plain text that any editor can open. Other front-matter lines are
/// preserved verbatim.
///
/// Files written before titles were stored have no front matter; they
/// parse as a whole body with no title, and the store names them from
/// their first line once, on load.
enum NoteFile {
    static let delimiter = "---"
    private static let titleKey = "title:"

    struct Parsed: Equatable {
        /// Empty when the file carries no title of its own, which is what
        /// a note written by an older build looks like.
        var title: String
        var extraFrontMatter: [String]
        var body: String
    }

    static func parse(_ text: String) -> Parsed {
        var lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == delimiter,
              let closing = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespaces) == delimiter
              })
        else {
            return Parsed(title: "", extraFrontMatter: [], body: text)
        }

        var title: String?
        var extra: [String] = []
        for line in lines[1..<closing] {
            if title == nil, let value = titleValue(in: line) {
                title = value
            } else {
                extra.append(line)
            }
        }
        // A pair of horizontal rules is ordinary Markdown unless the block
        // contains the title field Ledge itself writes.
        guard let title else {
            return Parsed(title: "", extraFrontMatter: [], body: text)
        }

        lines.removeSubrange(0...closing)
        // The single blank line separating the block from the text is
        // punctuation, not content.
        if lines.first?.isEmpty == true { lines.removeFirst() }
        return Parsed(title: title, extraFrontMatter: extra, body: lines.joined(separator: "\n"))
    }

    static func serialise(title: String, extraFrontMatter: [String] = [], body: String) -> String {
        let name = Note.sanitisedTitle(title)
        guard !name.isEmpty || !extraFrontMatter.isEmpty else { return body }

        var header = [delimiter]
        if !name.isEmpty { header.append("\(titleKey) \(quoteIfNeeded(name))") }
        header.append(contentsOf: extraFrontMatter)
        header.append(delimiter)
        header.append("")
        return header.joined(separator: "\n") + body
    }

    // MARK: - Values

    /// Quoting is only for a title a reader would otherwise misread: one
    /// that already looks quoted.
    private static func quoteIfNeeded(_ value: String) -> String {
        guard value.hasPrefix("\"") || value.hasSuffix("\"") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
    }

    private static func titleValue(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.firstIndex(of: ":"),
              trimmed[..<colon].lowercased() == "title" else { return nil }
        return unquote(String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
    }
}
