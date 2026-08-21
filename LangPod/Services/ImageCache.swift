import UIKit
import CryptoKit

/// Two-tier image cache: in-memory NSCache + on-disk Caches directory.
/// Disk LRU eviction kicks in above 300MB total — enough to hold every cover
/// in the catalog (~600 images), so a cover is downloaded once per install.
actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let maxDiskBytes = 300 * 1024 * 1024

    private var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CastlingoCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        memory.countLimit = 50
    }

    /// Returns cached image if available, otherwise downloads, caches, and returns.
    func image(for urlString: String) async -> UIImage? {
        let key = cacheKey(for: urlString)

        // 1. Memory hit
        if let img = memory.object(forKey: key as NSString) {
            return img
        }

        // 2. Disk hit
        let file = cacheDirectory.appendingPathComponent(key)
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            memory.setObject(img, forKey: key as NSString)
            // Update mtime so LRU tracking sees this as recently used
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: file.path
            )
            return img
        }

        // 3. Network — download, cache, return
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let img = UIImage(data: data) else {
                return nil
            }
            try? data.write(to: file)
            memory.setObject(img, forKey: key as NSString)
            evictOldFilesIfNeeded()
            return img
        } catch {
            return nil
        }
    }

    private func cacheKey(for urlString: String) -> String {
        Self.cacheKey(for: urlString)
    }

    nonisolated static func cacheKey(for urlString: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(urlString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".img"
    }

    /// Synchronous disk-only lookup. Returns nil immediately if not on disk.
    /// Safe to call from any thread; never touches the network.
    nonisolated func diskHitSync(for urlString: String) -> UIImage? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CastlingoCovers", isDirectory: true)
        let file = dir.appendingPathComponent(Self.cacheKey(for: urlString))
        guard let data = try? Data(contentsOf: file), let img = UIImage(data: data) else {
            return nil
        }
        return img
    }

    /// LRU eviction by file modification date, bounded by total byte size.
    private func evictOldFilesIfNeeded() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        var entries: [(url: URL, date: Date, size: Int)] = files.map { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return (url, values?.contentModificationDate ?? .distantPast, values?.fileSize ?? 0)
        }
        var totalBytes = entries.reduce(0) { $0 + $1.size }
        guard totalBytes > maxDiskBytes else { return }

        entries.sort { $0.date < $1.date } // oldest first
        for entry in entries {
            guard totalBytes > maxDiskBytes else { break }
            try? fm.removeItem(at: entry.url)
            totalBytes -= entry.size
        }
    }
}
