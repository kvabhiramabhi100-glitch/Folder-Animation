import SwiftUI
import UIKit
import ImageIO

struct Photo: Identifiable {
    enum Source {
        case asset(String)
        case remote(URL)
    }
    let id = UUID()
    let source: Source

    static func asset(_ name: String) -> Photo { Photo(source: .asset(name)) }
    static func remote(_ url: URL) -> Photo { Photo(source: .remote(url)) }
}

struct Album: Identifiable {
    let id = UUID()
    let title: String
    let photos: [Photo]
    var style: FolderStyle = .graphite
}

extension Album {
    static let titles = ["Paris 2025", "Japan 2026", "China 2026", "Seoul 2026", "New York 2026", "Mexico 2026"]

    /// Demo data using seeded picsum photos (needs network).
    static let samples: [Album] = titles.enumerated().map { index, title in
        let photos = (0..<8).map { n in
            Photo.remote(URL(string: "https://picsum.photos/seed/folder\(index)x\(n)/600/750")!)
        }
        return Album(title: title, photos: photos)
    }

    /// Asset-catalog version: add images named e.g. "album0_0" ... "album5_7"
    /// to Assets.xcassets and pass `Album.assetSamples` in FolderStackApp.
    static let assetSamples: [Album] = titles.enumerated().map { index, title in
        Album(title: title, photos: (0..<8).map { .asset("album\(index)_\($0)") })
    }
}

// MARK: - Image cache

/// Downloads, downsamples and decodes remote photos once, off the main thread,
/// and keeps the decoded bitmaps in memory so cards never re-decode while animating.
@MainActor
final class ImageStore {
    static let shared = ImageStore()

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 128 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let image = cached(url) { return image }
        if let task = inFlight[url] { return await task.value }
        let session = session
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            return Self.decode(data, maxPixel: 900)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }

    /// Loads every remote photo, starting with album `first` and its neighbours.
    func prefetch(_ albums: [Album], first: Int) {
        let order = albums.indices.sorted { abs($0 - first) < abs($1 - first) }
        Task {
            for (rank, a) in order.enumerated() {
                let urls = albums[a].photos.compactMap { photo -> URL? in
                    if case .remote(let url) = photo.source { return url }
                    return nil
                }
                if rank < 2 {
                    // Visible albums: wait for them before starting the rest.
                    await withTaskGroup(of: Void.self) { group in
                        for url in urls { group.addTask { _ = await self.load(url) } }
                    }
                } else {
                    for url in urls { Task { _ = await load(url) } }
                }
            }
        }
    }

    nonisolated private static func decode(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Card

struct PhotoCardView: View {
    let photo: Photo
    let tint: Color

    var body: some View {
        ZStack {
            LinearGradient(colors: [tint.opacity(0.9), tint.opacity(0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            switch photo.source {
            case .asset(let name):
                Image(name).resizable().scaledToFill()
            case .remote(let url):
                RemoteImage(url: url)
            }
        }
    }
}

private struct RemoteImage: View {
    let url: URL
    @State private var image: UIImage?

    init(url: URL) {
        self.url = url
        _image = State(initialValue: ImageStore.shared.cached(url))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .transition(.opacity)
            }
        }
        .task(id: url) {
            guard image == nil, let loaded = await ImageStore.shared.load(url) else { return }
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }
}

// MARK: - Haptics

@MainActor
enum Haptics {
    private static var impacts: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = impacts[style] ?? UIImpactFeedbackGenerator(style: style)
        impacts[style] = generator
        generator.impactOccurred()
        generator.prepare()
    }

    static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }
}
