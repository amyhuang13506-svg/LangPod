import Foundation
import SwiftUI

/// 词汇小课堂数据层。国家是平级分类（随时切换），@AppStorage 只记住上次看的国家。
@Observable
class LessonStore {
    var countries: [LessonCountry] = LessonCountry.defaults
    var lessons: [SceneLessonIndexItem] = []
    var isLoadingIndex = false

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
    }

    // MARK: - Loading

    /// 首次进入：缓存优先展示 + 后台拉取（仿 DataStore 启动模式）
    func loadIfNeeded() {
        guard lessons.isEmpty && !isLoadingIndex else { return }
        loadIndex(for: selectedCountry)
        Task {
            let remote = await APIService.shared.fetchLessonCountries()
            if !remote.isEmpty { self.countries = remote }
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

    // MARK: - 免费闸门
    // 只有「第一个国家（默认美国）」的「第一课」免费体验，其余全部需订阅。

    /// 第一个国家 = 国家 chips 里的第一个（默认美国）
    var freeCountryId: String { countries.first?.id ?? "us" }

    /// 免费样本课堂 id：仅当停留在第一个国家时，取「稳定顺序」的第一课（不含每日课）。
    /// 用稳定分组而非每日随机分组，保证免费课固定不漂移。
    var freeSampleLessonId: String? {
        guard selectedCountry == freeCountryId else { return nil }
        return stableByCategory.first?.lessons.first?.id ?? lessons.first { !$0.isDaily }?.id
    }

    /// 该课堂是否为免费样本
    func isFreeSample(_ id: String) -> Bool {
        id == freeSampleLessonId
    }

    /// 稳定分组（服务器 index 顺序，不随每日随机变），仅用于判定免费样本
    private var stableByCategory: [(category: String, lessons: [SceneLessonIndexItem])] {
        var order: [String] = []
        var groups: [String: [SceneLessonIndexItem]] = [:]
        for lesson in lessons where !lesson.isDaily {
            if groups[lesson.categoryZh] == nil { order.append(lesson.categoryZh) }
            groups[lesson.categoryZh, default: []].append(lesson)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// 按分类分组：分类顺序稳定，分类内课程「按当日随机」排序（当天稳定、每天变），
    /// 让用户每天切分类都看到不一样的排布。不含今日课堂和往期每日。
    var byCategory: [(category: String, lessons: [SceneLessonIndexItem])] {
        let seed = Self.dailyShuffleSeed()
        return stableByCategory.map { group in
            let shuffled = group.lessons.sorted {
                Self.stableHash("\($0.id)|\(seed)") < Self.stableHash("\($1.id)|\(seed)")
            }
            return (group.category, shuffled)
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
