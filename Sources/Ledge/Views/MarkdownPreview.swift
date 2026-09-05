import SwiftUI

/// Read-only rendering of a note's Markdown body.
///
/// This lays out the blocks `MarkdownDocument.parse` produces as a plain
/// `VStack`: it owns no scrolling, padding, or background, so a note tab
/// (or, later, anything else that wants a Markdown preview) can drop it into
/// whatever container already provides those.
struct MarkdownPreview: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownDocument.parse(markdown).enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        // Applied once at the root: SwiftUI's text-selection environment
        // value propagates to every `Text` in the hierarchy below, so
        // individual block views don't need to repeat it.
        .textSelection(.enabled)
    }
}

/// Renders one parsed block using only `Theme` tokens, matching the rest of
/// the panel's chrome instead of hard-coded greys.
private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case let .heading(level, text):
            MarkdownHeading(level: level, text: text)

        case let .paragraph(text):
            Text(markdownInline(text))
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

        case let .bulletList(items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    MarkdownListRow(marker: "•", indent: item.indent, text: item.text)
                }
            }

        case let .numberedList(items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    MarkdownListRow(marker: "\(index + 1).", indent: item.indent, text: item.text)
                }
            }

        case let .taskList(items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    MarkdownTaskRow(item: item)
                }
            }

        case let .quote(lines):
            MarkdownQuote(lines: lines)

        case let .codeBlock(language, code):
            MarkdownCodeBlock(language: language, code: code)

        case .divider:
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)

        case let .table(header, rows):
            MarkdownTable(header: header, rows: rows)
        }
    }
}

/// A heading, sized so h1/h2 read as the panel's rounded display type and
/// smaller levels step down towards body text.
private struct MarkdownHeading: View {
    let level: Int
    let text: String

    private var font: Font {
        switch level {
        case 1: return .system(size: 22, weight: .semibold, design: .rounded)
        case 2: return .system(size: 19, weight: .semibold, design: .rounded)
        case 3: return .system(size: 17, weight: .semibold)
        case 4: return .system(size: 15, weight: .semibold)
        case 5: return .system(size: 14, weight: .semibold)
        default: return .system(size: 13, weight: .semibold)
        }
    }

    var body: some View {
        Text(markdownInline(text))
            .font(font)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            // A heading belongs to what follows it, so it earns a little
            // extra air above rather than sitting evenly between two
            // paragraphs.
            .padding(.top, level <= 2 ? 6 : 2)
    }
}

/// One row of a bullet or numbered list: a fixed-width marker column
/// followed by the item's inline-formatted text, offset by `indent`.
private struct MarkdownListRow: View {
    let marker: String
    let indent: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(marker)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(minWidth: 16, alignment: .trailing)
            Text(markdownInline(text))
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, CGFloat(indent) * 16)
    }
}

/// One task list row. This preview is read-only: the checkbox glyph reflects
/// `isDone` but is not an interactive control.
private struct MarkdownTaskRow: View {
    let item: MarkdownTaskItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                .font(.system(size: 13))
                .foregroundStyle(item.isDone ? Theme.inkSecondary : Theme.inkTertiary)
            Text(markdownInline(item.text))
                .font(.system(size: 14))
                .foregroundStyle(item.isDone ? Theme.inkTertiary : Theme.ink)
                .strikethrough(item.isDone)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, CGFloat(item.indent) * 16)
    }
}

/// A quote block: a hairline rule down the left edge and de-emphasised text,
/// matching how quotes read in the rest of the app's chrome.
private struct MarkdownQuote: View {
    let lines: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 3)
            Text(markdownInline(lines.joined(separator: "\n")))
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A fenced code block on a raised `Theme.card` surface. Code wraps rather
/// than clipping or scrolling, so it never fights the panel's own layout.
private struct MarkdownCodeBlock: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.inkTertiary)
            }
            Text(code)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.controlCornerRadius)
                .fill(Theme.card)
        )
    }
}

/// A GitHub-style table rendered as a simple grid: bold header row, hairline
/// separators between every row and column.
private struct MarkdownTable: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MarkdownTableRow(cells: header, isHeader: true)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Rectangle().fill(Theme.hairline).frame(height: 1)
                MarkdownTableRow(cells: row, isHeader: false)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.controlCornerRadius)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }
}

private struct MarkdownTableRow: View {
    let cells: [String]
    let isHeader: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                Text(markdownInline(cell))
                    .font(.system(size: 13, weight: isHeader ? .semibold : .regular))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                if index < cells.count - 1 {
                    // `maxHeight: .infinity` inside a `fixedSize`d row: a
                    // bare 1pt rectangle takes its own ideal height here and
                    // draws as a stub rather than a full column rule.
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Parses one span of inline Markdown (bold, italic, links, code spans) into
/// an `AttributedString`, falling back to the raw text if it fails to parse.
///
/// Foundation's Markdown parser has no `~~strikethrough~~` syntax, so this
/// first splits `raw` on `~~...~~` runs, parses each side normally, and
/// stamps the struck-through segments with `.strikethroughStyle` afterwards
/// -- rather than attempting to remap character ranges between the raw and
/// parsed text, which would be brittle once bold/code spans shift positions.
private func markdownInline(_ raw: String) -> AttributedString {
    var result = AttributedString()
    var remainder = Substring(raw)

    while let openRange = remainder.range(of: "~~") {
        let before = remainder[remainder.startIndex..<openRange.lowerBound]
        result += parsedInlineSegment(String(before))

        let afterOpen = remainder[openRange.upperBound...]
        guard let closeRange = afterOpen.range(of: "~~") else {
            // No closing marker: treat the rest of the text, tildes and all,
            // as plain (non-struck-through) inline Markdown.
            result += parsedInlineSegment(String(remainder[openRange.lowerBound...]))
            return result
        }

        let inner = afterOpen[afterOpen.startIndex..<closeRange.lowerBound]
        var struckThrough = parsedInlineSegment(String(inner))
        struckThrough.strikethroughStyle = .single
        result += struckThrough

        remainder = afterOpen[closeRange.upperBound...]
    }

    result += parsedInlineSegment(String(remainder))
    return result
}

/// Parses one strikethrough-free segment as inline Markdown.
private func parsedInlineSegment(_ text: String) -> AttributedString {
    guard !text.isEmpty else { return AttributedString() }
    let options = AttributedString.MarkdownParsingOptions(
        allowsExtendedAttributes: true,
        interpretedSyntax: .inlineOnlyPreservingWhitespace
    )
    if let attributed = try? AttributedString(markdown: text, options: options) {
        return attributed
    }
    return AttributedString(text)
}
