import Foundation

/// API service for fetching episodes from the server.
/// Falls back to local mock data when the server is unreachable.
actor APIService {
    static let shared = APIService()

    // OSS direct URL (public read)
    private let baseURL = "https://castlingo.oss-ap-southeast-1.aliyuncs.com"

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
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                debugLog("❌ Index HTTP \(code)")
                return []
            }

            let index = try JSONDecoder().decode(EpisodeIndex.self, from: data)
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
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                debugLog("⚠️ Detail \(id): HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            return try JSONDecoder().decode(Episode.self, from: data)
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

    enum CodingKeys: String, CodingKey {
        case id, title, level, date, audio, thumbnail
        case durationSeconds = "duration_seconds"
        case vocabularyCount = "vocabulary_count"
    }
}
