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

    /// 已掌握: 配对 >= 3 或 造句 >= 1 (且 30 天内有练习)
    var strongWords: [SavedWord] { words.filter { $0.memoryState == .strong } }

    /// 复习中: 配对 1-2 次
    var fadingWords: [SavedWord] { words.filter { $0.memoryState == .fading } }

    /// 新词: 配对 0 次
    var forgettingWords: [SavedWord] { words.filter { $0.memoryState == .forgetting } }

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

    func recordMatchCorrect(_ word: String) {
        guard let idx = words.firstIndex(where: { $0.word == word }) else { return }
        words[idx].recordMatchCorrect()
        persist()
    }

    func recordSentenceCorrect(_ word: String) {
        guard let idx = words.firstIndex(where: { $0.word == word }) else { return }
        words[idx].recordSentenceCorrect()
        persist()
    }

    // Legacy compatibility
    func markReviewed(_ word: String) {
        recordMatchCorrect(word)
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
        migrateExampleTranslations()
    }

    /// Fill in missing exampleZh from latest episode data
    private func migrateExampleTranslations() {
        let allVocab = MockDataLoader.loadAllEpisodes().flatMap(\.vocabulary)
        var updated = false
        for i in words.indices {
            if words[i].exampleZh == nil || words[i].exampleZh?.isEmpty == true {
                if let match = allVocab.first(where: { $0.word == words[i].word }) {
                    if let zh = match.exampleZh, !zh.isEmpty {
                        words[i].exampleZh = zh
                        updated = true
                    }
                }
            }
        }
        if updated { persist() }
    }

    private func loadMockData() {
        let allEpisodes = MockDataLoader.loadAllEpisodes()
        for episode in allEpisodes.prefix(3) {
            for vocab in episode.vocabulary {
                var saved = SavedWord(from: vocab)
                // Vary for visual variety
                let matchCount = Int.random(in: 0...4)
                saved.matchCorrectCount = matchCount
                saved.sentenceCorrectCount = matchCount > 2 ? Int.random(in: 0...1) : 0
                saved.lastPracticeDate = Date().addingTimeInterval(-Double.random(in: 0...14) * 86400)
                if matchCount >= 1 { saved.masteryLevel = .recognized }
                if saved.sentenceCorrectCount >= 1 { saved.masteryLevel = .canUse }
                words.append(saved)
            }
        }
        persist()
    }
}
