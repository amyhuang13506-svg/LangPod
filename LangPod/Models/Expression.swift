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
    /// 每日新增的「今日句型」标记（pipeline cron 产出，当天免费 + NEW 角标）
    var isDaily: Bool?
    var date: String?

    var id: String { english }

    enum CodingKeys: String, CodingKey {
        case english, audio, cover, examples, scene, date
        case meaningZh = "meaning_zh"
        case usageZh = "usage_zh"
        case countryNoteZh = "country_note_zh"
        case isDaily = "is_daily"
    }

    var hasCountryNote: Bool {
        !(countryNoteZh ?? "").isEmpty
    }

    /// 是否为「当天」的每日句型（当天免费 + 显示 NEW 角标）
    var isDailyToday: Bool {
        (isDaily ?? false) && ExpressionAccessGate.isToday(date)
    }
}

/// 今日句型指针（expressions/today.json）。每天由 pipeline cron 轮换分类新生成一条后重写，
/// App 顶部固定展示当天这一条，独立于当前所选大组。
struct ExpressionToday: Codable {
    let date: String
    let groupId: String
    let groupZh: String
    let categoryId: String
    let categoryZh: String
    let expression: Expression

    enum CodingKeys: String, CodingKey {
        case date, expression
        case groupId = "group_id"
        case groupZh = "group_zh"
        case categoryId = "category_id"
        case categoryZh = "category_zh"
    }
}

/// 句型付费门控：Pro 全解锁；当天的每日句型免费；免费分类首条免费；其余 Pro。
enum ExpressionAccessGate {
    /// 本地时区判断（与 LessonAccessGate 同思路）
    static func isToday(_ dateString: String?) -> Bool {
        guard let dateString, !dateString.isEmpty else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date()) == String(dateString.prefix(10))
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
