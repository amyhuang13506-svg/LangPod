import Foundation

/// 口语表达库数据层：index 缓存优先展示 + 后台拉取，分类详情懒加载（仿 LessonStore）。
@Observable
class ExpressionStore {
    var groups: [ExpressionGroup] = []
    var isLoading = false
    var selectedGroupId: String {
        didSet { UserDefaults.standard.set(selectedGroupId, forKey: "expressionGroup") }
    }

    /// 顶部双区块（日常社交 | 商务英语）。切换时自动跳到该区块第一个组。
    var section: ExpressionSection {
        didSet {
            UserDefaults.standard.set(section.rawValue, forKey: "patternSection")
            if let first = groupsInSection.first, first.sectionValue == section,
               !groupsInSection.contains(where: { $0.id == selectedGroupId }) {
                selectedGroupId = first.id
                loadGroupDetails(first.id)
            }
        }
    }

    /// 当前区块下的组（老数据无 section → 归 social）。
    /// 只保留有内容的组 —— 内容分批上线时，未产出的分类 JSON 在 OSS 上还是 404，
    /// 展示出来会永久转圈；按 index 的 count 过滤掉，内容一上线自动出现。
    var groupsInSection: [ExpressionGroup] {
        groups.filter { $0.sectionValue == section && $0.categories.contains { $0.count > 0 } }
    }

    /// 分类详情缓存（分类 id → 完整表达列表）。主页按组平铺展示，选中组的 6 个分类并发拉取。
    private(set) var details: [String: ExpressionCategory] = [:]
    private var loaded = false
    private var loadingGroups: Set<String> = []

    init() {
        self.selectedGroupId = UserDefaults.standard.string(forKey: "expressionGroup") ?? "daily"
        self.section = ExpressionSection(
            rawValue: UserDefaults.standard.string(forKey: "patternSection") ?? ""
        ) ?? .social
    }

    /// 选中的组：必须落在当前区块内，否则回退到该区块第一个组
    var selectedGroup: ExpressionGroup? {
        groupsInSection.first { $0.id == selectedGroupId } ?? groupsInSection.first
    }

    func loadIfNeeded() {
        guard !loaded && !isLoading else { return }
        if let cached = APIService.shared.loadCachedExpressionIndexSync() {
            groups = cached
        }
        isLoading = true
        Task {
            let remote = await APIService.shared.fetchExpressionIndex()
            if !remote.isEmpty { self.groups = remote }
            self.isLoading = false
            self.loaded = true
            self.loadGroupDetails(self.selectedGroupId)
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

    // MARK: - 免费闸门（免费单位 = 大组 chip）

    /// 某分类是不是它所在大组的「免费分类」= 该组第一个有内容的分类。
    /// 免费的表达只落在这个分类的前 ExpressionFreeGate.freeCount 条。
    func isFreeCategory(_ categoryId: String) -> Bool {
        guard let group = groups.first(where: { g in g.categories.contains { $0.id == categoryId } })
        else { return true }   // 组结构未加载 → 保守放行（不误锁），加载后自然收敛
        return group.categories.first { $0.count > 0 }?.id == categoryId
    }

    /// 单条表达是否锁定：非 Pro 时，只有「组的免费分类」的前 freeCount 条免费，其余全锁。
    func isExpressionLocked(categoryId: String, index: Int, isPro: Bool) -> Bool {
        if isPro { return false }
        return !(index < ExpressionFreeGate.freeCount && isFreeCategory(categoryId))
    }

    /// 每个大组的免费入口分类（第一个有内容分类）——供每日任务深链定位免费表达。
    var freeEntryCategories: [ExpressionCategoryIndexItem] {
        groups.compactMap { group in group.categories.first { $0.count > 0 } }
    }
}
