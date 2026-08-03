import SwiftUI

/// Renders a real fetched site icon for `host`, falling back to a generated
/// letter tile (deterministic colour per host) while loading or when the
/// icon cannot be fetched. The letter tile matters more than it sounds:
/// undifferentiated placeholder squares are the most common complaint about
/// this class of app, because every unresolved site looks identical.
struct FaviconView: View {
    let host: String
    var size: CGFloat = 32
    /// Bumped by the app when the favicon source preference changes, so the
    /// icon is re-requested instead of showing a stale cache entry.
    var revision: Int = 0

    /// `FaviconStore` publishes its own revision now, so a source change is
    /// picked up by every mounted view even when nothing passes the
    /// `revision` parameter above explicitly.
    @ObservedObject private var store = FaviconStore.shared
    @State private var image: NSImage?
    @State private var isResolved = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.1)
            } else {
                MonogramIcon(host: host, size: size, isDimmed: !isResolved)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.18), value: image != nil)
        .task(id: "\(host)#\(revision)#\(store.revision)") {
            isResolved = false
            image = FaviconStore.shared.cachedImage(for: host)
            if image == nil {
                image = await FaviconStore.shared.loadImage(for: host)
            }
            isResolved = true
        }
    }
}

/// Letter tile used whenever a real icon is unavailable.
struct MonogramIcon: View {
    let host: String
    var size: CGFloat = 32
    var isDimmed: Bool = false

    private var letter: String {
        let trimmed = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return String(trimmed.first ?? "?").uppercased()
    }

    /// Stable hue per host so an icon never changes colour between launches.
    private var hue: Double {
        let seed = host.unicodeScalars.reduce(UInt32(7)) { partial, scalar in
            partial &* 31 &+ scalar.value
        }
        return Double(seed % 360) / 360
    }

    var body: some View {
        RoundedRectangle(cornerRadius: max(4, size * 0.28), style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hue: hue, saturation: 0.52, brightness: 0.82),
                        Color(hue: hue, saturation: 0.62, brightness: 0.66)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Text(letter)
                    .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .opacity(isDimmed ? 0.55 : 1)
    }
}
