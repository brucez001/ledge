import Foundation

/// Flattens Markdown into the short, decoration-free strings the interface
/// shows *about* a note -- its Home tile title and preview, its rail
/// tooltip, its window title.
///
/// Deliberately separate from `MarkdownEditing.clearFormatting`, which
/// rewrites the user's own text and must therefore be conservative. This
/// only produces display strings, so it can take liberties the editor
/// must not: table rows collapse to their cells, and structural lines
/// (fences, rules, delimiter rows) are skipped entirely because they say
/// nothing about what a note contains.
enum MarkdownSummary {
    /// Markers that carry no prose on their own.
    private static let ruleCharacters: Set<Character> = ["-", "*", "_"]

    /// True when a line is pure Markdown scaffolding: a fence, a
    /// horizontal rule, or a table's `| --- |` delimiter row.
    static func isStructural(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { return true }

        // A rule is three or more of one marker, spaces allowed between.
        let ruleBody = trimmed.filter { !$0.isWhitespace }
        if ruleBody.count >= 3,
           let first = ruleBody.first,
           ruleCharacters.contains(first),
           ruleBody.allSatisfy({ $0 == first }) {
            return true
        }

        // A delimiter row has nothing but pipes, dashes, colons, spaces.
        if trimmed.contains("|"),
           trimmed.allSatisfy({ $0 == "|" || $0 == "-" || $0 == ":" || $0.isWhitespace }) {
            return true
        }
        return false
    }

    /// One line of Markdown as plain prose: block markers removed, table
    /// cells joined, inline markers and link syntax stripped, whitespace
    /// collapsed.
    static func plainLine(_ line: String) -> String {
        var text = stripBlockMarkers(line.trimmingCharacters(in: .whitespaces))
        if text.contains("|") {
            text = joinTableCells(text)
        }
        text = stripLinks(text)
        text = stripInlineMarkers(text)
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The first line of `body` that actually says something, flattened.
    /// `skippingFirstProseLine` is how the preview avoids repeating the
    /// title that sits directly above it on the tile.
    static func firstProseLine(in body: String, skippingFirstProseLine: Bool = false) -> String? {
        var skipped = false
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            guard !isStructural(String(line)) else { continue }
            let plain = plainLine(String(line))
            guard !plain.isEmpty else { continue }
            if skippingFirstProseLine, !skipped {
                skipped = true
                continue
            }
            return plain
        }
        return nil
    }

    // MARK: - Pieces

    /// Removes leading quote, list, task, and heading markers, however many
    /// are stacked (`> - [ ] ` is one line's worth of scaffolding).
    private static func stripBlockMarkers(_ line: String) -> String {
        var text = line
        var changed = true
        while changed {
            changed = false
            text = text.trimmingCharacters(in: .whitespaces)

            if text.hasPrefix("#") {
                let stripped = String(text.drop(while: { $0 == "#" }))
                // "#hashtag" is a word, not a heading: only treat the run
                // as a marker when a space follows it, or it is the whole
                // line.
                if stripped.isEmpty || stripped.hasPrefix(" ") {
                    text = stripped
                    changed = true
                    continue
                }
            }

            if text.hasPrefix(">") {
                text = String(text.dropFirst())
                changed = true
                continue
            }

            for marker in ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] ", "- ", "* ", "+ "] {
                if text.hasPrefix(marker) {
                    text = String(text.dropFirst(marker.count))
                    changed = true
                    break
                }
            }
            if changed { continue }

            let digits = text.prefix(while: { $0.isNumber })
            if !digits.isEmpty {
                let rest = text.dropFirst(digits.count)
                if let separator = rest.first, separator == "." || separator == ")",
                   rest.dropFirst().hasPrefix(" ") {
                    text = String(rest.dropFirst(2))
                    changed = true
                }
            }
        }
        return text
    }

    /// `| Tool | Shortcut |` reads as "Tool, Shortcut": the pipes are the
    /// table's own punctuation and mean nothing in a one-line summary. A
    /// comma rather than a middot because a tile is narrow enough to wrap,
    /// and a wrapped line beginning with "·" looks like a bullet that lost
    /// its list.
    private static func joinTableCells(_ text: String) -> String {
        let cells = text
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !cells.isEmpty else { return "" }
        return cells.joined(separator: ", ")
    }

    /// `[text](url)` and `![alt](url)` keep only what a reader would read.
    private static func stripLinks(_ text: String) -> String {
        var result = ""
        var remainder = Substring(text)

        while let open = remainder.firstIndex(of: "[") {
            guard let close = remainder[open...].firstIndex(of: "]") else { break }
            let afterClose = remainder.index(after: close)
            guard afterClose < remainder.endIndex, remainder[afterClose] == "(",
                  let paren = remainder[afterClose...].firstIndex(of: ")") else {
                result += remainder[..<afterClose]
                remainder = remainder[afterClose...]
                continue
            }
            var before = remainder[..<open]
            // Drop an image's "!" along with its brackets.
            if before.hasSuffix("!") { before = before.dropLast() }
            result += before
            result += remainder[remainder.index(after: open)..<close]
            remainder = remainder[remainder.index(after: paren)...]
        }

        result += remainder
        return result
    }

    private static func stripInlineMarkers(_ text: String) -> String {
        var result = text
        // Longest markers first, so `**` is never mistaken for two `*`.
        for marker in ["***", "**", "~~", "__", "*", "_", "`"] {
            result = result.replacingOccurrences(of: marker, with: "")
        }
        return result
    }
}
