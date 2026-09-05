import Foundation

/// One source line, classified for live styling.
///
/// A live note keeps the raw Markdown source in the text storage and styles
/// it in place -- there is no separate rendered document, so the editor
/// needs to know, for every line, what kind of line it is and exactly which
/// UTF-16 range is the "syntax" part to de-emphasise versus the range that
/// is the line's own extent. Both are reported as `NSRange`s into the
/// original string so an `NSTextStorage` can apply attributes directly,
/// without any intermediate coordinate translation.
struct MarkdownLiveLine: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case paragraph
        case heading(level: Int)
        case bullet(depth: Int)
        case numbered(depth: Int)
        case task(depth: Int, isDone: Bool)
        case quote
        case code
        case divider
    }

    var kind: Kind
    /// The line's own range, excluding its trailing newline. If the line
    /// ends in `\r\n`, the `\r` is excluded too (see the note on
    /// `MarkdownLiveStyle.lines(in:)`).
    var range: NSRange
    /// The leading syntax marker to de-emphasise or hide: `"## "`, `"- "`,
    /// `"1. "`, `"- [x] "`, `"> "`. Zero length when the line has no marker
    /// (a paragraph, a fenced code line, or a divider, whose whole line is
    /// the marker).
    var marker: NSRange
    /// For bullets and tasks, the single marker character (`"-"`, `"*"`, or
    /// `"+"`) that the editor draws as a bullet dot. `nil` for every other
    /// kind, including numbered lists, which have no single character to
    /// substitute.
    var bulletCharacter: NSRange?
    /// Leading indentation in columns (a space is one column, a tab is
    /// four), used for the hanging indent of wrapped list text. Reported
    /// for every line, not just list items, so a wrapped plain paragraph
    /// under an indented list item can match its indent.
    var indentColumns: Int
}

/// One inline run inside a non-code line.
///
/// `MarkdownLiveStyle.inlineSpans(in:)` never looks inside a line that
/// `lines(in:)` classified as `.code`: a fenced code line is shown verbatim,
/// so its `*`, `` ` ``, and `[` characters are not syntax to interpret.
struct MarkdownLiveInline: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case strong
        case emphasis
        case strikethrough
        case code
        case link
        case linkURL
        case syntax
    }

    var kind: Kind
    var range: NSRange
}

/// Analyses Markdown source for live, in-place styling.
///
/// This is the pure counterpart to `MarkdownDocument`: where that type
/// parses source into a block tree for the read-only preview,
/// `MarkdownLiveStyle` classifies the same small Markdown subset line by
/// line and span by span, for an editor that never leaves the raw source.
/// It shares `MarkdownDocument`'s grammar decisions (heading, divider, list,
/// and quote rules) deliberately, so a note looks the same whether it is
/// being edited live or rendered in the preview.
///
/// Pure and `nonisolated`, with no attributes, colours, or fonts: it hands
/// back ranges only, so `NoteLiveTextStorage` (or whatever AppKit type
/// consumes it) owns every presentation decision, and this type stays easy
/// to unit test off the main actor.
enum MarkdownLiveStyle {
    /// Classifies every line of `markdown`, in order.
    ///
    /// One entry is returned per source line, including empty lines, so a
    /// caller can style a whole document by walking this array alongside
    /// the text storage's paragraph ranges. Line endings are recognised as
    /// `"\n"`, `"\r\n"`, or `"\r"`; a trailing line ending produces one more
    /// (empty) line after it, matching how a text view lets the cursor sit
    /// on a blank final line.
    nonisolated static func lines(in markdown: String) -> [MarkdownLiveLine] {
        let ns = markdown as NSString
        var result: [MarkdownLiveLine] = []
        var fence: FenceState?

        for range in rawLineRanges(in: ns) {
            let lineText = substring(of: markdown, utf16Range: range)
            let indentColumns = indentColumns(of: lineText)

            if let open = fence {
                if isClosingFence(lineText, matching: open) {
                    fence = nil
                }
                result.append(codeLine(range: range, indentColumns: indentColumns))
                continue
            }

            if let opened = fenceMarker(lineText) {
                fence = opened
                result.append(codeLine(range: range, indentColumns: indentColumns))
                continue
            }

            result.append(classify(lineText, lineRange: range, indentColumns: indentColumns, in: markdown))
        }

        return result
    }

    /// Finds every styleable inline run across `markdown`.
    ///
    /// Delegates line classification to `lines(in:)` so the two functions
    /// can never disagree about which lines are fenced code -- inline spans
    /// are only ever produced for the lines `lines(in:)` did not mark as
    /// `.code`.
    nonisolated static func inlineSpans(in markdown: String) -> [MarkdownLiveInline] {
        var spans: [MarkdownLiveInline] = []
        for line in lines(in: markdown) {
            if case .code = line.kind { continue }
            guard line.range.length > 0 else { continue }
            let lineText = substring(of: markdown, utf16Range: line.range)
            spans.append(contentsOf: inlineSpans(in: lineText, of: markdown))
        }
        return spans
    }

    // MARK: - Line splitting

    /// Splits `ns` into line-content ranges, excluding line-ending
    /// characters, without touching Swift `String` at all.
    ///
    /// Working directly on the `NSString` (i.e. in UTF-16 code units) keeps
    /// this exact for astral characters: a naive `Character`-based split
    /// followed by re-deriving UTF-16 offsets can drift when a line
    /// contains surrogate pairs, whereas this never leaves UTF-16 space.
    private static func rawLineRanges(in ns: NSString) -> [NSRange] {
        let length = ns.length
        var ranges: [NSRange] = []
        var index = 0

        while true {
            var lineEnd = index
            while lineEnd < length {
                let unit = ns.character(at: lineEnd)
                if unit == 0x0A || unit == 0x0D { break }
                lineEnd += 1
            }
            ranges.append(NSRange(location: index, length: lineEnd - index))

            guard lineEnd < length else { break }

            var terminatorLength = 1
            if ns.character(at: lineEnd) == 0x0D,
               lineEnd + 1 < length,
               ns.character(at: lineEnd + 1) == 0x0A {
                terminatorLength = 2
            }
            index = lineEnd + terminatorLength
        }

        return ranges
    }

    /// Slices `string` at a UTF-16 range, returning a `Substring` that
    /// still shares `string`'s indices -- every helper below can therefore
    /// hand a `Range<String.Index>` straight to `NSRange(_:in:)` without
    /// re-walking the string.
    private static func substring(of string: String, utf16Range: NSRange) -> Substring {
        let start = String.Index(utf16Offset: utf16Range.location, in: string)
        let end = String.Index(utf16Offset: utf16Range.location + utf16Range.length, in: string)
        return string[start..<end]
    }

    private static func codeLine(range: NSRange, indentColumns: Int) -> MarkdownLiveLine {
        MarkdownLiveLine(
            kind: .code,
            range: range,
            marker: NSRange(location: range.location, length: 0),
            bulletCharacter: nil,
            indentColumns: indentColumns
        )
    }

    private static func indentColumns(of lineText: Substring) -> Int {
        var columns = 0
        for character in lineText {
            if character == " " {
                columns += 1
            } else if character == "\t" {
                columns += 4
            } else {
                break
            }
        }
        return columns
    }

    // MARK: - Fenced code

    /// The fence character (`` ` `` or `~`) and run length of an open fence,
    /// carried across lines until a matching close is found.
    private struct FenceState {
        let character: Character
        let length: Int
    }

    /// Recognises a ``` / ~~~ fence-opening line, mirroring
    /// `MarkdownDocument.parseCodeFence`'s rule: three or more of the same
    /// character, ignoring surrounding whitespace and any info string.
    private static func fenceMarker(_ lineText: Substring) -> FenceState? {
        let trimmed = lineText.trimmingCharacters(in: .whitespaces)
        guard let fenceChar = trimmed.first, fenceChar == "`" || fenceChar == "~" else { return nil }
        let fenceRun = trimmed.prefix { $0 == fenceChar }
        guard fenceRun.count >= 3 else { return nil }
        return FenceState(character: fenceChar, length: fenceRun.count)
    }

    /// A closing fence is a line that, once trimmed, is nothing but a run of
    /// the opening character at least as long as the opening run.
    private static func isClosingFence(_ lineText: Substring, matching fence: FenceState) -> Bool {
        let trimmed = lineText.trimmingCharacters(in: .whitespaces)
        let closingRun = trimmed.prefix { $0 == fence.character }
        return closingRun.count >= fence.length && closingRun.count == trimmed.count
    }

    // MARK: - Per-line classification

    private static func classify(
        _ lineText: Substring,
        lineRange: NSRange,
        indentColumns: Int,
        in markdown: String
    ) -> MarkdownLiveLine {
        if let heading = headingMatch(lineText, in: markdown) {
            return MarkdownLiveLine(
                kind: .heading(level: heading.level),
                range: lineRange,
                marker: heading.marker,
                bulletCharacter: nil,
                indentColumns: indentColumns
            )
        }

        if isDivider(lineText) {
            return MarkdownLiveLine(
                kind: .divider,
                range: lineRange,
                marker: NSRange(location: lineRange.location, length: 0),
                bulletCharacter: nil,
                indentColumns: indentColumns
            )
        }

        if let quoteMarker = quoteMatch(lineText, in: markdown) {
            return MarkdownLiveLine(
                kind: .quote,
                range: lineRange,
                marker: quoteMarker,
                bulletCharacter: nil,
                indentColumns: indentColumns
            )
        }

        if let list = listMatch(lineText, in: markdown) {
            let depth = indentColumns / 2
            switch list {
            case let .bullet(marker, bulletCharacter):
                return MarkdownLiveLine(
                    kind: .bullet(depth: depth),
                    range: lineRange,
                    marker: marker,
                    bulletCharacter: bulletCharacter,
                    indentColumns: indentColumns
                )
            case let .task(marker, bulletCharacter, isDone):
                return MarkdownLiveLine(
                    kind: .task(depth: depth, isDone: isDone),
                    range: lineRange,
                    marker: marker,
                    bulletCharacter: bulletCharacter,
                    indentColumns: indentColumns
                )
            case let .numbered(marker):
                return MarkdownLiveLine(
                    kind: .numbered(depth: depth),
                    range: lineRange,
                    marker: marker,
                    bulletCharacter: nil,
                    indentColumns: indentColumns
                )
            }
        }

        return MarkdownLiveLine(
            kind: .paragraph,
            range: lineRange,
            marker: NSRange(location: lineRange.location, length: 0),
            bulletCharacter: nil,
            indentColumns: indentColumns
        )
    }

    // MARK: - Headings

    private struct HeadingMatch {
        let level: Int
        let marker: NSRange
    }

    /// Matches an ATX heading, mirroring `MarkdownDocument.parseHeading`:
    /// up to two leading spaces (a third would make it a fourth, which is
    /// not recognised), a run of `#`, then a space or end of line. The
    /// marker covers the hashes and exactly one following space -- any
    /// further spaces before the heading text are left as ordinary content.
    private static func headingMatch(_ lineText: Substring, in markdown: String) -> HeadingMatch? {
        var chars = lineText[lineText.startIndex...]
        var leadingSpaces = 0
        while leadingSpaces < 3, chars.first == " " {
            chars = chars.dropFirst()
            leadingSpaces += 1
        }

        let hashStart = chars.startIndex
        var hashEnd = hashStart
        while hashEnd < chars.endIndex, chars[hashEnd] == "#" {
            hashEnd = chars.index(after: hashEnd)
        }
        guard hashEnd > hashStart else { return nil }
        guard hashEnd == chars.endIndex || chars[hashEnd] == " " else { return nil }

        let level = min(chars.distance(from: hashStart, to: hashEnd), 6)
        var markerEnd = hashEnd
        if hashEnd < chars.endIndex, chars[hashEnd] == " " {
            markerEnd = chars.index(after: hashEnd)
        }

        return HeadingMatch(level: level, marker: NSRange(hashStart..<markerEnd, in: markdown))
    }

    // MARK: - Dividers

    /// A thematic break is three or more matching `-`, `*`, or `_`
    /// characters, spaces allowed between them -- identical to
    /// `MarkdownDocument.isDivider`, and checked before list matching so
    /// `"- - -"` is a divider rather than a bullet with odd content.
    private static func isDivider(_ lineText: Substring) -> Bool {
        let compact = lineText.trimmingCharacters(in: .whitespaces).filter { $0 != " " }
        guard compact.count >= 3, let marker = compact.first else { return false }
        guard marker == "-" || marker == "*" || marker == "_" else { return false }
        return compact.allSatisfy { $0 == marker }
    }

    // MARK: - Quotes

    /// `"> "` (or a bare `">"` at end of line), after any leading
    /// whitespace. Unlike `MarkdownDocument.parseQuote`, this does not
    /// collapse a run of quote lines into one block: each line is styled
    /// independently, which is all a live editor needs.
    private static func quoteMatch(_ lineText: Substring, in markdown: String) -> NSRange? {
        var chars = lineText[lineText.startIndex...]
        while let first = chars.first, first == " " || first == "\t" {
            chars = chars.dropFirst()
        }
        guard chars.first == ">" else { return nil }

        let markerStart = chars.startIndex
        let afterMarker = chars.index(after: markerStart)
        var markerEnd = afterMarker
        if afterMarker < chars.endIndex, chars[afterMarker] == " " {
            markerEnd = chars.index(after: afterMarker)
        }
        return NSRange(markerStart..<markerEnd, in: markdown)
    }

    // MARK: - Lists

    private enum ListMatch {
        case bullet(marker: NSRange, bulletCharacter: NSRange)
        case task(marker: NSRange, bulletCharacter: NSRange, isDone: Bool)
        case numbered(marker: NSRange)
    }

    /// Reads one line as a bullet, task, or numbered marker, mirroring
    /// `MarkdownDocument.classifyListLine`'s grammar.
    ///
    /// The load-bearing rule is the same as that parser's: `"-"` alone,
    /// with nothing after it, is not a marker at all (the guard on the
    /// character after the bullet requires an actual space), so a lone
    /// dash stays a plain paragraph right up until the moment a space is
    /// typed after it -- which is exactly the instant `"- "` should start
    /// rendering as a bullet.
    private static func listMatch(_ lineText: Substring, in markdown: String) -> ListMatch? {
        var content = lineText[lineText.startIndex...]
        while let first = content.first, first == " " || first == "\t" {
            content = content.dropFirst()
        }
        guard let first = content.first else { return nil }
        let contentStart = content.startIndex

        if first == "-" || first == "*" || first == "+" {
            let afterBulletChar = content.index(after: contentStart)
            let bulletCharacterRange = contentStart..<afterBulletChar
            guard afterBulletChar < content.endIndex, content[afterBulletChar] == " " else { return nil }

            var cursor = content.index(after: afterBulletChar)
            while cursor < content.endIndex, content[cursor] == " " {
                cursor = content.index(after: cursor)
            }

            if cursor < content.endIndex, content[cursor] == "[",
               let task = taskMatch(content, bracketOpen: cursor, contentStart: contentStart, in: markdown) {
                return .task(
                    marker: task.marker,
                    bulletCharacter: NSRange(bulletCharacterRange, in: markdown),
                    isDone: task.isDone
                )
            }

            let markerEnd = content.index(after: afterBulletChar)
            return .bullet(
                marker: NSRange(contentStart..<markerEnd, in: markdown),
                bulletCharacter: NSRange(bulletCharacterRange, in: markdown)
            )
        }

        guard first.isNumber else { return nil }
        var digitsEnd = contentStart
        while digitsEnd < content.endIndex, content[digitsEnd].isNumber {
            digitsEnd = content.index(after: digitsEnd)
        }
        guard digitsEnd < content.endIndex else { return nil }
        let delimiterChar = content[digitsEnd]
        guard delimiterChar == "." || delimiterChar == ")" else { return nil }
        let afterDelimiter = content.index(after: digitsEnd)
        guard afterDelimiter < content.endIndex, content[afterDelimiter] == " " else { return nil }
        let markerEnd = content.index(after: afterDelimiter)
        return .numbered(marker: NSRange(contentStart..<markerEnd, in: markdown))
    }

    private struct TaskMatch {
        let marker: NSRange
        let isDone: Bool
    }

    /// `"[ ] "`, `"[x] "`, or `"[X] "` starting at `bracketOpen`, the
    /// position of the line's `"["`. Takes precedence over a plain bullet
    /// whenever it matches, so `"- [x] done"` is always a task, never a
    /// bullet whose text happens to start with `"[x]"`.
    private static func taskMatch(
        _ content: Substring,
        bracketOpen: String.Index,
        contentStart: String.Index,
        in markdown: String
    ) -> TaskMatch? {
        let afterOpen = content.index(after: bracketOpen)
        guard afterOpen < content.endIndex else { return nil }
        let status = content[afterOpen]
        let afterStatus = content.index(after: afterOpen)
        guard afterStatus < content.endIndex, content[afterStatus] == "]" else { return nil }

        let isDone = status == "x" || status == "X"
        let isUnchecked = status == " "
        guard isDone || isUnchecked else { return nil }

        var markerEnd = content.index(after: afterStatus)
        if markerEnd < content.endIndex, content[markerEnd] == " " {
            markerEnd = content.index(after: markerEnd)
        }
        return TaskMatch(marker: NSRange(contentStart..<markerEnd, in: markdown), isDone: isDone)
    }

    // MARK: - Inline spans

    /// Scans one line for `**`/`__` strong, `*`/`_` emphasis, `~~`
    /// strikethrough, `` ` `` code, and `[label](url)` links.
    ///
    /// Matching is leftmost and non-overlapping: the cursor only ever moves
    /// forward, consuming a whole match (or, failing that, one character)
    /// before continuing, so an earlier match can never be revisited or
    /// overridden by a later one. Inline code is checked first so its
    /// contents are never re-examined for emphasis, and a delimiter with no
    /// matching close on the same line is left as plain text -- the cursor
    /// steps over it one character at a time, so a delimiter typed but not
    /// yet closed produces no span.
    private static func inlineSpans(in lineText: Substring, of markdown: String) -> [MarkdownLiveInline] {
        var spans: [MarkdownLiveInline] = []
        var cursor = lineText.startIndex
        let end = lineText.endIndex

        while cursor < end {
            let character = lineText[cursor]

            if character == "`" {
                let searchStart = lineText.index(after: cursor)
                if let close = lineText[searchStart...].firstIndex(of: "`") {
                    spans.append(MarkdownLiveInline(kind: .syntax, range: NSRange(cursor..<searchStart, in: markdown)))
                    spans.append(MarkdownLiveInline(kind: .code, range: NSRange(searchStart..<close, in: markdown)))
                    let closeEnd = lineText.index(after: close)
                    spans.append(MarkdownLiveInline(kind: .syntax, range: NSRange(close..<closeEnd, in: markdown)))
                    cursor = closeEnd
                    continue
                }
                cursor = lineText.index(after: cursor)
                continue
            }

            if let doubleEnd = lineText.index(cursor, offsetBy: 2, limitedBy: end) {
                let pair = lineText[cursor..<doubleEnd]
                if pair == "**" || pair == "__" {
                    if let close = findClosingRun(String(pair), in: lineText, from: doubleEnd, end: end),
                       close > doubleEnd {
                        let closeEnd = lineText.index(close, offsetBy: 2)
                        spans.append(MarkdownLiveInline(kind: .syntax, range: NSRange(cursor..<doubleEnd, in: markdown)))
                        spans.append(MarkdownLiveInline(kind: .strong, range: NSRange(doubleEnd..<close, in: markdown)))
                        spans.append(MarkdownLiveInline(kind: .syntax, range: NSRange(close..<closeEnd, in: markdown)))
                        cursor = closeEnd
                        continue
                    }
                } else if pair == "~~" {
                    if let close = findClosingRun("~~", in: lineText, from: doubleEnd, end: end), close > doubleEnd {
                        let closeEnd = lineText.index(close, offsetBy: 2)
                        spans.append(MarkdownLiveInline(kind: .syntax, range: NSRange(cursor..<doubleEnd, in: markdown)))
                        spans.append(MarkdownLiveInline(kind: .strikethrough, range: NSRange(doubleEnd..<close, in: markdown)))
                        spans.append(MarkdownLiveInline(kind: .syntax, range: NSRange(close..<closeEnd, in: markdown)))
                        cursor = closeEnd
                        continue
                    }
                }
            }

            if character == "*" || character == "_" {
                let afterCursor = lineText.index(after: cursor)
                if let close = lineText[afterCursor...].firstIndex(of: character), close > afterCursor {
                    let closeEnd = lineText.index(after: close)
                    spans.append(MarkdownLiveInline(kind: .syntax, range: NSRange(cursor..<afterCursor, in: markdown)))
                    spans.append(MarkdownLiveInline(kind: .emphasis, range: NSRange(afterCursor..<close, in: markdown)))
                    spans.append(MarkdownLiveInline(kind: .syntax, range: NSRange(close..<closeEnd, in: markdown)))
                    cursor = closeEnd
                    continue
                }
                cursor = afterCursor
                continue
            }

            if character == "[" {
                if let link = linkMatch(in: lineText, bracketOpen: cursor, end: end, of: markdown) {
                    spans.append(contentsOf: link.spans)
                    cursor = link.end
                    continue
                }
                cursor = lineText.index(after: cursor)
                continue
            }

            cursor = lineText.index(after: cursor)
        }

        return spans
    }

    /// Searches `lineText[from..<end]` for the next occurrence of `delimiter`
    /// (a two-character run), trying every position rather than jumping in
    /// twos, so an overlapping run such as `"***"` closing a `"**"` open is
    /// still found starting at its first character.
    private static func findClosingRun(
        _ delimiter: String,
        in lineText: Substring,
        from: String.Index,
        end: String.Index
    ) -> String.Index? {
        var index = from
        while let candidateEnd = lineText.index(index, offsetBy: 2, limitedBy: end) {
            if lineText[index..<candidateEnd] == delimiter {
                return index
            }
            index = lineText.index(after: index)
        }
        return nil
    }

    private struct LinkMatch {
        let spans: [MarkdownLiveInline]
        let end: String.Index
    }

    /// `"[label](url)"` starting at `bracketOpen`. Only the very next `"]"`
    /// and `"("`/`")"` are considered -- there is deliberately no support
    /// for a label containing its own brackets, matching the grammar's
    /// "no reference links, nothing clever" scope.
    private static func linkMatch(
        in lineText: Substring,
        bracketOpen: String.Index,
        end: String.Index,
        of markdown: String
    ) -> LinkMatch? {
        let labelStart = lineText.index(after: bracketOpen)
        guard let closeBracket = lineText[labelStart...].firstIndex(of: "]") else { return nil }
        let afterBracket = lineText.index(after: closeBracket)
        guard afterBracket < end, lineText[afterBracket] == "(" else { return nil }
        let urlStart = lineText.index(after: afterBracket)
        guard let closeParen = lineText[urlStart...].firstIndex(of: ")") else { return nil }

        let closeParenEnd = lineText.index(after: closeParen)
        let spans = [
            MarkdownLiveInline(kind: .syntax, range: NSRange(bracketOpen..<labelStart, in: markdown)),
            MarkdownLiveInline(kind: .link, range: NSRange(labelStart..<closeBracket, in: markdown)),
            MarkdownLiveInline(kind: .syntax, range: NSRange(closeBracket..<afterBracket, in: markdown)),
            MarkdownLiveInline(kind: .syntax, range: NSRange(afterBracket..<urlStart, in: markdown)),
            MarkdownLiveInline(kind: .linkURL, range: NSRange(urlStart..<closeParen, in: markdown)),
            MarkdownLiveInline(kind: .syntax, range: NSRange(closeParen..<closeParenEnd, in: markdown))
        ]
        return LinkMatch(spans: spans, end: closeParenEnd)
    }
}
