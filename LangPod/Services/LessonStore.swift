import Foundation
import SwiftUI

/// 词汇 tab 顶部大区块：日常词汇（主题图解）/ 生活场景（国家维度）
enum LessonSection: String {
    case daily
    case scene
}

/// 词汇小课堂数据层。生活场景区国家是平级分类（随时切换）；
/// 日常词汇区是主题图解课，走 OSS 伪国家目录 lessons/daily/（复用同一套接口与模型）。
@Observable
class LessonStore {
    var countries: [LessonCountry] = LessonCountry.defaults
    var lessons: [SceneLessonIndexItem] = [] {
        didSet { freeSceneIds = Self.computeFreeIds(lessons) }
    }
    var isLoadingIndex = false

    // MARK: - 免费闸门（每个分类前 N 课免费）

    /// 每个小分类免费开放的课数 —— 日常词汇 / 生活场景 通用。
    /// 与句型的 ExpressionFreeGate.freePerCategory 对齐。
    static let freePerCategory = 2

    /// 免费课 id（分类内按 id 稳定排序取前 freePerCategory 个）。
    /// 随 lessons / themeLessons 重算：切国家 → 重算当前国家的免费集。
    private(set) var freeSceneIds: Set<String> = []
    private(set) var freeThemeIds: Set<String> = []

    /// 分类内取「最早的 N 课」免费。按 date 升序（date = 内容创建日，pipeline 落盘时必填）：
    /// 新课 date 更晚 → 永远排在后面 → 不会把已免费的课挤成锁。内容在持续生成，
    /// 闸门必须对「新增」稳定，否则用户昨天能看的课今天变锁（像 bug）。
    /// 免费占比随分类变大自然稀释。每日课不占名额（走当天免费逻辑）。
    private static func computeFreeIds(_ items: [SceneLessonIndexItem]) -> Set<String> {
        var result: Set<String> = []
        for (_, list) in Dictionary(grouping: items.filter { !$0.isDaily }, by: \.category) {
            let ranked = list.sorted { a, b in
                a.date == b.date ? a.id < b.id : a.date < b.date
            }
            result.formUnion(ranked.prefix(freePerCategory).map(\.id))
        }
        return result
    }

    // MARK: - 日常词汇（主题图解）

    /// 当前所在大区块，记住上次停留
    var section: LessonSection {
        didSet { UserDefaults.standard.set(section.rawValue, forKey: "vocabSection") }
    }

    var themeLessons: [SceneLessonIndexItem] = [] {
        didSet { freeThemeIds = Self.computeFreeIds(themeLessons) }
    }
    var isLoadingThemeIndex = false
    private var loadedTheme = false

    /// 日常词汇选中的主题大类（不持久化，默认第一个有内容的大类）
    var selectedThemeCategory: String = ""

    /// 主题大类固定产品顺序（对应 pipeline theme_catalog.THEME_CATEGORIES 的 8 大类）。
    /// 目录外的新大类由 themeCategories 兜底追加，服务端加类不用发版。
    static let themeCategoryOrder = [
        "grocery",    // 食物
        "home",       // 家居
        "body",       // 身体与健康
        "clothing",   // 穿着
        "transport",  // 出行与城市
        "nature",     // 自然与动物
        "work",       // 工作与休闲
        "basics",     // 基础概念
    ]

    /// 伪国家 daily 的元数据：详情页发音口音固定美音。
    /// ⚠️ 不进 countries.json（老版本会把它当国家渲染），App 端直接引用这个常量。
    static let themeCountry = LessonCountry(
        id: "daily", nameZh: "日常词汇", flag: "📖", accent: "en-US", lessonCount: 0
    )

    /// 全局今日每日课（跨国家，独立于所选国家），来自 lessons/today.json
    var globalToday: SceneLessonToday?
    private var loadedToday = false

    /// 上次浏览的国家（默认美国）。非锁定，只是下次默认停留。
    var selectedCountry: String {
        didSet {
            UserDefaults.standard.set(selectedCountry, forKey: "lessonCountry")
            loadIndex(for: selectedCountry)
        }
    }

    /// 已学完的课堂（滚动到底部记录），驱动 ✓ 角标
    private(set) var completedLessonIds: Set<String>

    /// 详情内存缓存（本次会话）
    private var detailCache: [String: SceneLesson] = [:]
    private var loadedCountries: Set<String> = []

    init() {
        self.selectedCountry = UserDefaults.standard.string(forKey: "lessonCountry") ?? "us"
        self.completedLessonIds = Set(UserDefaults.standard.stringArray(forKey: "completedLessonIds") ?? [])
        self.section = LessonSection(rawValue: UserDefaults.standard.string(forKey: "vocabSection") ?? "") ?? .scene
    }

    // MARK: - Loading

    /// 首次进入：缓存优先展示 + 后台拉取（仿 DataStore 启动模式）
    func loadIfNeeded() {
        guard lessons.isEmpty && !isLoadingIndex else { return }
        loadIndex(for: selectedCountry)
        loadTodayIfNeeded()
        Task {
            let remote = await APIService.shared.fetchLessonCountries()
            if !remote.isEmpty { self.countries = remote }
        }
    }

    /// 拉全局今日课（每次会话一次）。跨国家置顶展示用。
    func loadTodayIfNeeded() {
        guard !loadedToday else { return }
        loadedToday = true
        Task {
            if let t = await APIService.shared.fetchTodayLesson() { self.globalToday = t }
        }
    }

    private func loadIndex(for country: String) {
        // 1. 缓存立即显示
        if let cached = APIService.shared.loadCachedLessonIndexSync(country: country) {
            lessons = cached
        } else if loadedCountries.contains(country) {
            // 拉过但确实没内容
        } else {
            lessons = []
        }
        // 2. 后台拉最新
        isLoadingIndex = true
        Task {
            let remote = await APIService.shared.fetchLessonIndex(country: country)
            // 用户可能在请求期间又切了国家，只应用当前选中国家的结果
            if country == self.selectedCountry {
                if !remote.isEmpty { self.lessons = remote }
                self.isLoadingIndex = false
            }
            self.loadedCountries.insert(country)
        }
    }

    func lessonDetail(country: String, id: String) async -> SceneLesson? {
        if let cached = detailCache[id] { return cached }
        let lesson = await APIService.shared.fetchLessonDetail(country: country, id: id)
        if let lesson { detailCache[id] = lesson }
        return lesson
    }

    /// 日常词汇主题课 index（lessons/daily/，缓存优先 + 后台拉取，与国家 index 同模式）
    func loadThemeIfNeeded() {
        guard !loadedTheme else { return }
        loadedTheme = true
        if let cached = APIService.shared.loadCachedLessonIndexSync(country: LessonSection.daily.rawValue) {
            themeLessons = cached
            ensureThemeCategorySelection()
        }
        isLoadingThemeIndex = true
        Task {
            let remote = await APIService.shared.fetchLessonIndex(country: LessonSection.daily.rawValue)
            if !remote.isEmpty {
                self.themeLessons = remote
                self.ensureThemeCategorySelection()
            }
            self.isLoadingThemeIndex = false
        }
    }

    // MARK: - Derived

    var currentCountry: LessonCountry {
        countries.first { $0.id == selectedCountry }
            ?? LessonCountry.defaults.first { $0.id == selectedCountry }
            ?? LessonCountry.defaults[0]
    }

    /// 今日新场景（每天全局一个，跨国家置顶展示）。在当前国家 index 里找；
    /// 每日课堂轮换国家产出，所以也在其它国家缓存里找不到时以当前国家为准。
    var todayLesson: SceneLessonIndexItem? {
        lessons.first { $0.isDaily && LessonAccessGate.isToday($0.date) }
    }

    /// 全局今日课卡（跨国家置顶）：仅当 today.json 日期是今天才展示；带该课自己的国家（含口音）。
    var todayCard: (item: SceneLessonIndexItem, country: LessonCountry)? {
        guard let t = globalToday, LessonAccessGate.isToday(t.date) else { return nil }
        let country = countries.first { $0.id == t.country }
            ?? LessonCountry.defaults.first { $0.id == t.country }
            ?? currentCountry
        return (t.lesson, country)
    }

    /// 该课堂是否免费（每日课不算，它走当天免费逻辑）。
    /// 客户端按「每个分类前 freePerCategory 课」派生，不再读内容里的 is_free 标记
    /// —— 免费范围跟着内容自动扩展，pipeline 加课不用改标记也不用发版。
    func isFreeSample(_ item: SceneLessonIndexItem) -> Bool {
        if item.isDaily { return false }
        return freeSceneIds.contains(item.id) || freeThemeIds.contains(item.id)
    }

    /// 该课是否锁定（Pro / 免费样本 / 今日课当天免费 → 不锁）。
    /// 新付费模型：锁定课仍可进详情看内容，只在动作按钮处拦截 —— 这个判定供
    /// LessonDetailView 决定是否显示标题锁标 + 拦动作，VocabularyView 不再用它挡入口。
    func isLocked(_ item: SceneLessonIndexItem, isPro: Bool) -> Bool {
        if isPro { return false }
        if item.isDaily && LessonAccessGate.isToday(item.date) { return false }
        return !isFreeSample(item)
    }

    /// 每日任务「学一篇词汇小课堂」的目标：今日课优先（当天免费、天天新），
    /// 没有今日课时按日在免费课池里轮换 —— 保证任务每天都有内容可给。
    var dailyTaskLesson: (item: SceneLessonIndexItem, country: LessonCountry)? {
        if let today = todayCard { return today }
        var pool: [(item: SceneLessonIndexItem, country: LessonCountry)] = []
        pool += themeLessons.filter { freeThemeIds.contains($0.id) }.map { ($0, Self.themeCountry) }
        pool += lessons.filter { freeSceneIds.contains($0.id) }.map { ($0, currentCountry) }
        guard !pool.isEmpty else { return nil }
        let sorted = pool.sorted { $0.item.id < $1.item.id }
        let days = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return sorted[days % sorted.count]
    }

    // MARK: - 日常词汇派生

    /// 主题大类 chips（id + 中文名）：从 index 内容派生，按固定产品顺序；
    /// 目录之外的新大类兜底追加，pipeline 加类不用发版。
    var themeCategories: [(id: String, zh: String)] {
        var zhById: [String: String] = [:]
        for lesson in themeLessons where zhById[lesson.category] == nil {
            zhById[lesson.category] = lesson.categoryZh
        }
        var result: [(id: String, zh: String)] = []
        for id in Self.themeCategoryOrder {
            if let zh = zhById[id] { result.append((id, zh)) }
        }
        let known = Set(Self.themeCategoryOrder)
        for (id, zh) in zhById.sorted(by: { $0.value < $1.value }) where !known.contains(id) {
            result.append((id, zh))
        }
        return result
    }

    private func ensureThemeCategorySelection() {
        if selectedThemeCategory.isEmpty
            || !themeLessons.contains(where: { $0.category == selectedThemeCategory }) {
            selectedThemeCategory = themeCategories.first?.id ?? ""
        }
    }

    /// 当前主题大类下的课：免费在前，其余按当日稳定随机（与场景分类同思路）
    var themeLessonsInSelectedCategory: [SceneLessonIndexItem] {
        let seed = Self.dailyShuffleSeed()
        return themeLessons.filter { $0.category == selectedThemeCategory }
            .sorted { a, b in
                let fa = freeThemeIds.contains(a.id), fb = freeThemeIds.contains(b.id)
                if fa != fb { return fa }
                return Self.stableHash("\(a.id)|\(seed)") < Self.stableHash("\(b.id)|\(seed)")
            }
    }

    /// 分类固定展示顺序（对应 lesson_catalog.CATEGORIES 的产品顺序），
    /// 不随课程日期/index 顺序变——避免新增内容（如新加的 dentist）把某分类顶到最前。
    static let categoryOrder = ["arrival", "food", "health", "settling", "social"]

    /// 按分类分组（分类按 categoryOrder 固定顺序）。含全部课堂，包括每日课：
    /// 每日场景（今日的 + 往期的）都落在各自对应分类里，不单开「往期每日场景」区。
    /// 分类内排序：今日每日课(NEW) → 免费样本 → 其余按当日随机（当天稳定、每天变）。
    var byCategory: [(category: String, lessons: [SceneLessonIndexItem])] {
        let seed = Self.dailyShuffleSeed()
        let order = Self.categoryOrder

        var groups: [String: [SceneLessonIndexItem]] = [:]   // key = categoryZh
        var enKey: [String: String] = [:]                    // categoryZh -> category(en)
        for lesson in lessons {
            groups[lesson.categoryZh, default: []].append(lesson)
            enKey[lesson.categoryZh] = lesson.category
        }
        // 分类内排序优先级：今日每日课 0 → 免费样本 1 → 其它 2
        func rank(_ i: SceneLessonIndexItem) -> Int {
            if i.isDaily && LessonAccessGate.isToday(i.date) { return 0 }
            if isFreeSample(i) { return 1 }
            return 2
        }
        return groups.keys.sorted { a, b in
            let ia = order.firstIndex(of: enKey[a] ?? "") ?? order.count
            let ib = order.firstIndex(of: enKey[b] ?? "") ?? order.count
            if ia != ib { return ia < ib }
            return a < b
        }.map { cat in
            let items = (groups[cat] ?? []).sorted { a, b in
                let ra = rank(a), rb = rank(b)
                if ra != rb { return ra < rb }
                return Self.stableHash("\(a.id)|\(seed)") < Self.stableHash("\(b.id)|\(seed)")
            }
            return (cat, items)
        }
    }

    /// 当日随机种子：本地时区 yyyy-MM-dd（当天所有排序稳定，跨天变化）
    static func dailyShuffleSeed() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: Date())
    }

    /// 确定性哈希（FNV-1a）：不用 Swift 随机化的 hashValue，保证跨启动/跨设备一致
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h ^= UInt64(b); h = h &* 1099511628211 }
        return h
    }

    /// 往期每日场景（已过期，Pro）
    var pastDailyLessons: [SceneLessonIndexItem] {
        lessons.filter { $0.isDaily && !LessonAccessGate.isToday($0.date) }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Completion

    func markCompleted(_ lessonId: String) {
        guard !completedLessonIds.contains(lessonId) else { return }
        completedLessonIds.insert(lessonId)
        UserDefaults.standard.set(Array(completedLessonIds), forKey: "completedLessonIds")
        // 每日任务：课堂学完（guard 已按 lessonId 去重，不会重复 fire）
        NotificationCenter.default.post(
            name: .taskEventLessonCompleted,
            object: nil,
            userInfo: ["lesson_id": lessonId]
        )
    }

    func isCompleted(_ lessonId: String) -> Bool {
        completedLessonIds.contains(lessonId)
    }
}
