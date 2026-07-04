import Foundation

/// 「我的句子」收藏项。与 SavedWord 的区别：带使用场景（scene），
/// 支撑场景模拟练习（给场景选句子）。
struct SavedSentence: Codable, Identifiable, Hashable {
    let english: String
    let chinese: String
    /// 使用场景：小课堂句子 = 课堂标题（"在 CVS 买非处方药"）；
    /// 句型例句 = pattern.scene（"日常请求 / 寻求许可"）
    let scene: String
    let source: String          // "lesson" | "pattern"
    let sourceLabel: String     // 课堂名或句型 template（展示"来自：xxx"）
    /// 发音：小课堂句子 = 独立 mp3 URL；句型例句 = 讲解音频 URL + 截段区间
    let audioUrl: String?
    let audioStart: Double?
    let audioEnd: Double?
    var savedDate: Date
    /// 连词成句答对次数（驱动 已掌握/复习中/新句 分类，仿 SavedWord.matchCorrectCount）
    var practiceCorrectCount: Int = 0
    var lastPracticeDate: Date? = nil

    var id: String { english }

    /// 连词成句可用（≤12 个单词）
    var isPracticeable: Bool {
        english.split(separator: " ").count <= 12
    }

    /// 掌握状态（仿 SavedWord.memoryState）：连词成句答对 ≥2 → 已掌握（30 天没练退回复习中）；
    /// =1 → 复习中；0 → 新句。复用 MemoryState（forgetting 在句子语境展示为「新句」）。
    var memoryState: MemoryState {
        if practiceCorrectCount >= 2 {
            if let last = lastPracticeDate, Date().timeIntervalSince(last) / 86400 > 30 {
                return .fading
            }
            return .strong
        }
        if practiceCorrectCount >= 1 { return .fading }
        return .forgetting
    }

    mutating func recordPracticeCorrect() {
        practiceCorrectCount += 1
        lastPracticeDate = Date()
    }
}

// 自定义 Codable 放在 extension 里，保留 memberwise init（3 个收藏点在用）。
// decodeIfPresent 兼容旧数据（没有 practiceCorrectCount / lastPracticeDate 字段）。
extension SavedSentence {
    enum CodingKeys: String, CodingKey {
        case english, chinese, scene, source, sourceLabel
        case audioUrl, audioStart, audioEnd, savedDate
        case practiceCorrectCount, lastPracticeDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        english = try c.decode(String.self, forKey: .english)
        chinese = try c.decode(String.self, forKey: .chinese)
        scene = try c.decode(String.self, forKey: .scene)
        source = try c.decode(String.self, forKey: .source)
        sourceLabel = try c.decode(String.self, forKey: .sourceLabel)
        audioUrl = try c.decodeIfPresent(String.self, forKey: .audioUrl)
        audioStart = try c.decodeIfPresent(Double.self, forKey: .audioStart)
        audioEnd = try c.decodeIfPresent(Double.self, forKey: .audioEnd)
        savedDate = try c.decode(Date.self, forKey: .savedDate)
        practiceCorrectCount = try c.decodeIfPresent(Int.self, forKey: .practiceCorrectCount) ?? 0
        lastPracticeDate = try c.decodeIfPresent(Date.self, forKey: .lastPracticeDate)
    }
}
