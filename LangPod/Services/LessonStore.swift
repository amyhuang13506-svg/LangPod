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

    /// 免费样本课堂 id：仅当停留在第一个国家时，取展示顺序的第一课（不含每日课）
    var freeSampleLessonId: String? {
        guard selectedCountry == freeCountryId else { return nil }
        return byCategory.first?.lessons.first?.id ?? lessons.first { !$0.isDaily }?.id
    }

    /// 该课堂是否为免费样本
    func isFreeSample(_ id: String) -> Bool {
        id == freeSampleLessonId
    }

    /// 按分类分组（保持首次出现顺序），不含今日课堂和往期每日
    var byCategory: [(category: String, lessons: [SceneLessonIndexItem])] {
        var order: [String] = []
        var groups: [String: [SceneLessonIndexItem]] = [:]
        for lesson in lessons where !lesson.isDaily {
            if groups[lesson.categoryZh] == nil { order.append(lesson.categoryZh) }
            groups[lesson.categoryZh, default: []].append(lesson)
        }
        return order.map { ($0, groups[$0] ?? []) }
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
    }

    func isCompleted(_ lessonId: String) -> Bool {
        completedLessonIds.contains(lessonId)
    }
}
