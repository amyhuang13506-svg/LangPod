import Foundation

struct MockDataLoader {
    static func loadEpisodes(for level: PodcastLevel) -> [Episode] {
        let filename = "episodes_\(level.rawValue)"
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        do {
            return try JSONDecoder().decode([Episode].self, from: data)
        } catch {
            return []
        }
    }

    static func loadAllEpisodes() -> [Episode] {
        PodcastLevel.allCases.flatMap { loadEpisodes(for: $0) }
    }
}
