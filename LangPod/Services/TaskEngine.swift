import Foundation
import UIKit

// MARK: - Task Events (posted by hook sites, consumed by TaskEngine)

extension Notification.Name {
    /// 任 1 集第 1 遍英语原音播完（AudioPlayer.advancePhase）。userInfo: episode_id
    static let taskEventFirstRoundFinished = Notification.Name("castlingo.task.firstRoundFinished")
    /// 一整集全部遍数播完（DataStore.completeEpisode 方法体）。userInfo: episode_id
    static let taskEventEpisodeCompleted = Notification.Name("castlingo.task.episodeCompleted")
    /// 一个句型讲解音频完整听完（AudioPlayer.handleItemFinished .pattern 分支）。userInfo: pattern_id
    static let taskEventPatternFinished = Notification.Name("castlingo.task.patternFinished")
    /// 词义配对完成一轮（WordMatchView.advanceRound）
    static let taskEventWordMatchDone = Notification.Name("castlingo.task.wordMatchDone")
    /// 连词成句完成一轮（FeynmanChallengeView.advanceWord）
    static let taskEventSentenceBuildDone = Notification.Name("castlingo.task.sentenceBuildDone")
    /// 场景模拟完成一轮（SceneQuizView.advance）
    static let taskEventSceneQuizDone = Notification.Name("castlingo.task.sceneQuizDone")
    /// 课堂学完（LessonStore.markCompleted 方法体，自带 lessonId 去重）。userInfo: lesson_id
    static let taskEventLessonCompleted = Notification.Name("castlingo.task.lessonCompleted")
    /// 模拟现场对话走完（LessonRolePlayView.advance 首次 finished）
    static let taskEventRoleplayFinished = Notification.Name("castlingo.task.roleplayFinished")
    /// 真实播客（audio 类型）收听心跳，每 0.5s 一次（RawAudioController periodic observer，
    /// 已按 timeControlStatus == .playing 过滤）。userInfo: seconds (Double)
    static let taskEventRawListenTick = Notification.Name("castlingo.task.rawListenTick")

    /// 任务状态变化（完成/重抽）。LangPodApp 监听 → 重排每日推送。
    static let dailyTasksChanged = Notification.Name("castlingo.task.stateChanged")
    /// 任务 deep link：userInfo: type = DailyTaskType.rawValue。ContentView 接收后切 tab / 拉起对应页面。
    static let dailyTaskDeepLink = Notification.Name("castlingo.task.deepLink")
}

// MARK: - Task Types

/// 每日任务类型。格① 固定听力；格② 句型（当天无产出则换练习）；格③ 练习三选一；
/// 格④ 从剩余合格池抽（免费池剔除课堂类）。
enum DailyTaskType: String, Codable, CaseIterable {
    case listenEpisode = "listen_episode"
    case listenPattern = "listen_pattern"
    case practiceWordMatch = "practice_word_match"
    case practiceSentence = "practice_sentence_build"
    case practiceSceneQuiz = "practice_scene_quiz"
    case learnLesson = "learn_lesson"
    case roleplayLesson = "roleplay_lesson"
    case rawPodcast10Min = "raw_podcast_10min"   // 达标 5 分钟；case 名 / rawValue 保留，避免破坏已持久化的 record

    var title: String {
        switch self {
        case .listenEpisode: return "听一集学习播客"
        case .listenPattern: return "学一个句型"
        case .practiceWordMatch: return "词义配对一轮"
        case .practiceSentence: return "连词成句一轮"
        case .practiceSceneQuiz: return "场景模拟一轮"
        case .learnLesson: return "学一篇场景课堂"
        case .roleplayLesson: return "走一遍模拟对话"
        case .rawPodcast10Min: return "听 5 分钟真实播客"
        }
    }

    var icon: String {
        switch self {
        case .listenEpisode: return "headphones"
        case .listenPattern: return "text.bubble"
        case .practiceWordMatch: return "rectangle.on.rectangle"
        case .practiceSentence: return "text.word.spacing"
        case .practiceSceneQuiz: return "person.2.wave.2"
        case .learnLesson: return "book"
        case .roleplayLesson: return "bubble.left.and.bubble.right"
        case .rawPodcast10Min: return "waveform"
        }
    }

    var estimatedMinutes: Int {
        switch self {
        case .listenEpisode: return 5
        case .listenPattern: return 2
        case .practiceWordMatch, .practiceSentence, .practiceSceneQuiz: return 2
        case .learnLesson: return 3
        case .roleplayLesson: return 2
        case .rawPodcast10Min: return 5
        }
    }

    /// 打卡清单展示顺序：轻 → 重。先给几十秒能完成的单词练习（快速拿到完成感），
    /// 再句型讲解（约 2 分钟），播客类压轴 —— 避免新用户一打开就面对最重的任务。
    var displayOrder: Int {
        switch self {
        case .practiceWordMatch: return 0
        case .practiceSentence: return 1
        case .practiceSceneQuiz: return 2
        case .listenPattern: return 3
        case .learnLesson: return 4
        case .roleplayLesson: return 5
        case .listenEpisode: return 6
        case .rawPodcast10Min: return 7
        }
    }

    var isPractice: Bool {
        self == .practiceWordMatch || self == .practiceSentence || self == .practiceSceneQuiz
    }
}

// MARK: - Persisted Record

/// 单一 UserDefaults key，每次变更整体写盘。跨 0 点检测到 dateKey != 今天 → 整体作废重抽。
struct DailyTaskRecord: Codable {
    var dateKey: String            // 本地时区 yyyy-MM-dd
    var taskIds: [String]          // 抽中的任务类型 id，3-4 个
    var doneFlags: [Bool]
    var popupShownToday: Bool      // 当日清单弹窗是否已自动展示
    var rewardGranted: Bool        // 4/4 火苗/analytics 是否已发（幂等，只一次）
    var rawListenSeconds: Double   // 10 分钟播客的累计收听秒数
    var celebrationShown: Bool? = nil  // 庆祝是否已「真正展示给用户」（与发奖解耦）。
                                       // optional 兼容旧记录；被完成页/练习全屏页挡下时不算展示，回前台补弹。
}

// MARK: - TaskEngine

/// 每日任务单例：抽取/资格过滤/事件记账/点火苗。
/// 事件源分散在 Services 和 Views 两层（SceneQuizView 自包含无环境注入、AudioPlayer 是
/// @State 实例非单例），所以走 NotificationCenter 广播 + 单例订阅，不走 @Environment。
@Observable
final class TaskEngine {
    static let shared = TaskEngine()

    /// 今日任务记录。UI 直接读；为 nil 表示还没抽（等 episodes 加载）。
    private(set) var record: DailyTaskRecord?

    // 依赖（App 启动时 configure 注入；weak 防环）
    private weak var dataStore: DataStore?
    private weak var vocabularyStore: VocabularyStore?
    private weak var lessonStore: LessonStore?
    private weak var subscriptionManager: SubscriptionManager?

    // UI 回调（LangPodApp 挂载；主线程调用）
    /// (完成的任务, 下一个未完成任务或 nil)
    var onTaskCompleted: ((DailyTaskType, DailyTaskType?) -> Void)?
    /// 4/4 全完成（幂等，只发一次）
    var onAllCompleted: (() -> Void)?

    private let storageKey = "dailyTaskRecord"
    private var observers: [NSObjectProtocol] = []
    /// 真实播客秒数节流缓冲：满 10s 才整体落盘一次，避免 0.5s 心跳频繁写 UserDefaults。
    private var pendingRawSeconds: Double = 0

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(DailyTaskRecord.self, from: data) {
            record = saved
        }
        subscribeEvents()
    }

    // MARK: - Setup

    func configure(
        dataStore: DataStore,
        vocabularyStore: VocabularyStore,
        lessonStore: LessonStore,
        subscriptionManager: SubscriptionManager
    ) {
        self.dataStore = dataStore
        self.vocabularyStore = vocabularyStore
        self.lessonStore = lessonStore
        self.subscriptionManager = subscriptionManager
        // 课堂资格依赖 lessons 列表（平时只在词汇 tab 首次出现时才加载）——这里主动拉，
        // 让抽取时 Pro 池的资格判断有数据可查。
        lessonStore.loadIfNeeded()
        #if DEBUG
        if let r = record {
            print("📋 TaskEngine 启动时记录: \(r.dateKey) tasks=\(r.taskIds) done=\(r.doneFlags) popupShown=\(r.popupShownToday) raw=\(Int(r.rawListenSeconds))s")
        } else {
            print("📋 TaskEngine 启动时无记录，等待抽取")
        }
        #endif
        scheduleEnsureToday()
    }

    /// 回前台 / 冷启动时调用：跨天则作废重抽，同一天不动（当天绝不重抽）。
    func checkDayRollover() {
        if let r = record, r.dateKey == Self.todayKey() { return }
        scheduleEnsureToday()
    }

    /// 等 episodes（今日句型资格的数据源）加载稳定后再抽，最多等 4 秒。
    /// 事件先到时 handle 侧会用当下数据立即抽（listenEpisode 格永远存在，不丢账）。
    private func scheduleEnsureToday() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<8 {
                if let ds = self.dataStore, !ds.isLoadingEpisodes, !ds.episodes.isEmpty { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            self.ensureTodayRecord()
        }
    }

    /// 保证 record 是今天的：没有或过期 → 立即抽取并整体持久化。
    @discardableResult
    func ensureTodayRecord() -> DailyTaskRecord {
        let today = Self.todayKey()
        if let r = record, r.dateKey == today { return r }

        let tasks = drawTasks()
        let fresh = DailyTaskRecord(
            dateKey: today,
            taskIds: tasks.map(\.rawValue),
            doneFlags: Array(repeating: false, count: tasks.count),
            popupShownToday: false,
            rewardGranted: false,
            rawListenSeconds: 0
        )
        record = fresh
        pendingRawSeconds = 0
        persist()
        #if DEBUG
        print("📋 TaskEngine 抽取今日任务: \(tasks.map(\.rawValue).joined(separator: ", "))")
        #endif
        NotificationCenter.default.post(name: .dailyTasksChanged, object: nil)
        return fresh
    }

    // MARK: - Drawing (配额制 + 资格过滤，seed 稳定当天不变)

    private func drawTasks() -> [DailyTaskType] {
        let seed = LessonStore.dailyShuffleSeed()
        var slots: [DailyTaskType] = [.listenEpisode]   // 格① 固定
        var usedPractices: Set<DailyTaskType> = []
        let practices = eligiblePractices()             // 场景模拟保底，永不为空

        // 格②：句型；当天 cron 无产出 → 替换为练习类
        if hasPatternToday() {
            slots.append(.listenPattern)
        } else if let sub = pickStable(from: practices.filter { !usedPractices.contains($0) }, seed: seed + "|slot2") {
            slots.append(sub)
            usedPractices.insert(sub)
        }

        // 格③：练习三选一
        if let p = pickStable(from: practices.filter { !usedPractices.contains($0) }, seed: seed + "|slot3") {
            slots.append(p)
            usedPractices.insert(p)
        }

        // 格④：机动池（Pro 才含课堂类；免费池剔除）
        var pool: [DailyTaskType] = []
        let isPro = subscriptionManager?.isProUser == true
        if isPro, lessonStore?.lessons.isEmpty == false {
            pool.append(.learnLesson)
            pool.append(.roleplayLesson)
        }
        if hasRawPodcastForTask() {
            pool.append(.rawPodcast10Min)
        }
        pool += practices.filter { !usedPractices.contains($0) }   // 第二种练习
        if let extra = pickStable(from: pool, seed: seed + "|slot4") {
            slots.append(extra)
        }

        return slots   // 合格不足 4 个 → 当天出 3 个，不硬凑
    }

    /// 练习资格：配对需 ≥4 词；连词成句需有可练例句（≤12 词的非空例句）；场景模拟永远合格。
    private func eligiblePractices() -> [DailyTaskType] {
        var result: [DailyTaskType] = []
        let words = vocabularyStore?.words ?? []
        if words.count >= 4 {
            result.append(.practiceWordMatch)
        }
        if words.contains(where: { !$0.example.isEmpty && $0.example.split(separator: " ").count <= 12 }) {
            result.append(.practiceSentence)
        }
        result.append(.practiceSceneQuiz)   // 保底：免费无限、无前置
        return result
    }

    private func hasPatternToday() -> Bool {
        guard let ds = dataStore else { return false }
        let today = DateFormatter.episodeDate.string(from: Date())
        return ds.episodes.contains { $0.date == today && ($0.patterns?.isEmpty == false) }
    }

    /// 是否有可作为「听真实播客」任务的原声。纳入 video —— audio 和 video 都走 AVPlayer（OSS mp4），
    /// 进度都拿得到，能精确统计达标。判据用 audioUrl != nil（有它才走 AVPlayer；纯 iframe 拿不到进度，
    /// 排除）。不要求「当日更新」：video 供给是历史 keynote，不会每天新增，卡当日更新等于永远不出现。
    private func hasRawPodcastForTask() -> Bool {
        guard let ds = dataStore else { return false }
        return ds.rawPodcasts.contains { $0.audioUrl != nil }
    }

    /// 确定性抽取：按 stableHash(id|seed) 排序取第一个。当天稳定、跨天变化、跨启动一致。
    private func pickStable(from pool: [DailyTaskType], seed: String) -> DailyTaskType? {
        pool.min { LessonStore.stableHash("\($0.rawValue)|\(seed)") < LessonStore.stableHash("\($1.rawValue)|\(seed)") }
    }

    // MARK: - Event Intake

    private func subscribeEvents() {
        let center = NotificationCenter.default
        // queue: .main 保证 @Observable 状态只在主线程改（AVAudioPlayer delegate 链可能在后台线程 post）
        func on(_ name: Notification.Name, _ handler: @escaping (Notification) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main, using: handler))
        }

        on(.taskEventFirstRoundFinished) { [weak self] _ in self?.complete(.listenEpisode) }
        // 完成一整集也算格①（兜底：万一第 1 遍事件在流播边界丢失）
        on(.taskEventEpisodeCompleted) { [weak self] _ in self?.complete(.listenEpisode) }
        on(.taskEventPatternFinished) { [weak self] _ in self?.complete(.listenPattern) }
        on(.taskEventWordMatchDone) { [weak self] _ in self?.complete(.practiceWordMatch) }
        on(.taskEventSentenceBuildDone) { [weak self] _ in self?.complete(.practiceSentence) }
        on(.taskEventSceneQuizDone) { [weak self] _ in self?.complete(.practiceSceneQuiz) }
        on(.taskEventLessonCompleted) { [weak self] _ in self?.complete(.learnLesson) }
        on(.taskEventRoleplayFinished) { [weak self] _ in self?.complete(.roleplayLesson) }
        on(.taskEventRawListenTick) { [weak self] note in
            let sec = note.userInfo?["seconds"] as? Double ?? 0.5
            self?.accumulateRawListen(seconds: sec)
        }
    }

    /// 记账：按格序匹配第一个未完成的同类格；没有同类格或已完成 → 忽略（即天然按日去重，
    /// repeatOne 反复触发/重听同集都不会重复记）。
    private func complete(_ type: DailyTaskType) {
        ensureTodayRecord()
        guard var r = record else { return }
        guard let idx = r.taskIds.indices.first(where: { r.taskIds[$0] == type.rawValue && !r.doneFlags[$0] }) else {
            return
        }
        r.doneFlags[idx] = true
        record = r
        persist()

        // 完成任意 1 格点亮火苗（非听力任务也点火，lastListenDate 同步更新 → 推送仲裁不误报断连）
        dataStore?.markStreakActivity()

        Analytics.track(.dailyTaskComplete, params: ["type": type.rawValue])
        #if DEBUG
        print("📋 TaskEngine 任务完成: \(type.rawValue) (\(completedCount)/\(totalCount))")
        #endif

        onTaskCompleted?(type, nextIncompleteTask())
        grantIfNeeded()
        NotificationCenter.default.post(name: .dailyTasksChanged, object: nil)
    }

    /// 真实播客收听秒数：audio / video 都走 AVPlayer，确认在播时由挂点 post。累计 ≥300s（5 分钟）达标。
    /// 落盘节流：每满 10s 整体写一次（杀进程最多丢 10s，可接受）。
    private func accumulateRawListen(seconds: Double) {
        ensureTodayRecord()
        guard var r = record else { return }
        // 没有这个格的日子也累计（记录当天收听量，成本极低），达标判定只看有格的情况
        pendingRawSeconds += seconds
        guard pendingRawSeconds >= 10 else { return }
        r.rawListenSeconds += pendingRawSeconds
        pendingRawSeconds = 0
        record = r
        persist()

        if r.rawListenSeconds >= 300 {
            complete(.rawPodcast10Min)
        }
    }

    /// 4/4 达成：火苗/analytics 只发一次（rewardGranted 幂等），随后尝试展示庆祝。
    /// 关键：庆祝「展示」与「发奖」解耦——被完成页/练习全屏页挡下时不算已展示，回前台再补弹。
    private func grantIfNeeded() {
        guard var r = record,
              !r.doneFlags.isEmpty,
              r.doneFlags.allSatisfy({ $0 }) else { return }
        if !r.rewardGranted {
            r.rewardGranted = true
            record = r
            persist()
            Analytics.track(.dailyTaskAllComplete)
        }
        presentCelebrationIfNeeded()
    }

    /// 全部完成且庆祝尚未真正展示 → 触发展示（onAllCompleted 内部判断是否被 cover 挡、需排队）。
    /// 冷启动 / 回前台也会调用，恢复被吞掉的庆祝（如锁屏听完最后一格、或第 4 格在练习全屏页里完成）。
    func presentCelebrationIfNeeded() {
        guard let r = record, r.dateKey == Self.todayKey(),
              !r.doneFlags.isEmpty,
              r.doneFlags.allSatisfy({ $0 }),
              r.celebrationShown != true else { return }
        onAllCompleted?()
    }

    /// 庆祝页真正展示后（用户点继续/炫耀）调用，持久化「已展示」，避免回前台重复弹。
    func markCelebrationShown() {
        guard var r = record else { return }
        r.celebrationShown = true
        record = r
        persist()
    }

    // MARK: - UI Queries

    var todayTasks: [(type: DailyTaskType, done: Bool)] {
        guard let r = record, r.dateKey == Self.todayKey() else { return [] }
        return r.taskIds.indices.compactMap { i -> (type: DailyTaskType, done: Bool)? in
            guard let t = DailyTaskType(rawValue: r.taskIds[i]) else { return nil }
            return (t, r.doneFlags[i])
        }
        // 展示顺序轻 → 重（完成标记按类型匹配，与持久化顺序无关，重排安全）
        .sorted { $0.type.displayOrder < $1.type.displayOrder }
    }

    var completedCount: Int {
        guard let r = record, r.dateKey == Self.todayKey() else { return 0 }
        return r.doneFlags.filter { $0 }.count
    }

    var totalCount: Int {
        guard let r = record, r.dateKey == Self.todayKey() else { return 0 }
        return r.taskIds.count
    }

    func nextIncompleteTask() -> DailyTaskType? {
        todayTasks.first(where: { !$0.done })?.type
    }

    /// 弹窗当日是否已自动弹过。
    var popupShownToday: Bool {
        guard let r = record, r.dateKey == Self.todayKey() else { return false }
        return r.popupShownToday
    }

    func markPopupShown() {
        ensureTodayRecord()
        guard var r = record else { return }
        r.popupShownToday = true
        record = r
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        guard let r = record, let data = try? JSONEncoder().encode(r) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    /// 本地时区 yyyy-MM-dd（与 LessonStore.dailyShuffleSeed 同一套日界）
    static func todayKey() -> String {
        LessonStore.dailyShuffleSeed()
    }
}

// MARK: - Debug helpers（仅开发版；#if DEBUG 包住，release 不编译）

#if DEBUG
extension TaskEngine {
    /// 清空今日任务并重抽，同时清掉「弹窗已弹」「onboarding 当天不弹」两个闸门。
    /// 之后切后台再回前台（或杀进程重启）即可复现「自动弹清单」。
    func debugResetToday() {
        record = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: "onboardingCompletedDay")
        pendingRawSeconds = 0
        ensureTodayRecord()
    }

    /// 完成下一个未完成任务格——走真实 complete 流程（横条 + 火苗 + 进度环 + 4/4 庆祝），
    /// 跳过等音频 / 免费额度。
    func debugCompleteNext() {
        guard let next = nextIncompleteTask() else { return }
        complete(next)
    }

    /// 完成全部剩余任务格 → 触发 4/4 大庆祝。
    func debugCompleteAll() {
        // 测试时清掉「已发奖 / 已展示」闸门，保证每次都重新弹庆祝
        if var r = record {
            r.rewardGranted = false
            r.celebrationShown = false
            record = r
            persist()
        }
        while let next = nextIncompleteTask() {
            complete(next)
        }
        // 若本来就已全完成（nextIncompleteTask 直接为 nil），也主动补弹一次
        presentCelebrationIfNeeded()
    }
}
#endif
