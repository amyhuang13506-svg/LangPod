import Foundation

/// API service for fetching episodes from the server.
/// Falls back to local mock data when the server is unreachable.
actor APIService {
    static let shared = APIService()

    // Server base URL (Nginx proxy on Aliyun → OSS)
    private let baseURL = "http://47.84.141.119/langpod/api"

    // MARK: - Episode List

    /// Fetch episode index for a level. Falls back to mock data on failure.
    func fetchEpisodes(for level: PodcastLevel) async -> [Episode] {
        let url = URL(string: "\(baseURL)/episodes/\(level.rawValue)/index.json")!

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return MockDataLoader.loadEpisodes(for: level)
            }

            let index = try JSONDecoder().decode(EpisodeIndex.self, from: data)

            // Fetch full episode details for each
            var episodes: [Episode] = []
            for item in index.episodes {
                if let episode = await fetchEpisodeDetail(id: item.id, level: level) {
                    episodes.append(episode)
                }
            }

            // Cache for offline use
            cacheEpisodes(episodes, for: level)

            return episodes.isEmpty ? MockDataLoader.loadEpisodes(for: level) : episodes
        } catch {
            // Try cached data first, then fall back to mock
            if let cached = loadCachedEpisodes(for: level) {
                return cached
            }
            return MockDataLoader.loadEpisodes(for: level)
        }
    }

    /// Fetch full episode detail by ID
    private func fetchEpisodeDetail(id: String, level: PodcastLevel) async -> Episode? {
        let url = URL(string: "\(baseURL)/episodes/\(level.rawValue)/\(id)/episode.json")!

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            return try JSONDecoder().decode(Episode.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Caching

    private var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LangPodEpisodes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cacheEpisodes(_ episodes: [Episode], for level: PodcastLevel) {
        let file = cacheDirectory.appendingPathComponent("episodes_\(level.rawValue).json")
        guard let data = try? JSONEncoder().encode(episodes) else { return }
        try? data.write(to: file)
    }

    private func loadCachedEpisodes(for level: PodcastLevel) -> [Episode]? {
        let file = cacheDirectory.appendingPathComponent("episodes_\(level.rawValue).json")
        guard let data = try? Data(contentsOf: file),
              let episodes = try? JSONDecoder().decode([Episode].self, from: data),
              !episodes.isEmpty else {
            return nil
        }
        return episodes
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
    let vocabularyCount: Int

    enum CodingKeys: String, CodingKey {
        case id, title, level, date, audio
        case durationSeconds = "duration_seconds"
        case vocabularyCount = "vocabulary_count"
    }
}
