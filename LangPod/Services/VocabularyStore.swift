import Foundation

@Observable
class VocabularyStore {
    var words: [SavedWord] = []

    private let storageKey = "savedWords"

    init() {
        load()
    }

    // MARK: - Computed

    var totalCount: Int { words.count }

    var strongWords: [SavedWord] { words.filter { $0.memoryState == .strong } }
    var fadingWords: [SavedWord] { words.filter { $0.memoryState == .fading } }
    var forgettingWords: [SavedWord] { words.filter { $0.memoryState == .forgetting } }

    var todayWords: [SavedWord] {
        let calendar = Calendar.current
        return words.filter { calendar.isDateInToday($0.lastReviewDate) }
    }

    var wordsNeedingReview: [SavedWord] {
        words.filter { $0.nextReviewDate <= Date() }
    }

    func wordsByMastery(_ level: MasteryLevel) -> [SavedWord] {
        words.filter { $0.masteryLevel == level }
    }

    // MARK: - Actions

    func saveWords(from episode: Episode) {
        for vocab in episode.vocabulary {
            guard !words.contains(where: { $0.word == vocab.word }) else { continue }
            words.append(SavedWord(from: vocab))
        }
        persist()
    }

    func markReviewed(_ word: String) {
        guard let idx = words.firstIndex(where: { $0.word == word }) else { return }
        words[idx].markReviewed()
        persist()
    }

    func upgradeMastery(_ word: String, to level: MasteryLevel) {
        guard let idx = words.firstIndex(where: { $0.word == word }) else { return }
        words[idx].masteryLevel = level
        persist()
    }

    func clearMasteredWords() {
        words.removeAll { $0.memoryState == .strong }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(words) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([SavedWord].self, from: data) else {
            loadMockData()
            return
        }
        words = saved
    }

    /// Pre-populate with some mock words for UI development
    private func loadMockData() {
        let allEpisodes = MockDataLoader.loadAllEpisodes()
        for episode in allEpisodes.prefix(3) {
            for vocab in episode.vocabulary {
                var saved = SavedWord(from: vocab)
                // Vary the review dates for visual variety
                let daysAgo = Double.random(in: 0...14)
                saved.lastReviewDate = Date().addingTimeInterval(-daysAgo * 86400)
                saved.reviewCount = Int.random(in: 0...5)
                saved.masteryLevel = MasteryLevel.allCases.randomElement() ?? .heard
                words.append(saved)
            }
        }
        persist()
    }
}
