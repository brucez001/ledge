import Foundation

/// Turns whatever the user typed into either a navigable URL or a search.
///
/// The rules deliberately favour "search" when the input is ambiguous, so
/// typing `4.5 vs 5` does not navigate to a nonexistent `4.5` host, while
/// still recognising ports (`localhost:3000`), bare IPs, paths, and local
/// files dragged or pasted in as plain paths.
enum AddressResolver {
    private static let navigableSchemes: Set<String> = ["http", "https", "file", "about"]

    static func resolve(_ rawValue: String, using engine: SearchEngine = .google) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let url = explicitSchemeURL(value) { return url }
        if let url = localFileURL(value) { return url }
        if let url = implicitHTTPSURL(value) { return url }
        return engine.searchURL(for: value)
    }

    // MARK: - Steps

    private static func explicitSchemeURL(_ value: String) -> URL? {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              navigableSchemes.contains(scheme),
              let url = components.url else { return nil }
        return url
    }

    /// Only resolves to a `file:` URL when the path actually exists, so a
    /// search like `/r/macapps best launcher` still searches.
    private static func localFileURL(_ value: String) -> URL? {
        guard value.hasPrefix("/") || value.hasPrefix("~/") else { return nil }
        let expanded = (value as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        return URL(fileURLWithPath: expanded)
    }

    private static func implicitHTTPSURL(_ value: String) -> URL? {
        guard !value.contains(where: \.isWhitespace) else { return nil }

        let authority = value.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard !authority.isEmpty else { return nil }

        // Strip an optional trailing :port before validating the host.
        var host = String(authority)
        if let colonIndex = host.lastIndex(of: ":") {
            let port = host[host.index(after: colonIndex)...]
            guard !port.isEmpty, port.allSatisfy(\.isNumber) else { return nil }
            host = String(host[..<colonIndex])
        }

        guard isHostLike(host) else { return nil }
        return URL(string: "https://\(value)") ?? encodedURL(from: value)
    }

    /// Fallback for hosts/paths containing characters `URL(string:)` rejects
    /// (for example an internationalised domain or a space-free unicode path).
    private static func encodedURL(from value: String) -> URL? {
        guard let encoded = value.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed.union(.urlPathAllowed).union(.urlHostAllowed)
        ) else { return nil }
        return URL(string: "https://\(encoded)")
    }

    // MARK: - Host heuristics

    private static func isHostLike(_ host: String) -> Bool {
        guard !host.isEmpty else { return false }
        if host.caseInsensitiveCompare("localhost") == .orderedSame { return true }
        if isIPv4(host) { return true }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }

        // A real top-level domain is alphabetic, so `4.5` and `192.168.0`
        // fall through to search instead of becoming bogus hosts.
        guard let tld = labels.last, (2...24).contains(tld.count), tld.allSatisfy(\.isLetter) else {
            return false
        }
        return labels.allSatisfy { label in
            label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || !$0.isASCII }
        }
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber) && (Int(part) ?? 256) <= 255
        }
    }
}
