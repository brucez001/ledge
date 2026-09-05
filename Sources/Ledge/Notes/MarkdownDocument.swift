import Foundation

/// One item within a bullet or numbered list block.
struct MarkdownListItem: Equatable {
    var text: String
    var indent: Int
}

/// One item within a task list block (`- [ ]` / `- [x]`).
struct MarkdownTaskItem: Equatable {
    var text: String
    var isDone: Bool
    var indent: Int
}

/// A single structural unit of a parsed Markdown document.
///
/// Blocks keep their inline text verbatim (`**bold**`, `[a link](url)`,
/// `` `code` `` and so on are not resolved here): `MarkdownPreview` is
/// responsible for that second, presentation-level pass, so this type stays
/// a plain, comparable description of document structure.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulletList([MarkdownListItem])
    case numberedList([MarkdownListItem])
    case taskList([MarkdownTaskItem])
    case quote([String])
    case codeBlock(language: String?, code: String)
    case divider
    case table(header: [String], rows: [[String]])
}

/// A minimal block-level Markdown parser for the notes preview.
///
/// This recognises the subset of Markdown a short, local plain-text note is
/// likely to contain -- headings, lists, quotes, fenced code, tables, and
/// dividers -- rather than aiming for full CommonMark compliance. There is
/// deliberately no support for HTML blocks, link reference definitions, or
/// nested block quotes: notes are not a general-purpose document format, and
/// keeping the grammar small keeps the parser (and `MarkdownPreview`, which
/// renders its output) easy to reason about.
enum MarkdownDocument {
    /// Splits `markdown` into an ordered list of top-level blocks.
    ///
    /// Pure and `nonisolated`: it touches no shared state and performs no
    /// side effects, so it is safe to call from a view's `body` (which is
    /// what `MarkdownPreview` does) without pulling parsing work onto the
    /// main actor.
    nonisolated static func parse(_ markdown: String) -> [MarkdownBlock] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }

            if let (block, next) = parseCodeFence(lines, from: index) {
                blocks.append(block)
                index = next
                continue
            }

            if let heading = parseHeading(line) {
                blocks.append(heading)
                index += 1
                continue
            }

            if isDivider(line) {
                blocks.append(.divider)
                index += 1
                continue
            }

            if let (table, next) = parseTable(lines, from: index) {
                blocks.append(table)
                index = next
                continue
            }

            if let (quote, next) = parseQuote(lines, from: index) {
                blocks.append(quote)
                index = next
                continue
            }

            if let (list, next) = parseList(lines, from: index) {
                blocks.append(list)
                index = next
                continue
            }

            let (paragraph, next) = parseParagraph(lines, from: index)
            blocks.append(paragraph)
            index = next
        }

        return blocks
    }

    // MARK: - Fenced code

    /// Recognises a ``` / ~~~ fence, consuming lines verbatim until a
    /// matching closing fence or the end of the text.
    private static func parseCodeFence(_ lines: [String], from start: Int) -> (MarkdownBlock, Int)? {
        let trimmed = lines[start].trimmingCharacters(in: .whitespaces)
        guard let fenceChar = trimmed.first, fenceChar == "`" || fenceChar == "~" else { return nil }
        let fenceRun = trimmed.prefix { $0 == fenceChar }
        guard fenceRun.count >= 3 else { return nil }

        let info = String(trimmed.dropFirst(fenceRun.count)).trimmingCharacters(in: .whitespaces)
        let language = info.isEmpty ? nil : info

        var index = start + 1
        var codeLines: [String] = []
        while index < lines.count {
            let candidate = lines[index].trimmingCharacters(in: .whitespaces)
            let closingRun = candidate.prefix { $0 == fenceChar }
            if closingRun.count >= fenceRun.count, closingRun.count == candidate.count {
                return (.codeBlock(language: language, code: codeLines.joined(separator: "\n")), index + 1)
            }
            codeLines.append(lines[index])
            index += 1
        }

        // No closing fence: per the spec, the code block runs to the end of
        // the text rather than swallowing the rest of the document as plain
        // paragraphs.
        return (.codeBlock(language: language, code: codeLines.joined(separator: "\n")), index)
    }

    private static func isFenceStart(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "`" || first == "~" else { return false }
        return trimmed.prefix { $0 == first }.count >= 3
    }

    // MARK: - Headings

    /// Matches an ATX heading (`#` through `######`), clamping a longer run
    /// of hashes to level 6 and trimming a trailing hash run and surrounding
    /// whitespace from the heading text.
    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        var chars = Substring(line)
        var leadingSpaces = 0
        while leadingSpaces < 3, chars.first == " " {
            chars.removeFirst()
            leadingSpaces += 1
        }

        let hashRun = chars.prefix { $0 == "#" }
        guard !hashRun.isEmpty else { return nil }
        let rest = chars.dropFirst(hashRun.count)
        guard rest.isEmpty || rest.first == " " else { return nil }

        let level = min(hashRun.count, 6)
        var text = String(rest).trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") {
            text.removeLast()
        }
        text = text.trimmingCharacters(in: .whitespaces)
        return .heading(level: level, text: text)
    }

    // MARK: - Dividers

    /// A thematic break is three or more matching `-`, `*`, or `_` characters,
    /// optionally separated by spaces, and nothing else on the line.
    private static func isDivider(_ line: String) -> Bool {
        let compact = line.trimmingCharacters(in: .whitespaces).filter { $0 != " " }
        guard compact.count >= 3, let marker = compact.first else { return false }
        guard marker == "-" || marker == "*" || marker == "_" else { return false }
        return compact.allSatisfy { $0 == marker }
    }

    // MARK: - Block quotes

    /// Collapses a run of consecutive `>`-prefixed lines into one quote
    /// block, stripping the marker (and one following space, if present)
    /// from each line.
    private static func parseQuote(_ lines: [String], from start: Int) -> (MarkdownBlock, Int)? {
        guard lines[start].trimmingCharacters(in: .whitespaces).hasPrefix(">") else { return nil }

        var content: [String] = []
        var index = start
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            var stripped = trimmed.dropFirst()
            if stripped.first == " " { stripped = stripped.dropFirst() }
            content.append(String(stripped))
            index += 1
        }
        return (.quote(content), index)
    }

    // MARK: - Lists

    private enum ListLineKind {
        case bullet(indent: Int, text: String)
        case task(indent: Int, isDone: Bool, text: String)
        case ordered(indent: Int, text: String)
    }

    /// Reads one line as a list item marker, if it looks like one.
    ///
    /// `indent` comes from leading whitespace alone (tabs count as two
    /// spaces, halved and clamped to 0...3) rather than from tracking marker
    /// nesting -- this parser produces a flat list of items per block, not a
    /// nested tree, which is all `MarkdownPreview` needs to offset rows.
    private static func classifyListLine(_ line: String) -> ListLineKind? {
        var chars = Substring(line)
        var indentWidth = 0
        while let first = chars.first, first == " " || first == "\t" {
            indentWidth += (first == "\t") ? 2 : 1
            chars.removeFirst()
        }
        let indent = min(indentWidth / 2, 3)

        if let marker = chars.first, marker == "-" || marker == "*" || marker == "+" {
            let afterMarker = chars.dropFirst()
            guard afterMarker.first == " " else { return nil }
            var rest = afterMarker.dropFirst()
            while rest.first == " " { rest = rest.dropFirst() }

            if rest.first == "[" {
                let afterBracket = rest.dropFirst()
                if let status = afterBracket.first {
                    let afterStatus = afterBracket.dropFirst()
                    if afterStatus.first == "]" {
                        let isDone = status == "x" || status == "X"
                        let isUnchecked = status == " "
                        if isDone || isUnchecked {
                            var text = afterStatus.dropFirst()
                            while text.first == " " { text = text.dropFirst() }
                            return .task(indent: indent, isDone: isDone, text: String(text))
                        }
                    }
                }
            }

            return .bullet(indent: indent, text: String(rest))
        }

        let digits = chars.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let afterDigits = chars.dropFirst(digits.count)
        guard let delimiter = afterDigits.first, delimiter == "." || delimiter == ")" else { return nil }
        let afterDelimiter = afterDigits.dropFirst()
        guard afterDelimiter.first == " " else { return nil }
        var rest = afterDelimiter.dropFirst()
        while rest.first == " " { rest = rest.dropFirst() }
        return .ordered(indent: indent, text: String(rest))
    }

    /// Groups a run of list-item lines into one block.
    ///
    /// Bullet and task markers share the same punctuation (`-`, `*`, `+`),
    /// so a run mixing plain bullets with `- [ ]` / `- [x]` items is scanned
    /// as a single run and only classified once it ends: any task item in
    /// the run promotes the whole block to a task list, with the plain
    /// bullets in that run treated as not done. A numbered marker never
    /// joins a bullet run, and vice versa.
    private static func parseList(_ lines: [String], from start: Int) -> (MarkdownBlock, Int)? {
        guard let firstKind = classifyListLine(lines[start]) else { return nil }

        if case .ordered = firstKind {
            var items: [MarkdownListItem] = []
            var index = start
            while index < lines.count, case let .ordered(indent, text)? = classifyListLine(lines[index]) {
                items.append(MarkdownListItem(text: text, indent: indent))
                index += 1
            }
            return (.numberedList(items), index)
        }

        var items: [MarkdownTaskItem] = []
        var containsTask = false
        var index = start

        func finish() -> (MarkdownBlock, Int) {
            if containsTask {
                return (.taskList(items), index)
            }
            let bulletItems = items.map { MarkdownListItem(text: $0.text, indent: $0.indent) }
            return (.bulletList(bulletItems), index)
        }

        while index < lines.count {
            switch classifyListLine(lines[index]) {
            case let .bullet(indent, text):
                items.append(MarkdownTaskItem(text: text, isDone: false, indent: indent))
            case let .task(indent, isDone, text):
                containsTask = true
                items.append(MarkdownTaskItem(text: text, isDone: isDone, indent: indent))
            case .ordered, .none:
                return finish()
            }
            index += 1
        }
        return finish()
    }

    // MARK: - Tables

    /// A GitHub-style table: a `|`-separated header row, a `|---|---|`
    /// delimiter row, then body rows padded or truncated to the header's
    /// column count.
    private static func parseTable(_ lines: [String], from start: Int) -> (MarkdownBlock, Int)? {
        guard lines[start].contains("|") else { return nil }
        guard start + 1 < lines.count, isTableDelimiterRow(lines[start + 1]) else { return nil }

        let header = splitTableRow(lines[start])
        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count {
            let candidate = lines[index]
            if candidate.trimmingCharacters(in: .whitespaces).isEmpty { break }
            guard candidate.contains("|") else { break }
            rows.append(padded(splitTableRow(candidate), to: header.count))
            index += 1
        }
        return (.table(header: header, rows: rows), index)
    }

    private static func isTableDelimiterRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return false }

        let cells = trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !cells.isEmpty else { return false }

        return cells.allSatisfy { cell in
            var core = Substring(cell)
            if core.first == ":" { core = core.dropFirst() }
            if core.last == ":" { core = core.dropLast() }
            return !core.isEmpty && core.allSatisfy { $0 == "-" }
        }
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    private static func padded(_ cells: [String], to count: Int) -> [String] {
        if cells.count == count { return cells }
        if cells.count > count { return Array(cells.prefix(count)) }
        return cells + Array(repeating: "", count: count - cells.count)
    }

    // MARK: - Paragraphs

    /// Anything that is not another block kind: consecutive plain lines are
    /// joined with "\n" into one paragraph, verbatim, so inline formatting
    /// survives for `MarkdownPreview` to interpret.
    private static func parseParagraph(_ lines: [String], from start: Int) -> (MarkdownBlock, Int) {
        var paragraphLines: [String] = []
        var index = start
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
            if startsNewBlock(lines, at: index) { break }
            paragraphLines.append(line)
            index += 1
        }
        return (.paragraph(paragraphLines.joined(separator: "\n")), index)
    }

    /// Whether `lines[index]` is the first line of some other block kind,
    /// used only to stop a paragraph run before it swallows the next block.
    private static func startsNewBlock(_ lines: [String], at index: Int) -> Bool {
        let line = lines[index]
        if isFenceStart(line) { return true }
        if parseHeading(line) != nil { return true }
        if isDivider(line) { return true }
        if line.contains("|"), index + 1 < lines.count, isTableDelimiterRow(lines[index + 1]) { return true }
        if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") { return true }
        if classifyListLine(line) != nil { return true }
        return false
    }
}
