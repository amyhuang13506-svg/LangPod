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
    private var relocalizedLabels: [String: String] = [:]   // 中文场景/来源标签 → 当前语言
    private var relocalizeInFlight = false
    private var relocalizedKey: String { "relocalizedSentences_\(ContentLanguage.current.rawValue)" }
    private var relocalizedLabelsKey: String { "relocalizedLabels_\(ContentLanguage.current.rawValue)" }

    /// 快照语言 ≠ 当前内容语言 → 需要显示层重翻译。
    /// language=="zh" 可能是真中文快照，也可能是加字段前存的（当时任何语言都补 "zh"）——
    /// 用「译文含汉字」二次确认；其他语言值直接信字段（日语译文含汉字，不能用汉字判）。
    private func needsRelocalization(_ s: SavedSentence) -> Bool {
        let current = ContentLanguage.current
        guard s.language != current.rawValue else { return false }
        if s.language == ContentLanguage.zh.rawValue {
            return s.translation.contains(where: { "一" <= $0 && $0 <= "鿿" })
        }
        return true
    }

    func displayTranslation(_ s: SavedSentence) -> String {
        guard needsRelocalization(s) else { return s.translation }
        return relocalized[s.english.lowercased()] ?? s.translation
    }

    /// 场景胶囊 / 「来自：」标签的显示文案（异语言快照 → 当前语言缓存）。
    func displayScene(_ s: SavedSentence) -> String { displayLabel(s.scene, of: s) }
    func displaySourceLabel(_ s: SavedSentence) -> String { displayLabel(s.sourceLabel, of: s) }

    private func displayLabel(_ label: String, of s: SavedSentence) -> String {
        guard needsRelocalization(s) else { return label }
        return relocalizedLabels[label] ?? label
    }

    private func loadRelocalized() {
        if let data = UserDefaults.standard.data(forKey: relocalizedKey),
           let cached = try? JSONDecoder().decode([String: String].self, from: data) {
            relocalized = cached
        }
        if let data = UserDefaults.standard.data(forKey: relocalizedLabelsKey),
           let cached = try? JSONDecoder().decode([String: String].self, from: data) {
            relocalizedLabels = cached
        }
    }

    private func persistRelocalized() {
        if let data = try? JSONEncoder().encode(relocalized) {
            UserDefaults.standard.set(data, forKey: relocalizedKey)
        }
        if let data = try? JSONEncoder().encode(relocalizedLabels) {
            UserDefaults.standard.set(data, forKey: relocalizedLabelsKey)
        }
    }

    /// 批量补齐缺失的当前语言译文 + 场景/来源标签（每次 GPT 调用 ≤60 条，循环到翻完）。
    /// 失败静默，下次启动重试。
    func relocalizeIfNeeded() {
        let lang = ContentLanguage.current
        guard lang != .zh else { return }
        let pending = sentences.filter {
            needsRelocalization($0) && relocalized[$0.english.lowercased()] == nil
        }
        let pendingLabels = Array(Set(
            sentences.filter { needsRelocalization($0) }
                .flatMap { [$0.scene, $0.sourceLabel] }
                .filter { !$0.isEmpty && relocalizedLabels[$0] == nil }
        ))
        guard !pending.isEmpty || !pendingLabels.isEmpty, !relocalizeInFlight else { return }
        relocalizeInFlight = true
        Task {
            defer { relocalizeInFlight = false }
            // 注意不能用递归续批 —— inFlight 要到 Task 结束才复位，递归调用会被 guard 挡掉
            var remaining = pending
            while !remaining.isEmpty {
                let batch = Array(remaining.prefix(60))
                remaining.removeFirst(batch.count)
                guard let result = await SentenceRelocalizer.translate(
                    batch.map(\.english), to: lang) else { break }
                for (en, tr) in result {
                    relocalized[en.lowercased()] = tr
                }
                persistRelocalized()
            }
            var remainingLabels = pendingLabels
            while !remainingLabels.isEmpty {
                let batch = Array(remainingLabels.prefix(40))
                remainingLabels.removeFirst(batch.count)
                guard let result = await LabelRelocalizer.translate(batch, to: lang) else { break }
                for (zh, tr) in result {
                    relocalizedLabels[zh] = tr
                }
                persistRelocalized()
            }
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
