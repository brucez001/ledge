import Foundation

/// The formatting actions the notes toolbar can apply to the editor text.
///
/// Every case is a pure text transform: applying one never touches anything
/// the user did not select, and never depends on `NSTextView` directly, so
/// the toolbar, tests, and any future editor surface can share one
/// implementation.
enum MarkdownCommand: Equatable {
    case bold
    case italic
    case strikethrough
    case inlineCode
    case heading(Int)
    case bulletList
    case numberedList
    case taskList
    case quote
    case codeBlock
    case link
    case divider
    case table
    case clearFormatting
}

/// A full replacement for the editor's text plus the selection to install
/// afterwards.
///
/// `NSTextView` only ever exposes and accepts UTF-16 offsets (via
/// `selectedRange`), so `selection` is expressed the same way here rather
/// than as a `String.Index` or a `Character` count, which would silently
/// misplace the caret whenever the note contains an emoji or accented
/// character.
struct MarkdownEdit: Equatable {
    let text: String
    let selection: NSRange
}

/// Pure text transforms behind the notes Markdown formatting toolbar.
///
/// Nothing here touches AppKit or `@MainActor` state: every function takes
/// the editor's current text and selection and returns the replacement text
/// and selection, so the toolbar can call these directly from any context.
enum MarkdownEditing {
    static func apply(_ command: MarkdownCommand, to text: String, selection: NSRange) -> MarkdownEdit {
        let ns = text as NSString
        let range = clampedSelection(selection, in: ns)
        switch command {
        case .bold:
            return applyInline(marker: "**", to: ns, selection: range)
        case .italic:
            return applyInline(marker: "*", to: ns, selection: range)
        case .strikethrough:
            return applyInline(marker: "~~", to: ns, selection: range)
        case .inlineCode:
            return applyInline(marker: "`", to: ns, selection: range)
        case .heading(let level):
            let clampedLevel = min(max(level, 1), 6)
            return applyLinePrefix(.heading(clampedLevel), to: ns, selection: range)
        case .bulletList:
            return applyLinePrefix(.bullet, to: ns, selection: range)
        case .numberedList:
            return applyLinePrefix(.numbered, to: ns, selection: range)
        case .taskList:
            return applyLinePrefix(.task, to: ns, selection: range)
        case .quote:
            return applyLinePrefix(.quote, to: ns, selection: range)
        case .codeBlock:
            return applyCodeBlock(to: ns, selection: range)
        case .link:
            return applyLink(to: ns, selection: range)
        case .divider:
            return applyDivider(to: ns, selection: range)
        case .table:
            return applyTable(to: ns, selection: range)
        case .clearFormatting:
            return applyClearFormatting(to: ns, selection: range)
        }
    }

    // MARK: - Selection safety

    /// Clamps an incoming selection to the bounds of `ns`.
    ///
    /// `NSTextView.selectedRange` should always be in range, but a caller on
    /// a stale copy of the text (for example after an async edit lands)
    /// could hand us an out-of-bounds range. Clamping keeps every transform
    /// total instead of trapping on an invalid `NSRange`.
    private static func clampedSelection(_ range: NSRange, in ns: NSString) -> NSRange {
        let length = ns.length
        let location = max(0, min(range.location, length))
        let remaining = length - location
        let len = max(0, min(range.length, remaining))
        return NSRange(location: location, length: len)
    }

    // MARK: - Inline markers (bold, italic, strikethrough, inline code)

    private static func applyInline(marker: String, to ns: NSString, selection: NSRange) -> MarkdownEdit {
        let markerLength = marker.utf16.count

        guard selection.length > 0 else {
            if let word = wordRange(in: ns, around: selection.location) {
                return applyInline(marker: marker, to: ns, selection: word)
            }
            let insertion = marker + marker
            let newText = ns.replacingCharacters(in: selection, with: insertion)
            return MarkdownEdit(text: newText, selection: NSRange(location: selection.location + markerLength, length: 0))
        }

        let selected = ns.substring(with: selection)

        // The selection itself is the wrapped text, e.g. selecting "**x**"
        // whole and pressing bold again should unwrap it.
        if let inner = exactlyWrapped(selected, marker: marker) {
            let newText = ns.replacingCharacters(in: selection, with: inner)
            return MarkdownEdit(text: newText, selection: NSRange(location: selection.location, length: inner.utf16.count))
        }

        // The selection excludes the markers but they sit immediately
        // outside it, e.g. selecting just "x" inside "**x**".
        if let fullRange = rangeWithOutsideMarkers(ns, selection: selection, marker: marker) {
            let newText = ns.replacingCharacters(in: fullRange, with: selected)
            return MarkdownEdit(text: newText, selection: NSRange(location: fullRange.location, length: selection.length))
        }

        let wrapped = marker + selected + marker
        let newText = ns.replacingCharacters(in: selection, with: wrapped)
        return MarkdownEdit(
            text: newText,
            selection: NSRange(location: selection.location + markerLength, length: selected.utf16.count)
        )
    }

    /// Returns the inner text when `selected` is wrapped end-to-end in
    /// `marker`, or `nil` when it is not (including when it is only wrapped
    /// in a *longer* run of the same character, e.g. `*` inside `***x***`,
    /// which is ambiguous and left untouched rather than half-unwrapped).
    private static func exactlyWrapped(_ selected: String, marker: String) -> String? {
        let ns = selected as NSString
        let markerLength = marker.utf16.count
        guard ns.length >= markerLength * 2,
              ns.substring(to: markerLength) == marker,
              ns.substring(from: ns.length - markerLength) == marker
        else { return nil }
        let inner = ns.substring(with: NSRange(location: markerLength, length: ns.length - markerLength * 2))
        guard !inner.hasPrefix(marker), !inner.hasSuffix(marker) else { return nil }
        return inner
    }

    /// Returns the range covering `marker` + `selection` + `marker` when
    /// those markers sit immediately outside the selection, guarding against
    /// matching part of a longer run of the same character.
    private static func rangeWithOutsideMarkers(_ ns: NSString, selection: NSRange, marker: String) -> NSRange? {
        let markerLength = marker.utf16.count
        let beforeLocation = selection.location - markerLength
        let afterLocation = selection.location + selection.length
        guard beforeLocation >= 0, afterLocation + markerLength <= ns.length else { return nil }

        let before = ns.substring(with: NSRange(location: beforeLocation, length: markerLength))
        let after = ns.substring(with: NSRange(location: afterLocation, length: markerLength))
        guard before == marker, after == marker else { return nil }

        if beforeLocation - 1 >= 0, let firstChar = marker.first {
            let further = ns.substring(with: NSRange(location: beforeLocation - 1, length: 1))
            if further == String(firstChar) { return nil }
        }
        if afterLocation + markerLength < ns.length, let lastChar = marker.last {
            let further = ns.substring(with: NSRange(location: afterLocation + markerLength, length: 1))
            if further == String(lastChar) { return nil }
        }

        return NSRange(location: beforeLocation, length: markerLength * 2 + selection.length)
    }

    /// Finds the contiguous word run touching `location`, so a caret resting
    /// anywhere inside or against a word wraps the whole word rather than
    /// inserting an empty marker pair inside it.
    private static func wordRange(in ns: NSString, around location: Int) -> NSRange? {
        func isWordCharacter(_ index: Int) -> Bool {
            guard index >= 0, index < ns.length else { return false }
            guard let scalar = Unicode.Scalar(ns.character(at: index)) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }

        guard isWordCharacter(location) || isWordCharacter(location - 1) else { return nil }

        var start = location
        while isWordCharacter(start - 1) { start -= 1 }
        var end = location
        while isWordCharacter(end) { end += 1 }
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    // MARK: - Line markers (headings, lists, quote)

    /// A parsed leading marker on a single line, used both to detect whether
    /// a line already carries a given marker and to strip whatever marker it
    /// currently has before applying a different one, so markers never stack.
    private enum LeadingMarker: Equatable {
        case heading(Int)
        case bullet
        case numbered(Int)
        case task
        case quote
    }

    private struct ParsedLine {
        let indentation: String
        let marker: LeadingMarker?
        let content: String
    }

    /// The line-prefix commands, keyed the same way regardless of whether
    /// the marker is a fixed literal (bullet, task, quote) or computed per
    /// line (heading level, list numbering).
    private enum LineCommandKind: Equatable {
        case heading(Int)
        case bullet
        case numbered
        case task
        case quote
    }

    private static func applyLinePrefix(_ kind: LineCommandKind, to ns: NSString, selection: NSRange) -> MarkdownEdit {
        let workRange = ns.paragraphRange(for: selection)
        let (lines, trailingNewline) = splitLines(ns.substring(with: workRange))
        let parsedLines = lines.map(parseLine)

        let allAlreadyMarked = parsedLines.allSatisfy { line in
            switch (kind, line.marker) {
            case (.bullet, .bullet?): return true
            case (.task, .task?): return true
            case (.quote, .quote?): return true
            case (.numbered, .numbered?): return true
            case (.heading(let wanted), .heading(let existing)?): return wanted == existing
            default: return false
            }
        }

        var newLines: [String] = []
        if allAlreadyMarked {
            // Every affected line already carries this exact marker: toggle
            // it off rather than stacking a second copy.
            newLines = parsedLines.map { $0.indentation + $0.content }
        } else {
            var ordinal = 1
            for line in parsedLines {
                switch kind {
                case .heading(let level):
                    newLines.append(line.indentation + String(repeating: "#", count: level) + " " + line.content)
                case .bullet:
                    newLines.append(line.indentation + "- " + line.content)
                case .task:
                    newLines.append(line.indentation + "- [ ] " + line.content)
                case .quote:
                    newLines.append(line.indentation + "> " + line.content)
                case .numbered:
                    newLines.append(line.indentation + "\(ordinal). " + line.content)
                    ordinal += 1
                }
            }
        }

        let newContent = joinLines(newLines, trailingNewline: trailingNewline)
        let newText = ns.replacingCharacters(in: workRange, with: newContent)
        return MarkdownEdit(text: newText, selection: NSRange(location: workRange.location, length: newContent.utf16.count))
    }

    /// Splits leading indentation and a recognised marker off a single line,
    /// leaving `content` ready to receive a different marker.
    private static func parseLine(_ line: String) -> ParsedLine {
        let ns = line as NSString
        var indentEnd = 0
        while indentEnd < ns.length {
            let character = ns.character(at: indentEnd)
            guard character == 0x20 || character == 0x09 else { break }
            indentEnd += 1
        }
        let indentation = ns.substring(to: indentEnd)
        let rest = ns.substring(from: indentEnd)

        if let (level, remainder) = matchHeading(rest) {
            return ParsedLine(indentation: indentation, marker: .heading(level), content: remainder)
        }
        if let remainder = matchLiteral(rest, marker: "- [ ] ") ?? matchLiteral(rest, marker: "- [x] ") ?? matchLiteral(rest, marker: "- [X] ") {
            return ParsedLine(indentation: indentation, marker: .task, content: remainder)
        }
        if let remainder = matchLiteral(rest, marker: "- ") {
            return ParsedLine(indentation: indentation, marker: .bullet, content: remainder)
        }
        if let (number, remainder) = matchNumbered(rest) {
            return ParsedLine(indentation: indentation, marker: .numbered(number), content: remainder)
        }
        if let remainder = matchLiteral(rest, marker: "> ") {
            return ParsedLine(indentation: indentation, marker: .quote, content: remainder)
        }
        return ParsedLine(indentation: indentation, marker: nil, content: rest)
    }

    private static func matchHeading(_ text: String) -> (level: Int, remainder: String)? {
        let ns = text as NSString
        var index = 0
        while index < ns.length, ns.character(at: index) == 0x23 /* # */ { index += 1 }
        guard (1...6).contains(index), index < ns.length, ns.character(at: index) == 0x20 else { return nil }
        return (index, ns.substring(from: index + 1))
    }

    private static func matchLiteral(_ text: String, marker: String) -> String? {
        guard text.hasPrefix(marker) else { return nil }
        return String(text.dropFirst(marker.count))
    }

    private static func matchNumbered(_ text: String) -> (number: Int, remainder: String)? {
        var rest = Substring(text)
        var digits = ""
        while let first = rest.first, first.isNumber {
            digits.append(first)
            rest = rest.dropFirst()
        }
        guard !digits.isEmpty, let number = Int(digits),
              rest.first == ".", rest.dropFirst().first == " "
        else { return nil }
        return (number, String(rest.dropFirst(2)))
    }

    // MARK: - Code block

    private static func applyCodeBlock(to ns: NSString, selection: NSRange) -> MarkdownEdit {
        let workRange = ns.paragraphRange(for: selection)
        let (lines, trailingNewline) = splitLines(ns.substring(with: workRange))

        if lines.count >= 2, lines.first == "```", lines.last == "```" {
            let inner = Array(lines.dropFirst().dropLast())
            let newContent = joinLines(inner, trailingNewline: trailingNewline)
            let newText = ns.replacingCharacters(in: workRange, with: newContent)
            return MarkdownEdit(text: newText, selection: NSRange(location: workRange.location, length: newContent.utf16.count))
        }

        // A caret on its own blank line gets an empty fence with the caret
        // left ready to type on the blank line inside it.
        if selection.length == 0, lines.count == 1, lines[0].isEmpty {
            let newContent = "```\n\n```"
            let newText = ns.replacingCharacters(in: workRange, with: newContent)
            let caretLocation = workRange.location + "```\n".utf16.count
            return MarkdownEdit(text: newText, selection: NSRange(location: caretLocation, length: 0))
        }

        let fenced = ["```"] + lines + ["```"]
        let newContent = joinLines(fenced, trailingNewline: trailingNewline)
        let newText = ns.replacingCharacters(in: workRange, with: newContent)
        return MarkdownEdit(text: newText, selection: NSRange(location: workRange.location, length: newContent.utf16.count))
    }

    // MARK: - Link

    private static func applyLink(to ns: NSString, selection: NSRange) -> MarkdownEdit {
        guard selection.length > 0 else {
            let newText = ns.replacingCharacters(in: selection, with: "[](url)")
            let urlStart = selection.location + "[](".utf16.count
            return MarkdownEdit(text: newText, selection: NSRange(location: urlStart, length: "url".utf16.count))
        }

        let selected = ns.substring(with: selection)
        if looksLikeURL(selected) {
            let replacement = "[text](\(selected))"
            let newText = ns.replacingCharacters(in: selection, with: replacement)
            let textStart = selection.location + "[".utf16.count
            return MarkdownEdit(text: newText, selection: NSRange(location: textStart, length: "text".utf16.count))
        }

        let replacement = "[\(selected)](url)"
        let newText = ns.replacingCharacters(in: selection, with: replacement)
        let urlStart = selection.location + "[".utf16.count + selected.utf16.count + "](".utf16.count
        return MarkdownEdit(text: newText, selection: NSRange(location: urlStart, length: "url".utf16.count))
    }

    /// A loose check for "this selection is a URL, not link text": either it
    /// has a `scheme:` prefix or it starts with the common `www.` shorthand.
    private static func looksLikeURL(_ value: String) -> Bool {
        guard !value.isEmpty, !value.contains(where: \.isWhitespace) else { return false }
        if value.lowercased().hasPrefix("www.") { return true }
        guard let colonIndex = value.firstIndex(of: ":"), colonIndex != value.startIndex else { return false }
        let scheme = value[value.startIndex..<colonIndex]
        guard let first = scheme.first, first.isLetter else { return false }
        return scheme.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
    }

    // MARK: - Divider and table

    private static func applyDivider(to ns: NSString, selection: NSRange) -> MarkdownEdit {
        let endpoint = NSRange(location: selection.location + selection.length, length: 0)
        let lineRange = ns.lineRange(for: endpoint)
        let lineEnd = lineRange.location + lineRange.length
        let lineHasTerminator = ns.substring(with: lineRange).hasSuffix("\n")

        // When the current line has no terminator it is the last line in the
        // document, so a leading newline is needed before the divider can
        // sit on its own line; a trailing newline is always added so the
        // caret has a line to land on afterwards.
        let insertion = lineHasTerminator ? "---\n" : "\n---\n"
        let newText = ns.replacingCharacters(in: NSRange(location: lineEnd, length: 0), with: insertion)
        let caretLocation = lineEnd + insertion.utf16.count
        return MarkdownEdit(text: newText, selection: NSRange(location: caretLocation, length: 0))
    }

    private static func applyTable(to ns: NSString, selection: NSRange) -> MarkdownEdit {
        let endpoint = NSRange(location: selection.location + selection.length, length: 0)
        let lineRange = ns.lineRange(for: endpoint)
        let lineEnd = lineRange.location + lineRange.length
        let lineHasTerminator = ns.substring(with: lineRange).hasSuffix("\n")

        let table = "| Column | Column |\n| --- | --- |\n|  |  |"
        let insertion = lineHasTerminator ? table + "\n" : "\n" + table
        let newText = ns.replacingCharacters(in: NSRange(location: lineEnd, length: 0), with: insertion)

        let headerPrefix = lineHasTerminator ? "| " : "\n| "
        let selectionStart = lineEnd + headerPrefix.utf16.count
        return MarkdownEdit(text: newText, selection: NSRange(location: selectionStart, length: "Column".utf16.count))
    }

    // MARK: - Clear formatting

    private static func applyClearFormatting(to ns: NSString, selection: NSRange) -> MarkdownEdit {
        let workRange = ns.paragraphRange(for: selection)
        let (lines, trailingNewline) = splitLines(ns.substring(with: workRange))
        let cleanedLines = lines.map { line -> String in
            let parsed = parseLine(line)
            return parsed.indentation + stripInlineMarkers(parsed.content)
        }
        let newContent = joinLines(cleanedLines, trailingNewline: trailingNewline)
        let newText = ns.replacingCharacters(in: workRange, with: newContent)
        return MarkdownEdit(text: newText, selection: NSRange(location: workRange.location, length: newContent.utf16.count))
    }

    /// Removes literal bold/italic/strikethrough/code markers and collapses
    /// `[text](url)` down to `text`, leaving plain reading text behind.
    private static func stripInlineMarkers(_ text: String) -> String {
        var result = stripLinks(text)
        for marker in ["~~", "**", "__", "*", "_", "`"] {
            result = result.replacingOccurrences(of: marker, with: "")
        }
        return result
    }

    /// Replaces `[text](url)` sequences with just `text`. Written as a plain
    /// character scan rather than `NSRegularExpression` so a malformed or
    /// adversarial pattern can never be a source of unexpected behaviour.
    private static func stripLinks(_ text: String) -> String {
        let ns = text as NSString
        var result = ""
        var index = 0
        while index < ns.length {
            if ns.character(at: index) == 0x5B /* [ */,
               let closeBracket = firstIndex(of: 0x5D /* ] */, in: ns, from: index + 1),
               closeBracket + 1 < ns.length, ns.character(at: closeBracket + 1) == 0x28 /* ( */,
               let closeParen = firstIndex(of: 0x29 /* ) */, in: ns, from: closeBracket + 2) {
                result += ns.substring(with: NSRange(location: index + 1, length: closeBracket - index - 1))
                index = closeParen + 1
                continue
            }
            result += ns.substring(with: NSRange(location: index, length: 1))
            index += 1
        }
        return result
    }

    private static func firstIndex(of value: unichar, in ns: NSString, from start: Int) -> Int? {
        var index = start
        while index < ns.length {
            if ns.character(at: index) == value { return index }
            index += 1
        }
        return nil
    }

    // MARK: - Line splitting

    /// Splits paragraph content into lines, remembering whether it ended
    /// with a trailing newline so `joinLines` can restore it exactly.
    private static func splitLines(_ content: String) -> (lines: [String], trailingNewline: Bool) {
        guard !content.isEmpty else { return ([""], false) }
        let trailingNewline = content.hasSuffix("\n")
        var lines = content.components(separatedBy: "\n")
        if trailingNewline { lines.removeLast() }
        return (lines, trailingNewline)
    }

    private static func joinLines(_ lines: [String], trailingNewline: Bool) -> String {
        let joined = lines.joined(separator: "\n")
        return trailingNewline ? joined + "\n" : joined
    }
}
