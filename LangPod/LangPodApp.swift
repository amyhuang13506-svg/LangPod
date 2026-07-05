import SwiftUI
#if canImport(RevenueCat)
import RevenueCat
#endif

@Observable
class AppState {
    var showToast = false
    var showCompletePage = false
    var toastTitle = ""
    var toastWordCount = 0
    var completedEpisode: Episode?

    // 每日任务系统
    var showDailyTasks = false            // 任务清单弹窗（根部 overlay，非 fullScreenCover，避免多 cover 冲突）
    var showTaskCelebration = false       // 4/4 点火大庆祝
    var pendingTaskCelebration = false    // 完成页/LevelUp 占用时排队，等 dismiss 再弹
    var taskToast: TaskToastData?         // 中途横条（完成的任务 + 下一个任务）
    var taskToastGeneration = 0           // 自动消失的代际闸门（新横条出现时旧定时器作废）
    var showTaskShareCard = false         // 里程碑日庆祝页「炫耀一下」→ 分享海报
}

@main
struct LangPodApp: App {
    @UIApplicationDelegateAdaptor(PushService.self) var pushService
    @State private var dataStore = DataStore()
    @State private var audioPlayer = AudioPlayer()
    @State private var vocabularyStore = VocabularyStore()
    @State private var sentenceStore = SentenceStore()
    @State private var lessonStore = LessonStore()
    @State private var appState = AppState()
    @State private var notificationManager = NotificationManager()
    @State private var subscriptionManager = SubscriptionManager()

    init() {
        #if canImport(RevenueCat)
        // Configure RevenueCat synchronously at launch, before anything touches
        // Purchases.shared. SubscriptionManager only accesses Purchases inside
        // deferred Tasks, so those run after this returns. Skipped until a real
        // `appl_` key is pasted into RevenueCatConfig (avoids configuring with a
        // placeholder); the manager then no-ops safely via Purchases.isConfigured.
        if RevenueCatConfig.isReady {
            #if DEBUG
            Purchases.logLevel = .debug
            #else
            Purchases.logLevel = .info
            #endif
            Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
        }
        #endif
    }

    // Intentionally empty.
    // Umeng init was previously here but blocked the main thread for ~300-500ms
    // on cold launch (UTDID keychain read + session bootstrap + report timer),
    // making the Onboarding first tap feel laggy. It's moved to `.task` below
    // so the first frame renders before the SDK starts. A few events at the
    // very start of the session may be dropped — acceptable.

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .bottom) {
                ContentView()
                    .environment(dataStore)
                    .environment(audioPlayer)
                    .environment(vocabularyStore)
                    .environment(sentenceStore)
                    .environment(lessonStore)
                    .environment(appState)
                    .environment(subscriptionManager)

                // Toast notification
                if appState.showToast {
                    EpisodeToast(
                        title: appState.toastTitle,
                        wordCount: appState.toastWordCount,
                        onTap: {
                            withAnimation { appState.showToast = false }
                            appState.showCompletePage = true
                        }
                    )
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 每日任务横条（顶部滑入，3.5s 自动消失，点击直达下一任务）
                if let toast = appState.taskToast {
                    TaskToastBar(data: toast) {
                        withAnimation { appState.taskToast = nil }
                        if let next = toast.nextType {
                            Analytics.track(.dailyTaskEntryTap, params: ["source": "toast"])
                            NotificationCenter.default.post(
                                name: .dailyTaskDeepLink,
                                object: nil,
                                userInfo: ["type": next.rawValue]
                            )
                        }
                    }
                    .padding(.top, 8)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
                }

                // 每日任务清单弹窗（全天最多自动弹 1 次；「我的」页 Streak 卡可随时重开）
                if appState.showDailyTasks {
                    DailyTaskPopupView(
                        onClose: {
                            Analytics.track(.dailyTaskPopupDismiss, params: [
                                "done_count": "\(TaskEngine.shared.completedCount)"
                            ])
                            withAnimation(.easeOut(duration: 0.2)) { appState.showDailyTasks = false }
                        },
                        onTapTask: { type in
                            Analytics.track(.dailyTaskEntryTap, params: ["source": "popup"])
                            withAnimation(.easeOut(duration: 0.2)) { appState.showDailyTasks = false }
                            NotificationCenter.default.post(
                                name: .dailyTaskDeepLink,
                                object: nil,
                                userInfo: ["type": type.rawValue]
                            )
                        }
                    )
                    .environment(dataStore)
                    .transition(.opacity)
                    .zIndex(3)
                }

                // 4/4 点火大庆祝（完成页/LevelUp 优先，占用时排队）
                if appState.showTaskCelebration {
                    TaskCelebrationView(
                        onShare: {
                            TaskEngine.shared.markCelebrationShown()
                            appState.showTaskCelebration = false
                            appState.showTaskShareCard = true
                        },
                        onContinue: {
                            TaskEngine.shared.markCelebrationShown()
                            withAnimation(.easeOut(duration: 0.25)) { appState.showTaskCelebration = false }
                        }
                    )
                    .environment(dataStore)
                    .environment(vocabularyStore)
                    .transition(.opacity)
                    .zIndex(4)
                }
            }
            .fullScreenCover(isPresented: $appState.showCompletePage) {
                if let episode = appState.completedEpisode {
                    EpisodeCompleteView(
                        episode: episode,
                        onNextEpisode: {
                            appState.showCompletePage = false
                            // Only skip if still on the completed episode (not already auto-advanced)
                            if audioPlayer.currentEpisode?.id == episode.id {
                                audioPlayer.skipToNextEpisode()
                            }
                        },
                        onSaveVocabulary: {
                            vocabularyStore.saveWords(from: episode)
                            appState.showCompletePage = false
                            // Don't skip — background auto-play already moved to next episode
                        },
                        onPlayPatterns: {
                            guard let first = episode.patterns?.first else { return }
                            appState.showCompletePage = false
                            audioPlayer.playPattern(first, parentEpisode: episode, in: audioPlayer.playQueue)
                        }
                    )
                    .environment(dataStore)
                    .environment(vocabularyStore)
                    .environment(subscriptionManager)
                }
            }
            .sheet(isPresented: Binding(
                get: { appState.showTaskShareCard },
                set: { appState.showTaskShareCard = $0 }
            )) {
                ShareCardView()
                    .environment(dataStore)
                    .environment(vocabularyStore)
            }
            .task {
                setupPlayGate()
                // 每日任务引擎：注入依赖 + 抽取今日任务（等 episodes 加载稳定后）
                TaskEngine.shared.configure(
                    dataStore: dataStore,
                    vocabularyStore: vocabularyStore,
                    lessonStore: lessonStore,
                    subscriptionManager: subscriptionManager
                )
                setupTaskEngineCallbacks()
                // 锁屏 / 控制中心 handler 全局注册一次，谁在播谁就是 active。
                RemoteCommandRouter.shared.setup()
                // Deferred analytics bootstrap: runs after first frame.
                Analytics.setup()
                Analytics.track(.appLaunch)
                // Request notification permission after first launch.
                // requestPushAuthorization() also asks iOS for permission, so
                // we only need NotificationManager.requestPermission() to keep
                // its `isAuthorized` flag in sync for the local-push arbiter.
                if dataStore.hasCompletedOnboarding {
                    notificationManager.requestPermission()
                    PushService.shared.requestPushAuthorization()
                }
                // 晚间内容推送要用今日新场景课（today.json）——提前拉，保证进后台重排时已就绪。
                lessonStore.loadTodayIfNeeded()
                refreshDailyNotification()
                await autoShowDailyTasksIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                dataStore.loadEpisodes()
                // 跨 0 点回前台 → 任务整体作废重抽（同一天不动）
                TaskEngine.shared.checkDayRollover()
                // 恢复被吞掉的 4/4 庆祝（如锁屏听完最后一格、或在练习全屏页里完成第 4 格）
                TaskEngine.shared.presentCelebrationIfNeeded()
                refreshDailyNotification()
                // Re-register on every foreground in case the user just turned
                // on permission in Settings (system holds the prompt for life).
                PushService.shared.registerIfAuthorized()
                Task { await autoShowDailyTasksIfNeeded() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                // Most important refresh: we just closed the app, so state is
                // freshest, and the user is about to be away (the moment the
                // push matters).
                refreshDailyNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reminderTimeChanged)) { _ in
                refreshDailyNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: .dailyTasksChanged)) { _ in
                // 任务完成/重抽 → 重排每日推送（「只差 1 个」档要用最新进度）
                refreshDailyNotification()
            }
            .onChange(of: appState.showCompletePage) { _, showing in
                // 完成页关闭 → 补发排队中的 4/4 庆祝（优先级：完成页/LevelUp > 任务庆祝）
                if !showing { dequeuePendingCelebrationIfPossible() }
            }
            .onChange(of: dataStore.pendingLevelUp) { _, pending in
                if pending == nil { dequeuePendingCelebrationIfPossible() }
            }
            .onChange(of: dataStore.selectedLevel) { _, newLevel in
                // Re-register so server-side level filter stays accurate after
                // the user switches reading level in Profile or Onboarding.
                PushService.shared.reuploadForLevelChange(newLevel: newLevel.rawValue)
            }
            .onChange(of: dataStore.hasCompletedOnboarding) { _, completed in
                // First time finishing onboarding → ask for push permission so
                // the user can start receiving new-episode notifications today,
                // not on next cold launch.
                if completed {
                    notificationManager.requestPermission()
                    PushService.shared.requestPushAuthorization()
                    // 记录 onboarding 完成日：当天不自动弹任务清单（不打断新用户首体验）
                    UserDefaults.standard.set(TaskEngine.todayKey(), forKey: "onboardingCompletedDay")
                }
            }
        }
    }

    // MARK: - Daily Tasks

    /// TaskEngine → UI 的两个回调：中途横条 + 4/4 大庆祝。主线程调用（TaskEngine 事件订阅在 main queue）。
    private func setupTaskEngineCallbacks() {
        TaskEngine.shared.onTaskCompleted = { [self] completed, next in
            // 4/4 时不出横条（大庆祝接管）；清单弹窗打开时也不出（清单自身实时打勾）
            guard next != nil, !appState.showDailyTasks else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                appState.taskToast = TaskToastData(completedTitle: completed.title, nextType: next)
            }
            // 3.5s 自动消失；同刻多任务达成会覆盖为最新一条，代际闸门防旧定时器误关新横条
            appState.taskToastGeneration += 1
            let gen = appState.taskToastGeneration
            Task {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                if appState.taskToastGeneration == gen {
                    withAnimation { appState.taskToast = nil }
                }
            }
        }

        TaskEngine.shared.onAllCompleted = { [self] in
            withAnimation { appState.taskToast = nil }
            // 完成页 / LevelUp 正在展示 → 排队等其关闭（陷阱：同 view 多 cover 同时置 true 会静默丢）
            if appState.showCompletePage || dataStore.pendingLevelUp != nil {
                appState.pendingTaskCelebration = true
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    appState.showDailyTasks = false
                    appState.showTaskCelebration = true
                }
            }
        }
    }

    private func dequeuePendingCelebrationIfPossible() {
        guard appState.pendingTaskCelebration,
              !appState.showCompletePage,
              dataStore.pendingLevelUp == nil else { return }
        appState.pendingTaskCelebration = false
        // 等完成页 dismiss 动画走完再弹，避免转场撞车
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                appState.showTaskCelebration = true
            }
        }
    }

    /// 冷启动 / 回前台自动弹任务清单。条件（全部满足）：已 onboarding 且非 onboarding 当天、
    /// 今日没自动弹过、没在播放、完成页/庆祝没在展示。首页渲染后延迟 1.5s。
    private func autoShowDailyTasksIfNeeded() async {
        guard dataStore.hasCompletedOnboarding else { return }
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let engine = TaskEngine.shared
        // 对账：各挂点事件实时落盘（锁屏听完的已带 ✓），这里只需保证今日记录已抽取
        engine.ensureTodayRecord()

        // 今日已 4/4 但庆祝还没弹过（如后台/锁屏听完最后一格）→ 弹庆祝，不再弹清单
        if engine.totalCount > 0, engine.completedCount >= engine.totalCount,
           !appState.showCompletePage, !appState.showTaskCelebration {
            engine.presentCelebrationIfNeeded()
            return
        }

        let onboardingDay = UserDefaults.standard.string(forKey: "onboardingCompletedDay")
        guard onboardingDay != TaskEngine.todayKey(),
              !engine.popupShownToday,
              !audioPlayer.isPlaying,
              !appState.showCompletePage,
              !appState.showTaskCelebration,
              !appState.showDailyTasks else { return }

        engine.markPopupShown()
        Analytics.track(.dailyTaskPopupView)
        withAnimation(.easeOut(duration: 0.25)) {
            appState.showDailyTasks = true
        }
    }

    private func setupPlayGate() {
        audioPlayer.playGate = { [self] episode in
            if subscriptionManager.isProUser {
                dataStore.recordPlayStart(episode: episode)
                return true
            }

            // Already played today? Allow replay without consuming a new daily slot.
            // IMPORTANT: check this BEFORE recordPlayStart, otherwise every episode
            // looks "already played" and the daily counter never increments.
            let alreadyPlayedToday = dataStore.listenHistory.contains {
                $0.episodeId == episode.id &&
                Calendar.current.isDateInToday($0.listenedAt)
            }
            if alreadyPlayedToday {
                dataStore.recordPlayStart(episode: episode)
                return true
            }

            dataStore.refreshDailyCountIfNeeded()
            if dataStore.dailyEpisodesPlayed >= SubscriptionManager.freeMaxDailyEpisodes {
                return false
            }
            dataStore.recordDailyPlay()
            dataStore.recordPlayStart(episode: episode)
            return true
        }
        audioPlayer.episodeEnricher = { [self] id in
            await dataStore.fetchEpisodeDetail(id: id)
        }

        // Default episode-finished handler: always record play history.
        // PlayerView overrides this with its own (adds completion page UI),
        // and restores it in onDisappear. This ensures history is recorded
        // even when PlayerView is not visible (e.g. background playback).
        setupDefaultFinishedHandler()
    }

    func setupDefaultFinishedHandler() {
        audioPlayer.onEpisodeFinished = { [self] in
            // Auto-save this episode's vocab so WordMatch / Feynman have real
            // content to work with. Idempotent: existing words are skipped.
            if let ep = audioPlayer.currentEpisode {
                vocabularyStore.saveWords(from: ep)
            }
            dataStore.completeEpisode(
                totalWords: vocabularyStore.totalCount,
                episode: audioPlayer.currentEpisode
            )
            audioPlayer.skipToNextEpisode()
            refreshDailyNotification()
        }
    }

    /// Recompute priority-arbitrated daily notification based on current state.
    /// Called at launch, foreground, background, and after episode completion.
    func refreshDailyNotification() {
        let context = buildNotificationContext()
        notificationManager.refreshDailyNotification(context: context)
    }

    private func buildNotificationContext() -> NotificationContext {
        let listenedToday = dataStore.listenHistory.contains {
            Calendar.current.isDateInToday($0.listenedAt)
        }

        let todayString = DateFormatter.episodeDate.string(from: Date())
        let newEpisode = dataStore.episodes.last { $0.date == todayString }

        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86400)
        let forgottenCount = vocabularyStore.words.filter { w in
            w.matchCorrectCount < 3 && w.lastPracticeDate < thirtyDaysAgo
        }.count

        let twoDaysAgo = Date().addingTimeInterval(-2 * 86400)
        let recentEncounters = vocabularyStore.words
            .filter { w in
                guard let enc = w.lastEncounterDate else { return false }
                return w.encounterCount > 0 && enc > twoDaysAgo
            }
            .map(\.word)

        let reminderHour = UserDefaults.standard.object(forKey: "reminderHour") as? Int ?? 20
        let reminderMinute = UserDefaults.standard.object(forKey: "reminderMinute") as? Int ?? 0

        // 晚间内容推送数据源：今日第一个句型 + 今日新场景课（跨国家置顶的 today.json）。
        let todayPattern: Pattern? = dataStore.episodes
            .filter { $0.date == todayString }
            .compactMap { $0.patterns }
            .flatMap { $0 }
            .first
        let todayCard = lessonStore.todayCard   // (item, country)，仅当 today.json 日期是今天

        return NotificationContext(
            streakDays: dataStore.streakDays,
            lastListenDate: dataStore.lastListenDate,
            listenedToday: listenedToday,
            newestEpisodeTitle: newEpisode?.title,
            hasNewEpisodeToday: newEpisode != nil,
            forgottenWordsCount: forgottenCount,
            recentEncounteredWords: recentEncounters,
            tasksCompletedToday: TaskEngine.shared.completedCount,
            tasksTotalToday: TaskEngine.shared.totalCount,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute,
            todayPatternTemplate: todayPattern?.template,
            todayPatternTranslationZh: todayPattern?.translationZh,
            todayPatternScene: todayPattern?.scene,
            todayLessonTitle: todayCard?.item.titleZh,
            todayLessonCountryZh: todayCard?.country.nameZh,
            todayLessonFlag: todayCard?.country.flag,
            todayLessonWordCount: todayCard?.item.wordCount
        )
    }
}
