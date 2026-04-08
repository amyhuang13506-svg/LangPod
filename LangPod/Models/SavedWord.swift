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
    let translationZh: String
    let example: String
    var exampleZh: String?
    var masteryLevel: MasteryLevel
    var lastPracticeDate: Date
    var matchCorrectCount: Int      // 配对答对次数
    var sentenceCorrectCount: Int   // 造句答对次数
    var savedDate: Date             // 保存时间

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

    init(from vocab: VocabularyItem) {
        self.word = vocab.word
        self.phonetic = vocab.phonetic
        self.translationZh = vocab.translationZh
        self.example = vocab.example
        self.exampleZh = vocab.exampleZh
        self.masteryLevel = .heard
        self.lastPracticeDate = Date()
        self.matchCorrectCount = 0
        self.sentenceCorrectCount = 0
        self.savedDate = Date()
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
