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

    // MARK: - Raw Podcast (硅谷原声)

    /// 拉「硅谷原声」master 列表（pipeline A 写到 OSS 的）。
    /// 失败时返回 nil；DataStore 会回到 bundle 里的种子数据。
    func fetchRawPodcasts() async -> [RawPodcast]? {
        guard let url = URL(string: "\(baseURL)/raw_podcasts/raw_podcasts.json") else {
            return nil
        }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                debugLog("⚠️ raw_podcasts HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            let rewritten = rewriteURLs(data)
            let items = try JSONDecoder().decode([RawPodcast].self, from: rewritten)
            cacheRawPodcasts(items)
            debugLog("✅ raw_podcasts loaded: \(items.count) items")
            return items
        } catch {
            debugLog("⚠️ raw_podcasts fetch error: \(error.localizedDescription)")
            return nil
        }
    }

    private func cacheRawPodcasts(_ items: [RawPodcast]) {
        let file = cacheDirectory.appendingPathComponent("raw_podcasts.json")
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: file)
        }
    }

    /// 拉「硅谷原声」单期字幕。**网络优先，失败回缓存**（避免老缓存吞掉新版字幕）。
    func fetchTranscript(transcriptUrl: String, podcastId: String) async -> RawTranscript? {
        guard let url = URL(string: transcriptUrl) else {
            return loadCachedTranscriptSync(podcastId: podcastId)
        }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return loadCachedTranscriptSync(podcastId: podcastId)
            }
            let transcript = try JSONDecoder().decode(RawTranscript.self, from: data)
            cacheTranscript(transcript, podcastId: podcastId)
            return transcript
        } catch {
            debugLog("⚠️ transcript fetch error: \(error.localizedDescription)")
            return loadCachedTranscriptSync(podcastId: podcastId)
        }
    }

    private func cacheTranscript(_ transcript: RawTranscript, podcastId: String) {
        let file = cacheDirectory.appendingPathComponent("transcript_\(podcastId).json")
        if let data = try? JSONEncoder().encode(transcript) {
            try? data.write(to: file)
        }
    }

    nonisolated func loadCachedTranscriptSync(podcastId: String) -> RawTranscript? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CastlingoEpisodes", isDirectory: true)
        let file = dir.appendingPathComponent("transcript_\(podcastId).json")
        guard let data = try? Data(contentsOf: file),
              let t = try? JSONDecoder().decode(RawTranscript.self, from: data) else {
            return nil
        }
        return t
    }

    /// 拉一集预翻译的词典（从 raw_podcasts/<id>/words.json）。
    /// transcriptUrl 末尾的 transcript.json 替换为 words.json 即可。
    func fetchPodcastWords(transcriptUrl: String, podcastId: String) async -> RawPodcastWords? {
        let wordsUrlString = transcriptUrl.replacingOccurrences(
            of: "transcript.json",
            with: "words.json"
        )
        guard let url = URL(string: wordsUrlString) else {
            return loadCachedWordsSync(podcastId: podcastId)
        }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return loadCachedWordsSync(podcastId: podcastId)
            }
            let words = try JSONDecoder().decode(RawPodcastWords.self, from: data)
            cacheWords(words, podcastId: podcastId)
            return words
        } catch {
            debugLog("⚠️ words fetch error: \(error.localizedDescription)")
            return loadCachedWordsSync(podcastId: podcastId)
        }
    }

    private func cacheWords(_ words: RawPodcastWords, podcastId: String) {
        let file = cacheDirectory.appendingPathComponent("words_\(podcastId).json")
        if let data = try? JSONEncoder().encode(words) {
            try? data.write(to: file)
        }
    }

    nonisolated func loadCachedWordsSync(podcastId: String) -> RawPodcastWords? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CastlingoEpisodes", isDirectory: true)
        let file = dir.appendingPathComponent("words_\(podcastId).json")
        guard let data = try? Data(contentsOf: file),
              let w = try? JSONDecoder().decode(RawPodcastWords.self, from: data) else {
            return nil
        }
        return w
    }

    nonisolated func loadCachedRawPodcastsSync() -> [RawPodcast]? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CastlingoEpisodes", isDirectory: true)
        let file = dir.appendingPathComponent("raw_podcasts.json")
        guard let data = try? Data(contentsOf: file),
              let items = try? JSONDecoder().decode([RawPodcast].self, from: data),
              !items.isEmpty else {
            return nil
        }
        return items
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
