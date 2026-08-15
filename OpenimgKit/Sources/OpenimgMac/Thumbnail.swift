import SwiftUI
import AppKit
import ImageIO
import OpenimgKit

/// In-memory cache for decoded thumbnails.
///
/// AsyncImage would be the one-liner here, and it is the wrong tool: it holds
/// nothing between view identities, so scrolling a grid re-downloads and
/// re-decodes every card that leaves and re-enters the viewport. On a page of
/// 200 that is 200 requests per pass over the same images.
///
/// NSCache rather than a dictionary because it evicts under memory pressure on
/// its own — a 200-image page of 600px thumbnails is real memory, and the app
/// should give it back when the system asks rather than when it feels like it.
@MainActor
final class ThumbnailCache {
    /// Grid thumbnails: many, small.
    static let shared = ThumbnailCache(limit: 400)

    /// Full-resolution originals, kept apart from the grid's cache and kept
    /// short. One of the pictures on the live site is a 20 MB PNG; 400 of those
    /// is a number NSCache should never be asked to hold, and the viewer only
    /// ever needs the current image and the one either side of it.
    static let full = ThumbnailCache(limit: 6)

    private let cache = NSCache<NSString, NSImage>()
    // 跨并发边界只传 CGImage:NSImage 的 Sendable 一致性在正式版 SDK 里
    // 明确不可用(本机 beta 放行只是巧合),Task 的 Success 必须 Sendable。
    private var inFlight: [String: Task<CGImage?, Never>] = [:]

    private init(limit: Int) { cache.countLimit = limit }

    func image(for url: String, client: OpenimgClient?) async -> NSImage? {
        if let hit = cache.object(forKey: url as NSString) { return hit }
        // Two cards can ask for the same URL in the same frame — dedup so the
        // second one waits on the first request instead of starting another.
        if let running = inFlight[url] {
            guard let cg = await running.value else { return nil }
            return cachedImage(cg, for: url)
        }

        let task = Task<CGImage?, Never> {
            guard let client else { return nil }
            guard let data = try? await client.fetchData(url) else { return nil }
            return Self.decode(data)
        }
        inFlight[url] = task
        let cg = await task.value
        inFlight[url] = nil
        guard let cg else { return nil }
        return cachedImage(cg, for: url)
    }

    /// CGImage → NSImage 的包装与落缓存,只发生在主 actor 上。
    private func cachedImage(_ cg: CGImage, for url: String) -> NSImage {
        if let hit = cache.object(forKey: url as NSString) { return hit }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(img, forKey: url as NSString)
        return img
    }

    nonisolated private static func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(src) >= 1 else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}

/// A thumbnail that keeps its loaded image across scrolls.
struct Thumbnail: View {
    let url: String
    let client: OpenimgClient?
    @State private var image: NSImage?

    var body: some View {
        // Color.clear takes whatever size the parent proposes; the image is
        // drawn over it and clipped to that. Applying .aspectRatio(.fill)
        // directly makes the view report the image's own size instead, so the
        // card grows to the full resolution of its thumbnail and spills over
        // its neighbours — which is exactly what the grid was doing.
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Rectangle().fill(.white.opacity(0.06))
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .clipped()
            .task(id: url) {
                image = await ThumbnailCache.shared.image(for: url, client: client)
            }
    }
}
