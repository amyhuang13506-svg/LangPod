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
    /// 分类封面插画（gpt-image-1 生成，主页网格卡 + 详情页顶部共用）
    var cover: String?

    enum CodingKeys: String, CodingKey {
        case id, zh, count, cover
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

/// 一条口语表达：表达本体 + 语感注释 + 国家差异 + 例句 + 场景示例。
/// 按实用频率排序，无难度分级。
struct Expression: Codable, Identifiable, Hashable {
    let english: String
    let meaningZh: String
    let usageZh: String
    let countryNoteZh: String?
    let audio: String?
    /// 卡片封面插画（按句意生成的视觉隐喻图，区别于详情页的对话场景图）
    var cover: String?
    let examples: [ExpressionExample]
    let scene: ExpressionScene?

    var id: String { english }

    enum CodingKeys: String, CodingKey {
        case english, audio, cover, examples, scene
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

/// 场景示例：具体场景描述 + 一来一回的迷你对话（其中一句用到本表达）
struct ExpressionScene: Codable, Hashable {
    let setupZh: String
    let dialogue: [ExpressionDialogueLine]
    /// 场景插画（A 左 B 右、上方留白，App 在图上叠加对话气泡）
    var image: String?

    enum CodingKeys: String, CodingKey {
        case dialogue, image
        case setupZh = "setup_zh"
    }
}

struct ExpressionDialogueLine: Codable, Identifiable, Hashable {
    let speaker: String   // "A" / "B"
    let en: String
    let zh: String
    let audio: String?
    var id: String { speaker + en }
}
