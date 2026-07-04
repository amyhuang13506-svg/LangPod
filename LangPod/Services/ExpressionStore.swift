import Foundation

/// 口语表达库数据层：index 缓存优先展示 + 后台拉取，分类详情懒加载（仿 LessonStore）。
@Observable
class ExpressionStore {
    var groups: [ExpressionGroup] = []
    var isLoading = false
    var selectedGroupId: String {
        didSet { UserDefaults.standard.set(selectedGroupId, forKey: "expressionGroup") }
    }

    /// 分类详情缓存（分类 id → 完整表达列表）。主页按组平铺展示，选中组的 6 个分类并发拉取。
    private(set) var details: [String: ExpressionCategory] = [:]
    private var loaded = false
    private var loadingGroups: Set<String> = []

    /// 今日句型（跨大组，来自 expressions/today.json）。仅当日期是今天才展示。
    var globalToday: ExpressionToday?
    private var loadedToday = false

    /// 当天有效的今日句型（过期自动隐藏）
    var todayExpression: ExpressionToday? {
        guard let t = globalToday, ExpressionAccessGate.isToday(t.date) else { return nil }
        return t
    }

    init() {
        self.selectedGroupId = UserDefaults.standard.string(forKey: "expressionGroup") ?? "reactions"
    }

    var selectedGroup: ExpressionGroup? {
        groups.first { $0.id == selectedGroupId } ?? groups.first
    }

    func loadIfNeeded() {
        guard !loaded && !isLoading else { return }
        if let cached = APIService.shared.loadCachedExpressionIndexSync() {
            groups = cached
        }
        isLoading = true
        loadTodayIfNeeded()
        Task {
            let remote = await APIService.shared.fetchExpressionIndex()
            if !remote.isEmpty { self.groups = remote }
            self.isLoading = false
            self.loaded = true
            self.loadGroupDetails(self.selectedGroupId)
        }
    }

    /// 拉今日句型（每次会话一次）。顶部置顶卡用。
    func loadTodayIfNeeded() {
        guard !loadedToday else { return }
        loadedToday = true
        Task {
            if let t = await APIService.shared.fetchTodayExpression() {
                self.globalToday = t
                // 顺带把它所属分类详情拉回，方便分类内定位 + NEW 角标
                self.loadGroupDetails(t.groupId)
            }
        }
    }

    /// 拉取一个组下全部分类的表达（并发，幂等）
    func loadGroupDetails(_ groupId: String) {
        guard let group = groups.first(where: { $0.id == groupId }),
              !loadingGroups.contains(groupId) else { return }
        let missing = group.categories.filter { details[$0.id] == nil }
        guard !missing.isEmpty else { return }
        loadingGroups.insert(groupId)
        Task {
            await withTaskGroup(of: (String, ExpressionCategory?).self) { taskGroup in
                for category in missing {
                    taskGroup.addTask {
                        (category.id, await APIService.shared.fetchExpressionCategory(id: category.id))
                    }
                }
                for await (id, detail) in taskGroup {
                    if let detail { self.details[id] = detail }
                }
            }
            self.loadingGroups.remove(groupId)
        }
    }

    func categoryDetail(id: String) async -> ExpressionCategory? {
        if let cached = details[id] { return cached }
        let detail = await APIService.shared.fetchExpressionCategory(id: id)
        if let detail { details[id] = detail }
        return detail
    }
}
