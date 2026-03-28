import Foundation

/// Memory state based on forgetting curve
enum MemoryState: String, Codable, CaseIterable {
    case strong    // > 80% retention
    case fading    // 40-80%
    case forgetting // < 40%

    var label: String {
        switch self {
        case .strong: "已掌握"
        case .fading: "复习中"
        case .forgetting: "即将遗忘"
        }
    }

    var color: String {
        switch self {
        case .strong: "16A34A"
        case .fading: "D97706"
        case .forgetting: "EF4444"
        }
    }

    var bgColor: String {
        switch self {
        case .strong: "DCFCE7"
        case .fading: "FEF3C7"
        case .forgetting: "FEE2E2"
        }
    }
}

/// Mastery depth (Feynman 4 levels)
enum MasteryLevel: Int, Codable, CaseIterable, Comparable {
    case heard = 0     // 听懂
    case recognized = 1 // 认出
    case canUse = 2    // 会用
    case canTeach = 3  // 能教

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
    var masteryLevel: MasteryLevel
    var lastReviewDate: Date
    var reviewCount: Int
    var nextReviewDate: Date

    var id: String { word }

    /// Compute memory state based on time since last review
    var memoryState: MemoryState {
        let hoursSinceReview = Date().timeIntervalSince(lastReviewDate) / 3600
        let retentionHours = retentionWindow
        let ratio = max(0, 1.0 - hoursSinceReview / retentionHours)

        if ratio > 0.8 { return .strong }
        if ratio > 0.4 { return .fading }
        return .forgetting
    }

    /// Retention window grows with review count (spaced repetition)
    private var retentionHours: Double {
        switch reviewCount {
        case 0: 4        // 4 hours
        case 1: 24       // 1 day
        case 2: 72       // 3 days
        case 3: 168      // 1 week
        case 4: 336      // 2 weeks
        default: 720     // 1 month
        }
    }

    private var retentionWindow: Double {
        retentionHours * 1.5  // buffer for gradual decay
    }

    init(from vocab: VocabularyItem) {
        self.word = vocab.word
        self.phonetic = vocab.phonetic
        self.translationZh = vocab.translationZh
        self.example = vocab.example
        self.masteryLevel = .heard
        self.lastReviewDate = Date()
        self.reviewCount = 0
        self.nextReviewDate = Date().addingTimeInterval(4 * 3600)
    }

    mutating func markReviewed() {
        reviewCount += 1
        lastReviewDate = Date()
        let hours = retentionHours
        nextReviewDate = Date().addingTimeInterval(hours * 3600)
    }
}
