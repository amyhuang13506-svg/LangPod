import Foundation

/// 口语表达库数据层：index 缓存优先展示 + 后台拉取，分类详情懒加载（仿 LessonStore）。
@Observable
class ExpressionStore {
    var groups: [ExpressionGroup] = []
    var isLoading = false
    var selectedGroupId: String {
        didSet { UserDefaults.standard.set(selectedGroupId, forKey: "expressionGroup") }
    }

    private var detailCache: [String: ExpressionCategory] = [:]
    private var loaded = false

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
        Task {
            let remote = await APIService.shared.fetchExpressionIndex()
            if !remote.isEmpty { self.groups = remote }
            self.isLoading = false
            self.loaded = true
        }
    }

    func categoryDetail(id: String) async -> ExpressionCategory? {
        if let cached = detailCache[id] { return cached }
        let detail = await APIService.shared.fetchExpressionCategory(id: id)
        if let detail { detailCache[id] = detail }
        return detail
    }
}
