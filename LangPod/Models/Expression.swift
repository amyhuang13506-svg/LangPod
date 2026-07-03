import Foundation

// MARK: - 口语表达库（句型 tab 数据模型）
// 4 个大组 × 24 个功能分类，全局一套内容（国家差异写在 country_note_zh 里）。

struct ExpressionIndex: Codable {
    let groups: [ExpressionGroup]
}

struct ExpressionGroup: Codable, Identifiable, Hashable {
    let id: String        // reactions / express / skills / native
    let zh: String        // 日常反应 / 表达自己 / 会话技能 / 进阶地道
    let icon: String
    let desc: String
    let categories: [ExpressionCategoryIndexItem]
}

struct ExpressionCategoryIndexItem: Codable, Identifiable, Hashable {
    let id: String
    let zh: String
    let count: Int
    let isFree: Bool

    enum CodingKeys: String, CodingKey {
        case id, zh, count
        case isFree = "is_free"
    }
}

/// 一个分类的完整内容（expressions/{id}.json）
struct ExpressionCategory: Codable, Identifiable {
    let id: String
    let zh: String
    let groupId: String
    let groupZh: String
    let isFree: Bool
    let expressions: [Expression]

    enum CodingKeys: String, CodingKey {
        case id, zh, expressions
        case groupId = "group_id"
        case groupZh = "group_zh"
        case isFree = "is_free"
    }
}

/// 一条口语表达：表达本体 + 语感注释 + 国家差异 + 例句。按实用频率排序，无难度分级。
struct Expression: Codable, Identifiable, Hashable {
    let english: String
    let meaningZh: String
    let usageZh: String
    let countryNoteZh: String?
    let audio: String?
    let examples: [ExpressionExample]

    var id: String { english }

    enum CodingKeys: String, CodingKey {
        case english, audio, examples
        case meaningZh = "meaning_zh"
        case usageZh = "usage_zh"
        case countryNoteZh = "country_note_zh"
    }

    var hasCountryNote: Bool {
        !(countryNoteZh ?? "").isEmpty
    }
}

struct ExpressionExample: Codable, Identifiable, Hashable {
    let en: String
    let zh: String
    let audio: String?
    var id: String { en }
}
