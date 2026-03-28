import Foundation

struct MockDataLoader {
    static func loadEpisodes(for level: PodcastLevel) -> [Episode] {
        let filename = "episodes_\(level.rawValue)"
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("❌ MockDataLoader: File not found: \(filename).json")
            return []
        }
        do {
            let episodes = try JSONDecoder().decode([Episode].self, from: data)
            return episodes
        } catch {
            print("❌ MockDataLoader: Decode error for \(filename): \(error)")
            return []
        }
    }

    static func loadAllEpisodes() -> [Episode] {
        PodcastLevel.allCases.flatMap { loadEpisodes(for: $0) }
    }
}
