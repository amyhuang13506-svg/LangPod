import Foundation

// MARK: - 学习计划（onboarding 生成 → 「我的」页常驻）
//
// Onboarding 第 5 屏按用户的三个答案（目标 / 级别 / 每日时长）拼一份专属计划，
// 「我的」页把同一份计划常驻展示并叠加进度。两处同源：改这里的文案两边一起变。
//
// 颜色用 hex String 而非 Color —— Models/ 全层不 import SwiftUI（与其余模型一致）。
// 视图层的 Color 扩展在 Views/LearningPlanViews.swift。

/// 学英语的目标（onboarding Q1）。rawValue 会落盘到 UserDefaults「userLearningGoal」
/// 并进 onboarding_complete 埋点 —— 不要改动。
enum LearningGoal: String, CaseIterable {
    case travel = "travel"
    case study = "study"
    case living = "overseas_living"
    case work = "work"
    case video = "video"
    case selfGrowth = "self_growth"

    var icon: String {
        switch self {
        case .travel: return "airplane"
        case .study: return "graduationcap.fill"
        case .living: return "house.fill"
        case .work: return "briefcase.fill"
        case .video: return "play.rectangle.fill"
        case .selfGrowth: return "sparkles"
        }
    }

    var label: String {
        switch self {
        case .travel: return "出国旅行"
        case .study: return "留学生活"
        case .living: return "在国外生活"
        case .work: return "工作需要"
        case .video: return "刷懂英文原声视频"
        case .selfGrowth: return "提升自己"
        }
    }

    var colorHex: String {
        switch self {
        case .travel: return "F59E0B"
        case .study: return "8B5CF6"
        case .living: return "10B981"
        case .work: return "3B82F6"
        case .video: return "FF0000"
        case .selfGrowth: return "EC4899"
        }
    }

    var bgColorHex: String {
        switch self {
        case .travel: return "FFFBEB"
        case .study: return "F5F3FF"
        case .living: return "ECFDF5"
        case .work: return "EFF6FF"
        case .video: return "FEF2F2"
        case .selfGrowth: return "FDF2F8"
        }
    }

    /// 计划页里 90 天效果预期的文案
    var outcome90d: String {
        switch self {
        case .travel: return "旅行常用场景对话不慌不忙，点单问路都能自己来"
        case .study: return "课堂内外的日常交流跟得上，社交场合敢开口"
        case .living: return "办事、就医、社交都能自己搞定，不用再靠翻译软件"
        case .work: return "职场高频表达张口就来，开会邮件不再卡壳"
        case .video: return "不开字幕也能跟上英文原声播客和视频"
        case .selfGrowth: return "英语听力形成条件反射，把'学过'变成'用得上'"
        }
    }
}

struct LearningPlan {
    let level: PodcastLevel
    /// nil = onboarding v2 之前的老用户（没存过目标）→ 全部走默认文案分支
    let goal: LearningGoal?
    let dailyMinutes: Int

    static let defaultMinutes = 15
    /// 里程碑天数，与「我的」页进度条同源
    static let milestoneDays = [7, 21, 30, 90]

    // MARK: - 构造

    init(level: PodcastLevel, goal: LearningGoal?, dailyMinutes: Int) {
        self.level = level
        self.goal = goal
        self.dailyMinutes = dailyMinutes
    }

    /// 从 onboarding 落盘的答案还原（「我的」页用）。
    /// level 由调用方传入 dataStore.selectedLevel —— 用户在设置里改级别，计划跟着变。
    static func persisted(level: PodcastLevel) -> LearningPlan {
        let goalRaw = UserDefaults.standard.string(forKey: "userLearningGoal") ?? ""
        let minutes = UserDefaults.standard.integer(forKey: "dailyGoalMinutes")
        return LearningPlan(
            level: level,
            goal: LearningGoal(rawValue: goalRaw),
            dailyMinutes: minutes > 0 ? minutes : defaultMinutes
        )
    }

    // MARK: - 展示

    /// 计划摘要 chips：级别 · 每天 N 分钟 · 目标（老用户无目标时只有前两个）
    var chips: [String] {
        var result = [level.tabName, "每天 \(dailyMinutes) 分钟"]
        if let goal { result.append(goal.label) }
        return result
    }

    struct Item: Identifiable {
        let icon: String
        let colorHex: String
        let title: String
        let detail: String
        var id: String { title }
    }

    struct Milestone: Identifiable {
        let day: Int
        let title: String
        let desc: String
        var id: Int { day }
        var dayLabel: String { "第 \(day) 天" }
    }

    /// 场景课堂一行的说明，跟随用户目标侧重
    private var lessonDetailText: String {
        switch goal {
        case .travel: return "机场、酒店、餐厅，旅行场景课优先安排"
        case .study: return "校园、社交、日常琐事，留学场景课优先安排"
        case .living: return "租房、看病、办事，海外生活场景课优先安排"
        case .work: return "职场沟通高频场景课优先安排"
        default: return "点单、租房、看病，按真实场景分类的实用课"
        }
    }

    /// 每天做什么 —— 按目标和时长拼装，不是人人相同
    var items: [Item] {
        var items: [Item] = [
            Item(icon: "headphones", colorHex: "3B82F6",
                 title: "每天 1 集\(level.tabName)播客",
                 detail: "英语 ×3 → 中文 ×1 → 英语 ×1，重复成本能"),
            Item(icon: "text.bubble.fill", colorHex: "F59E0B",
                 title: "高频句型讲解",
                 detail: "从当天播客拆出来，讲透场景和语感"),
        ]

        let youtubeItem = Item(icon: "play.rectangle.fill", colorHex: "FF0000",
                               title: "YouTube 原声播客",
                               detail: "中英双语字幕，检验真实语速听力")
        let lessonItem = Item(icon: "graduationcap.fill", colorHex: "10B981",
                              title: "出国场景课堂",
                              detail: lessonDetailText)

        // 目标决定第三块的侧重；时间充裕（≥20 分钟）则两块都排进来
        if goal == .video {
            items.append(youtubeItem)
            if dailyMinutes >= 20 { items.append(lessonItem) }
        } else {
            items.append(lessonItem)
            if dailyMinutes >= 20 { items.append(youtubeItem) }
        }

        items.append(Item(icon: "flame.fill", colorHex: "F97316",
                          title: "每日任务打卡",
                          detail: "词汇 + 句型练习，连续打卡不断档"))
        return items
    }

    /// 效果预期时间线。前三条固定，第 90 天跟随目标。
    var milestones: [Milestone] {
        [
            Milestone(day: 7, title: "耳朵热起来",
                      desc: "适应 5 遍精听的节奏，能从整句里抓到关键词，英语不再是一片模糊的背景音"),
            Milestone(day: 21, title: "句型上口",
                      desc: "高频句型开始形成条件反射，听到熟悉的场景，能直接反应出该说的那句话"),
            Milestone(day: 30, title: "跟上对话",
                      desc: "日常对话不用暂停回放也能跟上大意，敢在真实场景里开口回应"),
            Milestone(day: 90, title: "真的用得上",
                      desc: goal?.outcome90d ?? "英语听力形成条件反射，把'学过'变成'用得上'"),
        ]
    }

    // MARK: - 进度（「我的」页用；onboarding 侧恒为 0）

    /// 下一个未达成的里程碑；全部达成返回 nil
    func nextMilestone(activeDays: Int) -> Milestone? {
        milestones.first { $0.day > activeDays }
    }
}
