import Foundation

/// Works out what a Markdown editor should do when Return is pressed on a
/// list, task, or quote line.
///
/// Kept as a pure, testable helper rather than living inside the text view:
/// the rule ("continue the marker, unless the item is empty, in which case
/// end the list") is behaviour worth covering by unit tests, while the
/// `NSTextView` around it is not.
enum MarkdownListContinuation {
    enum Outcome: Equatable {
        /// Insert this prefix on the new line, continuing the run.
        case marker(String)
        /// The item held nothing but its marker: replace the line with this
        /// text (an empty line) so Return ends the run instead of adding
        /// another blank bullet.
        case clear(String)
    }

    /// `line` is the current line without its newline.
    static func continuation(for line: String) -> Outcome? {
        let indentLength = line.prefix { $0 == " " || $0 == "\t" }.count
        let indent = String(line.prefix(indentLength))
        let rest = String(line.dropFirst(indentLength))
        guard let marker = marker(in: rest) else { return nil }

        let content = String(rest.dropFirst(marker.consumed.count))
            .trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return .clear("") }
        return .marker(indent + marker.next)
    }

    private struct Marker {
        /// The marker as it appears on the current line.
        let consumed: String
        /// The marker to put on the following line.
        let next: String
    }

    private static func marker(in rest: String) -> Marker? {
        // Tasks first: "- [x] " also matches the plain bullet rule, and a
        // continued task must start unchecked rather than inherit a tick.
        if let match = taskMarker(in: rest) { return match }
        if let match = bulletMarker(in: rest) { return match }
        if let match = numberedMarker(in: rest) { return match }
        if rest.hasPrefix("> ") { return Marker(consumed: "> ", next: "> ") }
        if rest == ">" { return Marker(consumed: ">", next: "> ") }
        return nil
    }

    private static func taskMarker(in rest: String) -> Marker? {
        for bullet in ["-", "*", "+"] {
            for box in ["[ ]", "[x]", "[X]"] {
                let prefix = "\(bullet) \(box) "
                if rest.hasPrefix(prefix) {
                    return Marker(consumed: prefix, next: "\(bullet) [ ] ")
                }
                if rest == "\(bullet) \(box)" {
                    return Marker(consumed: rest, next: "\(bullet) [ ] ")
                }
            }
        }
        return nil
    }

    private static func bulletMarker(in rest: String) -> Marker? {
        for bullet in ["-", "*", "+"] {
            if rest.hasPrefix("\(bullet) ") {
                return Marker(consumed: "\(bullet) ", next: "\(bullet) ")
            }
            if rest == bullet {
                return Marker(consumed: bullet, next: "\(bullet) ")
            }
        }
        return nil
    }

    private static func numberedMarker(in rest: String) -> Marker? {
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let afterDigits = rest.dropFirst(digits.count)
        guard let separator = afterDigits.first, separator == "." || separator == ")" else { return nil }
        let consumedCore = "\(digits)\(separator)"
        let next = "\(number + 1)\(separator) "
        if rest.hasPrefix(consumedCore + " ") {
            return Marker(consumed: consumedCore + " ", next: next)
        }
        if rest == consumedCore {
            return Marker(consumed: consumedCore, next: next)
        }
        return nil
    }
}
