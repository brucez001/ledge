import AppKit
import Foundation

/// Disk-backed cache for fetched favicons, stored under Application
/// Support so they survive relaunches without re-hitting the network.
actor FaviconDiskCache {
    static let shared = FaviconDiskCache()

    private let directory: URL
    /// Bumped by `removeAll(generation:)`. A `write` tagged with a
    /// generation older than this is dropped rather than resurrecting a
    /// file the store just asked to be cleared. This has to live on the
    /// actor itself (not just be checked by `FaviconStore` beforehand)
    /// because only the actor sees the true arrival order of its own
    /// concurrent calls.
    private var currentGeneration = 0

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("Ledge/FaviconCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for host: String) -> URL {
        let safeName = host.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? host
        return directory.appendingPathComponent("\(safeName).png")
    }

    func read(host: String) -> Data? {
        try? Data(contentsOf: fileURL(for: host))
    }

    func write(host: String, data: Data, generation: Int) {
        guard generation >= currentGeneration else { return }
        try? data.write(to: fileURL(for: host), options: .atomic)
    }

    func removeAll(generation: Int) {
        currentGeneration = generation
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

/// Fetches real site icons with an in-memory + on-disk cache.
///
/// The site itself is asked first (`apple-touch-icon`, then `favicon.ico`)
/// so the app does not leak the list of sites a user has saved to a third
/// party. Google's favicon service is only used as a last resort, and can
/// be switched off entirely in Settings, in which case `FaviconView` falls
/// back to a generated letter tile.
@MainActor
final class FaviconStore: ObservableObject {
    static let shared = FaviconStore()

    /// Mirrors `Preferences.faviconSource`; the app keeps it in sync so
    /// views do not need to thread the preference through every call.
    var source: FaviconSource = .siteThenService
    /// Bumped by `invalidate()` so already-mounted `FaviconView`s can tell a
    /// source change happened and re-request instead of showing whatever
    /// they last resolved.
    @Published private(set) var revision = 0

    private var memoryCache: [String: NSImage] = [:]
    /// Hash of the bytes each cached icon was decoded from, so a newly
    /// declared icon can be told apart from a redisplay of the same one.
    /// Only meaningful within a launch, which is all it is used for.
    private var cachedIconSignatures: [String: Int] = [:]
    /// Each in-flight fetch is tagged with the `revision` it started under,
    /// so a completion that arrives after `invalidate()` bumped `revision`
    /// again is recognised as stale without needing `Task` identity checks.
    private var inFlight: [String: (generation: Int, task: Task<NSImage?, Never>)] = [:]

    private static let iconPaths = [
        "/apple-touch-icon.png",
        "/apple-touch-icon-precomposed.png",
        "/favicon.svg",
        "/favicon.ico",
        "/favicon.png"
    ]

    func cachedImage(for host: String) -> NSImage? {
        // `monogramOnly` promises letter tiles only; a real icon fetched
        // under a previous, more permissive source must not leak back in
        // just because it is still sitting in the memory cache.
        guard source.allowsSiteFetch else { return nil }
        return memoryCache[host]
    }

    func loadImage(for host: String) async -> NSImage? {
        guard !host.isEmpty else { return nil }
        guard source.allowsSiteFetch else { return nil }

        if let cached = memoryCache[host] {
            return cached
        }

        if let existing = inFlight[host] {
            return await existing.task.value
        }

        let generation = revision
        let task = Task<NSImage?, Never> { [weak self] in
            await self?.fetch(host: host, generation: generation)
        }
        inFlight[host] = (generation, task)
        let image = await task.value
        // Only clear the slot if it is still ours -- a newer call for the
        // same host (started after an `invalidate()`) may have already
        // replaced it with its own in-flight task.
        if inFlight[host]?.generation == generation {
            inFlight[host] = nil
        }
        return image
    }

    /// Drops cached icons so a source change (or a site's rebrand) is picked
    /// up on the next request.
    func invalidate() {
        revision += 1
        let generation = revision
        memoryCache.removeAll()
        cachedIconSignatures.removeAll()
        for entry in inFlight.values { entry.task.cancel() }
        inFlight.removeAll()
        Task { await FaviconDiskCache.shared.removeAll(generation: generation) }
    }

    /// Records an icon a page declared for itself, overriding whatever was
    /// guessed or fetched from a third party.
    ///
    /// This is the authoritative source: the page tells us where its icon is,
    /// and the fetch happens inside the web view, which is already signed in.
    /// Guessing `/favicon.ico` cannot reach an icon behind authentication, and
    /// the third-party fallback answers 200 with a blank globe for any host it
    /// cannot see, so without this an internal site is stuck with a grey
    /// placeholder for ever.
    func storeDeclaredIcon(_ data: Data, for host: String) {
        guard !host.isEmpty, source.allowsSiteFetch,
              let image = NSImage(data: data),
              image.size.width >= 8, image.size.height >= 8,
              Self.hasVisibleContent(image) else { return }

        // Compared by bytes rather than just presence: a host whose guessed or
        // third-party icon was wrong (a generic brand mark for a product that
        // ships its own) already has something cached, and the correction has
        // to reach the views without waiting for a relaunch.
        let signature = data.hashValue
        let isChanged = memoryCache[host] == nil || cachedIconSignatures[host] != signature
        memoryCache[host] = image
        cachedIconSignatures[host] = signature
        let generation = revision
        Task { await FaviconDiskCache.shared.write(host: host, data: data, generation: generation) }

        // Only nudge the views when this actually changes what they would
        // draw; a page reload re-declaring the same icon should not make every
        // icon in the rail re-request itself.
        if isChanged {
            revision += 1
        }
    }

    private func fetch(host: String, generation: Int) async -> NSImage? {
        // Checked first, before any disk or memory read, so switching to
        // "letter tiles only" hides a previously cached real icon instead
        // of it surviving one extra display until the cache expires.
        let effectiveSource = source
        guard effectiveSource.allowsSiteFetch else { return nil }

        if let diskData = await FaviconDiskCache.shared.read(host: host),
           let image = NSImage(data: diskData) {
            guard isStillCurrent(generation) else { return nil }
            memoryCache[host] = image
            cachedIconSignatures[host] = diskData.hashValue
            return image
        }

        for path in Self.iconPaths {
            guard isStillCurrent(generation) else { return nil }
            if let image = await download("https://\(host)\(path)", host: host, generation: generation) {
                return image
            }
        }

        guard effectiveSource.allowsServiceFallback, isStillCurrent(generation) else { return nil }

        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: "64"),
            // Ask for a 404 instead of the service's blank-globe placeholder.
            // Without this it answers 200 with a generic grey icon for any
            // host it cannot reach -- an internal or VPN-only site then caches
            // that placeholder for ever instead of falling back to a letter
            // tile, which at least tells the sites apart.
            URLQueryItem(name: "default_favicon", value: "false")
        ]
        guard let fallback = components?.url?.absoluteString else { return nil }
        return await download(fallback, host: host, generation: generation, rejectingPlaceholders: true)
    }

    /// `invalidate()` bumps `revision` synchronously, so this is `true`
    /// only if no invalidation (and no cancellation) happened since this
    /// fetch's generation was captured.
    private func isStillCurrent(_ generation: Int) -> Bool {
        !Task.isCancelled && generation == revision
    }

    /// Rasterises small and reports how much of the tile is actually painted,
    /// so a decodes-but-draws-nothing icon can be rejected.
    private static func hasVisibleContent(_ image: NSImage, threshold: Double = 0.02) -> Bool {
        let side = 32
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return true }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        guard let pixels = rep.bitmapData else { return true }
        var painted = 0
        let count = side * side
        for index in 0..<count where pixels[index * 4 + 3] > 12 {
            painted += 1
        }
        return Double(painted) / Double(count) >= threshold
    }

    private func download(
        _ address: String,
        host: String,
        generation: Int,
        rejectingPlaceholders: Bool = false
    ) async -> NSImage? {
        guard let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        // Some CDNs serve a placeholder HTML page for a missing icon; the
        // status-code and `NSImage` checks below reject those.
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard !data.isEmpty,
                  let image = NSImage(data: data),
                  image.size.width >= 8, image.size.height >= 8 else { return nil }
            // An icon that decodes but draws (almost) nothing is worse than no
            // icon: it looks broken, and every such site looks identical. A
            // letter tile at least tells them apart. `NSImage` decoding an SVG
            // whose artwork it cannot really render is the usual cause.
            guard Self.hasVisibleContent(image) else { return nil }
            // A third-party service can still answer 200 with its own generic
            // artwork. Rejecting the tiny sizes it uses for that is cheap
            // insurance: a real site icon requested at 64pt is not 16pt.
            if rejectingPlaceholders, image.size.width < 24 || image.size.height < 24 {
                return nil
            }
            // Dropped (not cached) rather than published if `invalidate()`
            // ran while the request was in flight -- otherwise a download
            // that finishes moments after a source change could re-insert
            // exactly the icon the user just asked to be forgotten.
            guard isStillCurrent(generation) else { return nil }
            memoryCache[host] = image
            cachedIconSignatures[host] = data.hashValue
            await FaviconDiskCache.shared.write(host: host, data: data, generation: generation)
            return image
        } catch {
            return nil
        }
    }
}
