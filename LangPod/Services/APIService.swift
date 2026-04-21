import Foundation

/// API service for fetching episodes from the server.
/// Falls back to local mock data when the server is unreachable.
actor APIService {
    static let shared = APIService()

    /// Origin OSS host — what the pipeline bakes into index.json URLs.
    /// Used to rewrite embedded audio/thumbnail URLs to the configured host.
    private static let originOSSHost = "castlingo.oss-ap-southeast-1.aliyuncs.com"

    /// Base URL for fetching index + detail. Reads `OSSBaseURL` from Info.plist
    /// (set this to the CDN/accelerate host once provisioned), falls back to
    /// direct OSS. Swap = one Info.plist edit, no code recompile semantics.
    private var baseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "OSSBaseURL") as? String
            ?? "https://\(Self.originOSSHost)"
    }

    /// Extracted host from configured base URL — used for URL rewriting.
    private var configuredHost: String {
        URL(string: baseURL)?.host ?? Self.originOSSHost
    }

    /// Rewrite any origin-OSS hosts inside a JSON blob to the configured host
    /// (CDN/accelerate). No-op when host is unchanged. Operates on the raw
    /// UTF-8 blob so it catches embedded audio + thumbnail + vocab audio URLs
    /// in one pass without needing to walk the decoded model.
    private func rewriteURLs(_ data: Data) -> Data {
        let newHost = configuredHost
        guard newHost != Self.originOSSHost else { return data }
        guard var text = String(data: data, encoding: .utf8) else { return data }
        text = text.replacingOccurrences(of: Self.originOSSHost, with: newHost)
        return Data(text.utf8)
    }

    // MARK: - Episode List

    /// Fetch episode index for a level. Returns lightweight Episodes (no script/vocabulary).
    /// Caller should lazy-load full details via fetchEpisodeDetail when needed.
    func fetchEpisodes(for level: PodcastLevel) async -> [Episode] {
        guard let url = URL(string: "\(baseURL)/episodes/\(level.rawValue)/index.json") else {
            debugLog("❌ Invalid URL for \(level.rawValue)")
            return []
        }

        do {
            debugLog("📡 Fetching index: \(url)")
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                debugLog("❌ Index HTTP \(code)")
                return []
            }

            let rewritten = rewriteURLs(data)
            let index = try JSONDecoder().decode(EpisodeIndex.self, from: rewritten)
            debugLog("✅ Index loaded: \(index.total) episodes")

            // Convert index items to lightweight Episodes (no script/vocabulary yet)
            var episodes = index.episodes.map { Episode(from: $0) }
            episodes.sort { $0.date < $1.date }

            // Cache for offline use
            if !episodes.isEmpty {
                cacheEpisodes(episodes, for: level)
            }
            return episodes
        } catch {
            debugLog("❌ Fetch error: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetch full episode detail by ID. Used for lazy loading script/vocabulary on play.
    func fetchEpisodeDetail(id: String, level: PodcastLevel) async -> Episode? {
        guard let url = URL(string: "\(baseURL)/episodes/\(level.rawValue)/\(id)/episode.json") else { return nil }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                debugLog("⚠️ Detail \(id): HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            let rewritten = rewriteURLs(data)
            return try JSONDecoder().decode(Episode.self, from: rewritten)
        } catch {
            debugLog("⚠️ Detail \(id) decode error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Public access to disk cache (used by DataStore for instant startup display)
    nonisolated func loadCachedEpisodesSync(for level: PodcastLevel) -> [Episode]? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CastlingoEpisodes", isDirectory: true)
        let file = dir.appendingPathComponent("episodes_\(level.rawValue).json")
        guard let data = try? Data(contentsOf: file),
              let episodes = try? JSONDecoder().decode([Episode].self, from: data),
              !episodes.isEmpty else {
            return nil
        }
        return episodes
    }

    // MARK: - Caching

    private var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CastlingoEpisodes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cacheEpisodes(_ episodes: [Episode], for level: PodcastLevel) {
        let file = cacheDirectory.appendingPathComponent("episodes_\(level.rawValue).json")
        guard let data = try? JSONEncoder().encode(episodes) else { return }
        try? data.write(to: file)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[API] \(message)")
        #endif
    }
}

// MARK: - Index Model

/// Lightweight index returned by the server (no full scripts)
struct EpisodeIndex: Codable {
    let level: String
    let episodes: [EpisodeIndexItem]
    let total: Int
}

struct EpisodeIndexItem: Codable {
    let id: String
    let title: String
    let level: String
    let date: String
    let durationSeconds: Int
    let audio: EpisodeAudio
    let thumbnail: String?
    let vocabularyCount: Int
    let patterns: [Pattern]?

    enum CodingKeys: String, CodingKey {
        case id, title, level, date, audio, thumbnail, patterns
        case durationSeconds = "duration_seconds"
        case vocabularyCount = "vocabulary_count"
    }
}
