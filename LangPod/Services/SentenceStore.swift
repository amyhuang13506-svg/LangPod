import Foundation

/// 「我的句子」收藏（UserDefaults 持久化，仿 VocabularyStore）。
@Observable
class SentenceStore {
    var sentences: [SavedSentence] = []

    private let storageKey = "savedSentences"

    init() {
        load()
        loadRelocalized()
        relocalizeIfNeeded()
    }

    // MARK: - 跨语言快照的显示层重翻译（非破坏性，仿 VocabularyStore）
    //
    // SavedSentence 快照没有语言标记 —— 用「当前语言非中文 && 译文含汉字」判定为
    // 老中文快照。译文从英文原句直翻（质量优于中转），只盖显示层不写回快照。

    private var relocalized: [String: String] = [:]   // english_lower → 当前语言译文
    private var relocalizeInFlight = false
    private var relocalizedKey: String { "relocalizedSentences_\(ContentLanguage.current.rawValue)" }

    private func needsRelocalization(_ s: SavedSentence) -> Bool {
        ContentLanguage.current != .zh
            && s.translation.contains(where: { "一" <= $0 && $0 <= "鿿" })
    }

    func displayTranslation(_ s: SavedSentence) -> String {
        guard needsRelocalization(s) else { return s.translation }
        return relocalized[s.english.lowercased()] ?? s.translation
    }

    private func loadRelocalized() {
        guard let data = UserDefaults.standard.data(forKey: relocalizedKey),
              let cached = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        relocalized = cached
    }

    private func persistRelocalized() {
        if let data = try? JSONEncoder().encode(relocalized) {
            UserDefaults.standard.set(data, forKey: relocalizedKey)
        }
    }

    /// 批量补齐缺失的当前语言译文（单次 GPT 调用，≤60 句）。失败静默，下次启动重试。
    func relocalizeIfNeeded() {
        guard ContentLanguage.current != .zh else { return }
        let pending = sentences.filter {
            needsRelocalization($0) && relocalized[$0.english.lowercased()] == nil
        }
        guard !pending.isEmpty, !relocalizeInFlight else { return }
        relocalizeInFlight = true
        let batch = Array(pending.prefix(60))
        Task {
            defer { relocalizeInFlight = false }
            guard let result = await SentenceRelocalizer.translate(
                batch.map(\.english), to: ContentLanguage.current) else { return }
            for (en, tr) in result {
                relocalized[en.lowercased()] = tr
            }
            persistRelocalized()
            if pending.count > batch.count { relocalizeIfNeeded() }
        }
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
