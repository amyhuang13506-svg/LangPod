import Foundation

/// API service for fetching episodes from the server.
/// Falls back to local mock data when the server is unreachable.
actor APIService {
    static let shared = APIService()

    // OSS direct URL (public read)
    private let baseURL = "https://castlingo.oss-ap-southeast-1.aliyuncs.com"

    // MARK: - Episode List

    /// Fetch episode index for a level. Falls back to mock data on failure.
    func fetchEpisodes(for level: PodcastLevel) async -> [Episode] {
        guard let url = URL(string: "\(baseURL)/episodes/\(level.rawValue)/index.json") else {
            print("[API] ❌ Invalid URL for \(level.rawValue)")
            return MockDataLoader.loadEpisodes(for: level)
        }

        do {
            print("[API] 📡 Fetching index: \(url)")
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[API] ❌ Index HTTP \(code)")
                return loadCachedEpisodes(for: level) ?? MockDataLoader.loadEpisodes(for: level)
            }

            let index = try JSONDecoder().decode(EpisodeIndex.self, from: data)
            print("[API] ✅ Index loaded: \(index.total) episodes")

            // Fetch full episode details concurrently
            var episodes: [Episode] = []
            await withTaskGroup(of: Episode?.self) { group in
                for item in index.episodes {
                    group.addTask {
                        await self.fetchEpisodeDetail(id: item.id, level: level)
                    }
                }
                for await episode in group {
                    if let ep = episode {
                        episodes.append(ep)
                    }
                }
            }
            // Sort by date
            episodes.sort { $0.date < $1.date }

            print("[API] ✅ Loaded \(episodes.count)/\(index.total) episode details")

            // Cache for offline use
            if !episodes.isEmpty {
                cacheEpisodes(episodes, for: level)
            }

            return episodes.isEmpty ? (loadCachedEpisodes(for: level) ?? MockDataLoader.loadEpisodes(for: level)) : episodes
        } catch {
            print("[API] ❌ Fetch error: \(error.localizedDescription)")
            if let cached = loadCachedEpisodes(for: level) {
                return cached
            }
            return MockDataLoader.loadEpisodes(for: level)
        }
    }

    /// Fetch full episode detail by ID
    private func fetchEpisodeDetail(id: String, level: PodcastLevel) async -> Episode? {
        guard let url = URL(string: "\(baseURL)/episodes/\(level.rawValue)/\(id)/episode.json") else { return nil }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("[API] ⚠️ Detail \(id): HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            return try JSONDecoder().decode(Episode.self, from: data)
        } catch {
            print("[API] ⚠️ Detail \(id) decode error: \(error.localizedDescription)")
            return nil
        }
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
