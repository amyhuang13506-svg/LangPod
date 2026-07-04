import Foundation

/// 「我的句子」收藏（UserDefaults 持久化，仿 VocabularyStore）。
@Observable
class SentenceStore {
    var sentences: [SavedSentence] = []

    private let storageKey = "savedSentences"

    init() {
        load()
    }

    var totalCount: Int { sentences.count }

    /// 可练习的句子（连词成句 ≤12 词过滤）
    var practiceableSentences: [SavedSentence] {
        sentences.filter { $0.isPracticeable }
    }

    // MARK: - 掌握分类（仿 VocabularyStore：已掌握 / 复习中 / 新句）

    /// 已掌握：连词成句答对 ≥2（30 天内练过）
    var strongSentences: [SavedSentence] { sentences.filter { $0.memoryState == .strong } }
    /// 复习中：答对 1 次
    var fadingSentences: [SavedSentence] { sentences.filter { $0.memoryState == .fading } }
    /// 新句：还没练过（答对 0 次）
    var newSentences: [SavedSentence] { sentences.filter { $0.memoryState == .forgetting } }

    /// 连词成句答对一句 → 记账（推进 复习中 / 已掌握）。SentencePracticeView.checkAnswer 调用。
    func recordPracticeCorrect(_ english: String) {
        guard let i = sentences.firstIndex(where: { $0.english == english }) else { return }
        sentences[i].recordPracticeCorrect()
        persist()
    }

    func isSaved(_ english: String) -> Bool {
        sentences.contains { $0.english == english }
    }

    @discardableResult
    func add(_ sentence: SavedSentence) -> Bool {
        guard !isSaved(sentence.english) else { return false }
        sentences.insert(sentence, at: 0)
        persist()
        Analytics.track(.sentenceSave, params: [
            "source": sentence.source,
            "total": "\(sentences.count)",
        ])
        return true
    }

    func remove(_ sentence: SavedSentence) {
        sentences.removeAll { $0.id == sentence.id }
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SavedSentence].self, from: data) else {
            return
        }
        sentences = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sentences) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
