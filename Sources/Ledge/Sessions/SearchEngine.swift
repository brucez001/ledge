import Foundation

/// Search provider used when the launcher's omnibox text is not an address.
enum SearchEngine: String, CaseIterable, Identifiable, Sendable {
    case google
    case duckDuckGo
    case bing
    case kagi
    case startpage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        case .kagi: "Kagi"
        case .startpage: "Startpage"
        }
    }

    /// Host shown in the omnibox hint and used to source the engine's icon.
    var host: String {
        switch self {
        case .google: "www.google.com"
        case .duckDuckGo: "duckduckgo.com"
        case .bing: "www.bing.com"
        case .kagi: "kagi.com"
        case .startpage: "www.startpage.com"
        }
    }

    private var searchPath: String {
        switch self {
        case .google: "/search"
        case .duckDuckGo: "/"
        case .bing: "/search"
        case .kagi: "/search"
        case .startpage: "/sp/search"
        }
    }

    func searchURL(for query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = searchPath
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }
}
