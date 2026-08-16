import Foundation

@Observable
class VocabularyStore {
    var words: [SavedWord] = []

    // Daily practice limits (free tier: 1 round per day each)
    var dailyMatchPlayed: Bool {
        didSet { UserDefaults.standard.set(dailyMatchPlayed, forKey: "dailyMatchPlayed") }
    }
    var dailySentencePlayed: Bool {
        didSet { UserDefaults.standard.set(dailySentencePlayed, forKey: "dailySentencePlayed") }
    }
    private var dailyPracticeDate: String {
        didSet { UserDefaults.standard.set(dailyPracticeDate, forKey: "dailyPracticeDate") }
    }

    private let storageKey = "savedWords"

    // MARK: - 跨语言快照的显示层重翻译（非破坏性）
    //
    // 快照（SavedWord.translation）永远保留存词时的原文 —— 切回原语言零损失。
    // 当快照语言 ≠ 当前内容语言时，后台批量补一份当前语言的释义，只盖在显示层。
    // 按语言分桶持久化：relocalized_{lang} = [word_lower: RelocalizedGloss]。

    struct RelocalizedGloss: Codable {
        let translation: String
        let exampleTranslation: String?
    }

    private var relocalized: [String: RelocalizedGloss] = [:]
    private var relocalizeInFlight = false
    private var relocalizedKey: String { "relocalized_\(ContentLanguage.current.rawValue)" }

    /// 显示用释义：快照语言匹配 → 快照原文；不匹配 → 重翻译缓存，没有则暂显原文。
    func displayTranslation(_ w: SavedWord) -> String {
        guard w.language != ContentLanguage.current.rawValue else { return w.translation }
        return relocalized[w.word.lowercased()]?.translation ?? w.translation
    }

    func displayExampleTranslation(_ w: SavedWord) -> String? {
        guard w.language != ContentLanguage.current.rawValue else { return w.exampleTranslation }
        return relocalized[w.word.lowercased()]?.exampleTranslation ?? w.exampleTranslation
    }

    /// 游戏/卡片用：返回显示字段已本地化的副本（不写回存储）。
    func displayWord(_ w: SavedWord) -> SavedWord {
        guard w.language != ContentLanguage.current.rawValue,
              let gloss = relocalized[w.word.lowercased()] else { return w }
        var copy = w
        copy = SavedWord(copying: w, translation: gloss.translation,
                         exampleTranslation: gloss.exampleTranslation ?? w.exampleTranslation)
        return copy
    }

    private func loadRelocalized() {
        guard let data = UserDefaults.standard.data(forKey: relocalizedKey),
              let cached = try? JSONDecoder().decode([String: RelocalizedGloss].self, from: data) else { return }
        relocalized = cached
    }

    private func persistRelocalized() {
        if let data = try? JSONEncoder().encode(relocalized) {
            UserDefaults.standard.set(data, forKey: relocalizedKey)
        }
    }

    /// 批量补齐缺失的当前语言释义（单次 GPT 调用，≤80 词）。失败静默，下次启动重试。
    func relocalizeIfNeeded() {
        let lang = ContentLanguage.current
        guard lang != .zh else { return }  // zh 快照即原生，且 zh 用户不受影响
        let pending = words.filter {
            $0.language != lang.rawValue && relocalized[$0.word.lowercased()] == nil
        }
        guard !pending.isEmpty, !relocalizeInFlight else { return }
        relocalizeInFlight = true
        let batch = Array(pending.prefix(80))
        Task {
            defer { relocalizeInFlight = false }
            guard let result = await GlossRelocalizer.translate(batch, to: lang) else { return }
            for (word, gloss) in result {
                relocalized[word.lowercased()] = gloss
            }
            persistRelocalized()
            // 超过 80 词的下一批
            if pending.count > batch.count { relocalizeIfNeeded() }
        }
    }

    init() {
        self.dailyMatchPlayed = UserDefaults.standard.bool(forKey: "dailyMatchPlayed")
        self.dailySentencePlayed = UserDefaults.standard.bool(forKey: "dailySentencePlayed")
        self.dailyPracticeDate = UserDefaults.standard.string(forKey: "dailyPracticeDate") ?? ""
        load()
        refreshDailyPracticeIfNeeded()
        loadRelocalized()
        relocalizeIfNeeded()
    }

    func refreshDailyPracticeIfNeeded() {
        let today = DateFormatter.episodeDate.string(from: Date())
        if dailyPracticeDate != today {
            dailyMatchPlayed = false
            dailySentencePlayed = false
            dailyPracticeDate = today
        }
    }

    func markDailyMatchPlayed() {
        refreshDailyPracticeIfNeeded()
        dailyMatchPlayed = true
    }

    func markDailySentencePlayed() {
        refreshDailyPracticeIfNeeded()
        dailySentencePlayed = true
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

    /// 单条加词（来自硅谷原声字幕等场景）。已存在的同名词会去重。
    @discardableResult
    func addWord(_ vocab: VocabularyItem, sourceLabel: String? = nil) -> Bool {
        guard !words.contains(where: { $0.word.lowercased() == vocab.word.lowercased() }) else {
            return false
        }
        words.append(SavedWord(from: vocab))
        persist()
        Analytics.track(.vocabularySave, params: [
            "source": sourceLabel ?? "manual",
            "word": vocab.word,
            "total": "\(words.count)"
        ])
        return true
    }

    func saveWords(from episode: Episode) {
        let before = words.count
        for vocab in episode.vocabulary {
            guard !words.contains(where: { $0.word == vocab.word }) else { continue }
            words.append(SavedWord(from: vocab))
        }
        persist()

        let added = words.count - before
        if added > 0 {
            Analytics.track(.vocabularySave, params: [
                "episode_id": episode.id,
                "added": "\(added)",
                "total": "\(words.count)"
            ])
        }
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

    /// Detect words from user's vocabulary that appear in this episode's script
    func detectEncounteredWords(in episode: Episode) -> [SavedWord] {
        // Extract all words from the episode script
        let scriptText = episode.script.map(\.text).joined(separator: " ").lowercased()
        let scriptWords = Set(scriptText.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })

        // Also include explicitly marked recycled words
        let recycled = Set((episode.recycledWords ?? []).map { $0.lowercased() })

        var encountered: [SavedWord] = []
        for i in words.indices {
            let wordLower = words[i].word.lowercased()
            if scriptWords.contains(wordLower) || recycled.contains(wordLower) {
                // Only count if this word was saved before this episode
                words[i].encounterCount += 1
                words[i].lastEncounterDate = Date()
                encountered.append(words[i])
            }
        }

        if !encountered.isEmpty { persist() }
        return encountered
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
            // Fresh install: empty vocabulary. Words are auto-saved when the
            // user completes an episode (see LangPodApp + PlayerView).
            words = []
            return
        }
        words = saved
        migrateExampleTranslations()
    }

    /// Fill in missing exampleTranslation from latest episode data.
    /// zh only：bundle 里的例句翻译是中文，绝不能回填进其他语言的快照。
    private func migrateExampleTranslations() {
        guard ContentLanguage.current == .zh else { return }
        let allVocab = MockDataLoader.loadAllEpisodes().flatMap(\.vocabulary)
        var updated = false
        for i in words.indices {
            if words[i].exampleTranslation == nil || words[i].exampleTranslation?.isEmpty == true {
                if let match = allVocab.first(where: { $0.word == words[i].word }) {
                    if let zh = match.exampleTranslation, !zh.isEmpty {
                        words[i].exampleTranslation = zh
                        updated = true
                    }
                }
            }
        }
        if updated { persist() }
    }

}
