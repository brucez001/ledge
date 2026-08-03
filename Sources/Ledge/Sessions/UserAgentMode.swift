import Foundation

/// Per-site browser identity. Some web apps only expose their compact,
/// touch-oriented layout to mobile Safari, which suits a narrow slide-over
/// panel far better than the desktop layout.
enum UserAgentMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case desktop
    case mobile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: "Desktop site"
        case .mobile: "Mobile site"
        }
    }

    var symbolName: String {
        switch self {
        case .desktop: "display"
        case .mobile: "iphone"
        }
    }

    /// `nil` means "leave WebKit's own user agent alone", which keeps the
    /// Safari-compatible default that sign-in flows expect.
    var customUserAgent: String? {
        switch self {
        case .desktop:
            nil
        case .mobile:
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
        }
    }

    var toggled: UserAgentMode {
        self == .desktop ? .mobile : .desktop
    }
}
