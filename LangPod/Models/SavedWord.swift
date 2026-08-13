import Foundation

/// Word status based on user actions (not time decay)
enum MemoryState: String, Codable, CaseIterable {
    case strong     // 已掌握: 配对 >= 3 次 或 造句 >= 1 次
    case fading     // 复习中: 配对 1-2 次
    case forgetting // 新词: 配对 0 次

    var label: String {
        switch self {
        case .strong: "已掌握"
        case .fading: "复习中"
        case .forgetting: "新词"
        }
    }

    var color: String {
        switch self {
        case .strong: "16A34A"
        case .fading: "D97706"
        case .forgetting: "3B82F6"
        }
    }

    var bgColor: String {
        switch self {
        case .strong: "DCFCE7"
        case .fading: "FEF3C7"
        case .forgetting: "EFF6FF"
        }
    }
}

/// Mastery depth (Feynman levels - simplified)
enum MasteryLevel: Int, Codable, CaseIterable, Comparable {
    case heard = 0      // 听懂 — 播客里听到
    case recognized = 1 // 认出 — 配对答对
    case canUse = 2     // 会用 — 造句答对
    case canTeach = 3   // 能教 — 保留备用

    var label: String {
        switch self {
        case .heard: "听懂"
        case .recognized: "认出"
        case .canUse: "会用"
        case .canTeach: "能教"
        }
    }

    var icon: String {
        switch self {
        case .heard: "👂"
        case .recognized: "👁"
        case .canUse: "✍️"
        case .canTeach: "🎓"
        }
    }

    static func < (lhs: MasteryLevel, rhs: MasteryLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct SavedWord: Codable, Identifiable {
    let word: String
    let phonetic: String
    let translation: String
    let example: String
    var exampleTranslation: String?
    /// 快照语言（ContentLanguage.rawValue）。老数据无此字段 → 解码补 "zh"。
    /// 换系统语言后老快照按原语言显示（V1 不迁移不隐藏）。
    var language: String
    var masteryLevel: MasteryLevel
    var lastPracticeDate: Date
    var matchCorrectCount: Int      // 配对答对次数
    var sentenceCorrectCount: Int   // 造句答对次数
    var savedDate: Date             // 保存时间
    var encounterCount: Int         // 在不同集中听到的总次数
    var lastEncounterDate: Date?    // 最近一次在新集中碰到的日期

    var id: String { word }

    // Legacy compatibility
    var reviewCount: Int { matchCorrectCount + sentenceCorrectCount }
    var lastReviewDate: Date { lastPracticeDate }

    /// Status based on user actions
    var memoryState: MemoryState {
        // 已掌握 but 30 days no practice → 退回复习中
        if matchCorrectCount >= 3 || sentenceCorrectCount >= 1 {
            let daysSincePractice = Date().timeIntervalSince(lastPracticeDate) / 86400
            if daysSincePractice > 30 {
                return .fading
            }
            return .strong
        }

        // 复习中: 做过配对但还不够
        if matchCorrectCount >= 1 {
            return .fading
        }

        // 新词: 从未做过配对
        return .forgetting
    }

    /// 老 UserDefaults 数据的字段名（rename 前的属性名，JSONEncoder 直接用属性名做 key）。
    private enum LegacyKeys: String, CodingKey {
        case translationZh, exampleZh
    }

    // Custom decoder for backward compatibility
    // (old data without encounterCount / language, and pre-rename zh key names)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        word = try container.decode(String.self, forKey: .word)
        phonetic = try container.decode(String.self, forKey: .phonetic)
        translation = try container.decodeIfPresent(String.self, forKey: .translation)
            ?? legacy.decode(String.self, forKey: .translationZh)
        example = try container.decode(String.self, forKey: .example)
        exampleTranslation = try container.decodeIfPresent(String.self, forKey: .exampleTranslation)
            ?? legacy.decodeIfPresent(String.self, forKey: .exampleZh)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? ContentLanguage.zh.rawValue
        masteryLevel = try container.decode(MasteryLevel.self, forKey: .masteryLevel)
        lastPracticeDate = try container.decode(Date.self, forKey: .lastPracticeDate)
        matchCorrectCount = try container.decode(Int.self, forKey: .matchCorrectCount)
        sentenceCorrectCount = try container.decode(Int.self, forKey: .sentenceCorrectCount)
        savedDate = try container.decode(Date.self, forKey: .savedDate)
        encounterCount = try container.decodeIfPresent(Int.self, forKey: .encounterCount) ?? 1
        lastEncounterDate = try container.decodeIfPresent(Date.self, forKey: .lastEncounterDate)
    }

    init(from vocab: VocabularyItem) {
        self.word = vocab.word
        self.phonetic = vocab.phonetic
        self.translation = vocab.translation
        self.example = vocab.example
        self.exampleTranslation = vocab.exampleTranslation
        self.language = ContentLanguage.current.rawValue
        self.masteryLevel = .heard
        self.lastPracticeDate = Date()
        self.matchCorrectCount = 0
        self.sentenceCorrectCount = 0
        self.savedDate = Date()
        self.encounterCount = 1
        self.lastEncounterDate = nil
    }

    mutating func recordMatchCorrect() {
        matchCorrectCount += 1
        lastPracticeDate = Date()
        if matchCorrectCount >= 1 && masteryLevel < .recognized {
            masteryLevel = .recognized
        }
    }

    mutating func recordSentenceCorrect() {
        sentenceCorrectCount += 1
        lastPracticeDate = Date()
        if masteryLevel < .canUse {
            masteryLevel = .canUse
        }
    }

    // Keep backward compatibility
    mutating func markReviewed() {
        recordMatchCorrect()
    }
}
