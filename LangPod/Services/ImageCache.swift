import UIKit
import CryptoKit

/// Two-tier image cache: in-memory NSCache + on-disk Caches directory.
/// LRU eviction at 100 images (~20MB).
actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let maxDiskFiles = 100

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

    /// LRU eviction by file modification date.
    private func evictOldFilesIfNeeded() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ), files.count > maxDiskFiles else { return }

        let sorted = files.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l < r // oldest first
        }
        let toRemove = sorted.prefix(sorted.count - maxDiskFiles)
        for url in toRemove {
            try? fm.removeItem(at: url)
        }
    }
}
