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

    var id: String { english }

    /// 连词成句可用（≤12 个单词）
    var isPracticeable: Bool {
        english.split(separator: " ").count <= 12
    }
}
