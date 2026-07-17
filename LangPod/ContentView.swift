import SwiftUI

struct ContentView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AudioPlayer.self) private var audioPlayer
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(LessonStore.self) private var lessonStore
    @Environment(SentenceStore.self) private var sentenceStore

    @State private var selectedTab = 0

    /// 每日任务 deep link 拉起的练习页（直接从 ContentView present，避免嵌套跳转链）
    private enum TaskPracticeTarget: String, Identifiable {
        case wordMatch, sentenceBuild, sceneQuiz
        var id: String { rawValue }
    }
    @State private var taskPractice: TaskPracticeTarget?
    @State private var taskLesson: LessonOpenTarget?

    var body: some View {
        if dataStore.hasCompletedOnboarding {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Label("首页", systemImage: "house")
                    }
                    .tag(0)
                VocabularyView()
                    .tabItem {
                        Label("词汇", image: "vocabAa")
                    }
                    .tag(1)
                PatternsTabView()
                    .tabItem {
                        Label("句型", systemImage: "text.bubble")
                    }
                    .tag(2)
                ProfileView()
                    .tabItem {
                        Label("我的", systemImage: "person")
                    }
                    .tag(3)
            }
            .tint(.accent)
            .onAppear {
                // 截图/调试用：simctl launch 传 -debug_start_tab N 直接落到指定 tab
                // （argument domain 只在该次启动生效，真机正常启动不受影响）
                let debugTab = UserDefaults.standard.integer(forKey: "debug_start_tab")
                if (1...3).contains(debugTab) { selectedTab = debugTab }
            }
            .onChange(of: subscriptionManager.isProUser, initial: true) {
                audioPlayer.isProUser = subscriptionManager.isProUser
            }
            .onChange(of: dataStore.dailyPatternIDsPlayedToday, initial: true) {
                audioPlayer.dailyPatternIDsPlayedToday = dataStore.dailyPatternIDsPlayedToday
            }
            .task {
                // Bridge pattern play events from AudioPlayer back into DataStore
                // so the daily quota counter advances and persists.
                let store = dataStore
                audioPlayer.onPatternStarted = { id in
                    store.recordPatternPlayed(id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openEpisodeFromPush)) { note in
                guard let episodeId = note.userInfo?["episode_id"] as? String,
                      !episodeId.isEmpty else { return }
                let level = note.userInfo?["level"] as? String ?? ""
                openEpisodeFromPush(episodeId: episodeId, levelHint: level)
            }
            .onReceive(NotificationCenter.default.publisher(for: .dailyTaskDeepLink)) { note in
                guard let raw = note.userInfo?["type"] as? String,
                      let type = DailyTaskType(rawValue: raw) else { return }
                handleTaskDeepLink(type)
            }
            .fullScreenCover(item: $taskPractice) { target in
                switch target {
                case .wordMatch:
                    WordMatchView()
                        .environment(vocabularyStore)
                        .environment(subscriptionManager)
                        .onAppear { if audioPlayer.isPlaying { audioPlayer.togglePlayPause() } }
                case .sentenceBuild:
                    FeynmanChallengeView()
                        .environment(vocabularyStore)
                        .environment(subscriptionManager)
                        .onAppear { if audioPlayer.isPlaying { audioPlayer.togglePlayPause() } }
                case .sceneQuiz:
                    SceneQuizView()
                        .environment(sentenceStore)
                }
            }
            .fullScreenCover(item: $taskLesson) { target in
                LessonDetailView(item: target.item, country: target.country)
                    .environment(vocabularyStore)
                    .environment(lessonStore)
                    .environment(sentenceStore)
                    .environment(subscriptionManager)
            }
        } else {
            OnboardingView()
        }
    }

    // MARK: - 每日任务 deep link（弹窗任务格 / 中途横条 → 直达对应功能）

    private func handleTaskDeepLink(_ type: DailyTaskType) {
        switch type {
        case .listenEpisode:
            selectedTab = 0
            // 播今日第一集（走 playGate，免费额度照常生效）
            let today = DateFormatter.episodeDate.string(from: Date())
            let target = dataStore.episodes.last(where: { $0.date == today })
                ?? dataStore.currentEpisode
                ?? dataStore.episodes.last
            if let ep = target {
                _ = audioPlayer.playEpisode(ep, in: dataStore.episodes)
            }

        case .listenPattern:
            selectedTab = 0
            // 播今日第一个句型（今日句型免费；被额度 gate 挡下就停在首页，由今日句型卡走付费墙）
            let today = DateFormatter.episodeDate.string(from: Date())
            let pairs: [(Pattern, Episode)] = dataStore.episodes
                .filter { $0.date == today }
                .flatMap { ep in (ep.patterns ?? []).map { ($0, ep) } }
            if let first = pairs.first {
                let items: [PlayItem] = pairs.map { .pattern($0.0, parentEpisode: $0.1) }
                _ = audioPlayer.playPattern(first.0, parentEpisode: first.1, in: items)
            }

        case .learnExpression:
            // 句型 tab 图文表达库：切 tab 并置深链 flag，
            // PatternsTabView 出现后自动打开免费分类第一条（免费用户可看）
            selectedTab = 2
            TaskEngine.shared.pendingExpressionDeepLink = true

        case .practiceWordMatch:
            selectedTab = 1
            taskPractice = .wordMatch

        case .practiceSentence:
            selectedTab = 1
            taskPractice = .sentenceBuild

        case .practiceSceneQuiz:
            selectedTab = 1
            taskPractice = .sceneQuiz

        case .learnLesson, .roleplayLesson:
            selectedTab = 1
            // 今日课优先（跨国家、当天免费），否则按日在免费课池里轮换 ——
            // 原来只在选中国家索引里找，找不到就回退第一篇（对免费用户是锁的，
            // 等于任务把人带到付费墙）。模拟对话在课堂详情页内。
            lessonStore.loadIfNeeded()
            lessonStore.loadThemeIfNeeded()
            if let target = lessonStore.dailyTaskLesson {
                taskLesson = LessonOpenTarget(item: target.item, country: target.country)
            }

        case .rawPodcast10Min:
            selectedTab = 0
            // 纳入 video：只要有 audioUrl（走 AVPlayer，能统计进度）即可。优先今日更新，否则第一条。
            // 复用 pendingRawPodcastId 深链管道。
            let playable = dataStore.rawPodcasts.filter { $0.audioUrl != nil }
            let today = TaskEngine.todayKey()
            let target = playable.first(where: {
                $0.publishedAt == today || ($0.crawledAt?.hasPrefix(today) ?? false)
            }) ?? playable.first
            if let podcast = target {
                dataStore.pendingRawPodcastId = podcast.id
            }
        }
    }

    /// Resolve an episode from a push payload and play it.
    /// 1. If the episode is already in the loaded index → play directly.
    /// 2. Otherwise fetch detail by (id, level) and play.
    /// `levelHint` may be empty when the push is a local one without level data;
    /// we then fall back to scanning all known levels.
    private func openEpisodeFromPush(episodeId: String, levelHint: String) {
        // Raw podcast (硅谷原声) IDs are namespaced `raw-yt-…` / `raw-rss-…`
        // and use a totally different player. Hand off to HomeView via DataStore.
        if episodeId.hasPrefix("raw-") {
            dataStore.pendingRawPodcastId = episodeId
            // Refresh master list — the just-published item may not be in cache
            // yet. HomeView's onChange waits one frame and retries.
            Task { await dataStore.refreshRawPodcastsFromRemote() }
            return
        }

        // Hot path: episode already in current index
        if let ep = dataStore.episodes.first(where: { $0.id == episodeId }) {
            _ = audioPlayer.playEpisode(ep, in: dataStore.episodes)
            return
        }

        // Cold path: episode not yet in cache (push fired before index refresh).
        // Resolve level from hint or by guessing, then fetch the detail directly.
        let resolved: PodcastLevel? = {
            if !levelHint.isEmpty, let lv = PodcastLevel(rawValue: levelHint) { return lv }
            // Guess from id prefix (pipeline ids look like "easy_20260504_001")
            for lv in PodcastLevel.allCases where episodeId.hasPrefix(lv.rawValue) {
                return lv
            }
            return nil
        }()

        guard let level = resolved else { return }

        Task { @MainActor in
            // Switch the home view to that level so the user lands on the right list.
            if dataStore.selectedLevel != level {
                dataStore.selectedLevel = level
                dataStore.loadEpisodes()
            }
            if let ep = await APIService.shared.fetchEpisodeDetail(id: episodeId, level: level) {
                _ = audioPlayer.playEpisode(ep, in: dataStore.episodes)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(DataStore())
        .environment(AudioPlayer())
        .environment(SubscriptionManager())
}
