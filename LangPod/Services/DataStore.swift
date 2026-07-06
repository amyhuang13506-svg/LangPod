import SwiftUI

@Observable
class DataStore {
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    var selectedLevel: PodcastLevel {
        didSet {
            UserDefaults.standard.set(selectedLevel.rawValue, forKey: "selectedLevel")
            loadEpisodes()
        }
    }

    var userName: String {
        didSet { UserDefaults.standard.set(userName, forKey: "userName") }
    }

    var episodes: [Episode] = []
    var currentEpisode: Episode?
    var isLoadingEpisodes = false

    /// 真实大佬演讲/keynote 列表，YouTube 嵌入流式播放（不托管）。
    /// 数据来自 bundle 的 raw_podcasts.json，后续可改为服务器拉取。
    var rawPodcasts: [RawPodcast] = []

    /// Set by ContentView when a remote push targets a raw podcast (id starts
    /// with `raw-`). HomeView observes this and presents the player.
    /// Single-shot: HomeView clears it back to nil once consumed.
    var pendingRawPodcastId: String? = nil


    // Streak system
    var streakDays: Int {
        didSet { UserDefaults.standard.set(streakDays, forKey: "streakDays") }
    }
    var lastListenDate: Date? {
        didSet { UserDefaults.standard.set(lastListenDate?.timeIntervalSince1970 ?? 0, forKey: "lastListenDate") }
    }
    var streakMilestone: Int? // Set when hitting 7/30/100 day milestones

    // Listening Level System
    var listeningLevel: ListeningLevel {
        didSet { UserDefaults.standard.set(listeningLevel.rawValue, forKey: "listeningLevel") }
    }
    var episodesCompleted: Int {
        didSet { UserDefaults.standard.set(episodesCompleted, forKey: "episodesCompleted") }
    }
    var pendingLevelUp: ListeningLevel?

    // Daily episode count (for free tier limit)
    var dailyEpisodesPlayed: Int {
        didSet { UserDefaults.standard.set(dailyEpisodesPlayed, forKey: "dailyEpisodesPlayed") }
    }
    private(set) var dailyEpisodesDate: String {
        didSet { UserDefaults.standard.set(dailyEpisodesDate, forKey: "dailyEpisodesDate") }
    }

    // Daily pattern plays (free tier: up to freeMaxDailyPatterns unique pattern IDs/day).
    // Replaying a pattern already in this set does NOT consume additional quota.
    var dailyPatternIDsPlayedToday: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(dailyPatternIDsPlayedToday), forKey: "dailyPatternIDsPlayedToday")
        }
    }
    private(set) var dailyPatternsDate: String {
        didSet { UserDefaults.standard.set(dailyPatternsDate, forKey: "dailyPatternsDate") }
    }

    // Listening history
    var listenHistory: [ListenedEpisode] = []
    var patternHistory: [ListenedPattern] = []
    var rawPodcastHistory: [ListenedRawPodcast] = []
    var totalListeningSeconds: Int {
        didSet { UserDefaults.standard.set(totalListeningSeconds, forKey: "totalListeningSeconds") }
    }

    /// 记录页播放历史的分段筛选：全部 / 播客 / 句型 / 视频
    var historyFilter: HistoryFilter = .all

    enum HistoryFilter: String, CaseIterable {
        case all, episode, pattern, raw
        var label: String {
            switch self {
            case .all: "全部"
            case .episode: "播客"
            case .pattern: "句型"
            case .raw: "视频"
            }
        }
    }

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let levelRaw = UserDefaults.standard.string(forKey: "selectedLevel") ?? "easy"
        self.userName = UserDefaults.standard.string(forKey: "userName") ?? "Explorer"
        self.selectedLevel = PodcastLevel(rawValue: levelRaw) ?? .easy
        self.listeningLevel = ListeningLevel(rawValue: UserDefaults.standard.integer(forKey: "listeningLevel")) ?? .lv1
        self.episodesCompleted = UserDefaults.standard.integer(forKey: "episodesCompleted")
        self.streakDays = UserDefaults.standard.integer(forKey: "streakDays")
        let lastTs = UserDefaults.standard.double(forKey: "lastListenDate")
        self.lastListenDate = lastTs > 0 ? Date(timeIntervalSince1970: lastTs) : nil
        self.totalListeningSeconds = UserDefaults.standard.integer(forKey: "totalListeningSeconds")
        self.dailyEpisodesPlayed = UserDefaults.standard.integer(forKey: "dailyEpisodesPlayed")
        self.dailyEpisodesDate = UserDefaults.standard.string(forKey: "dailyEpisodesDate") ?? ""
        let savedPatternIds = UserDefaults.standard.array(forKey: "dailyPatternIDsPlayedToday") as? [String] ?? []
        self.dailyPatternIDsPlayedToday = Set(savedPatternIds)
        self.dailyPatternsDate = UserDefaults.standard.string(forKey: "dailyPatternsDate") ?? ""
        if self.streakDays == 0 { self.streakDays = 1 }
        refreshDailyCountIfNeeded()
        checkStreakContinuity()
        loadListenHistory()
        loadPatternHistory()
        loadRawPodcastHistory()
        loadEpisodes()
        loadRawPodcasts()
    }

    private func loadRawPodcasts() {
        // 三层 fallback：磁盘缓存（最快）→ bundle 种子（首次启动）→ 服务器（最新）
        if let cached = APIService.shared.loadCachedRawPodcastsSync() {
            rawPodcasts = cached
        } else if let url = Bundle.main.url(forResource: "raw_podcasts", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let items = try? JSONDecoder().decode([RawPodcast].self, from: data) {
            rawPodcasts = items
        } else {
            rawPodcasts = []
        }
        fetchRemoteRawPodcasts()
    }

    private func fetchRemoteRawPodcasts() {
        Task {
            guard let remote = await APIService.shared.fetchRawPodcasts(), !remote.isEmpty else {
                return
            }
            await MainActor.run {
                self.rawPodcasts = remote
            }
        }
    }

    /// Force-refresh the master list from OSS. Used by the deep-link path so a
    /// just-pushed item that isn't in our local cache yet becomes visible
    /// before HomeView's onChange handler tries to look it up.
    @MainActor
    func refreshRawPodcastsFromRemote() async {
        guard let remote = await APIService.shared.fetchRawPodcasts(), !remote.isEmpty else {
            return
        }
        self.rawPodcasts = remote
    }

    /// 反向查找：Episode 是哪条「硅谷原声」的解读版本？
    /// 优先用 episode.sourcePodcastId（pipeline 写入），fallback 走 RawPodcast.relatedEpisodeIds。
    func sourcePodcast(for episode: Episode) -> RawPodcast? {
        if let id = episode.sourcePodcastId {
            return rawPodcasts.first { $0.id == id }
        }
        return rawPodcasts.first { $0.relatedEpisodeIds?.contains(episode.id) == true }
    }

    func loadEpisodes() {
        // Instant display: prefer disk cache, fall back to bundled mock data
        if let cached = APIService.shared.loadCachedEpisodesSync(for: selectedLevel) {
            episodes = cached
        } else {
            episodes = MockDataLoader.loadEpisodes(for: selectedLevel)
        }
        let today = DateFormatter.episodeDate.string(from: Date())
        currentEpisode = episodes.last(where: { $0.date == today }) ?? episodes.last
        fetchRemoteEpisodes()
    }

    private func fetchRemoteEpisodes() {
        isLoadingEpisodes = true
        Task {
            let remoteEpisodes = await APIService.shared.fetchEpisodes(for: selectedLevel)
            await MainActor.run {
                if !remoteEpisodes.isEmpty {
                    self.episodes = remoteEpisodes
                    let today = DateFormatter.episodeDate.string(from: Date())
                    self.currentEpisode = remoteEpisodes.last(where: { $0.date == today }) ?? remoteEpisodes.last
                }
                self.isLoadingEpisodes = false
            }
        }
    }

    /// Lazy-load full episode detail (script + vocabulary) and update the episodes array.
    /// Called when user starts playing a lightweight episode.
    func fetchEpisodeDetail(id: String) async -> Episode? {
        guard let idx = episodes.firstIndex(where: { $0.id == id }) else { return nil }
        let level = episodes[idx].podcastLevel ?? selectedLevel
        guard let detail = await APIService.shared.fetchEpisodeDetail(id: id, level: level) else {
            return nil
        }
        await MainActor.run {
            if let i = self.episodes.firstIndex(where: { $0.id == id }) {
                self.episodes[i] = detail
            }
        }
        return detail
    }

    /// Call after completing an episode to check for level up
    func refreshDailyCountIfNeeded() {
        let today = DateFormatter.episodeDate.string(from: Date())
        if dailyEpisodesDate != today {
            dailyEpisodesPlayed = 0
            dailyEpisodesDate = today
        }
        if dailyPatternsDate != today {
            dailyPatternIDsPlayedToday = []
            dailyPatternsDate = today
        }
    }

    func recordDailyPlay() {
        refreshDailyCountIfNeeded()
        dailyEpisodesPlayed += 1
    }

    /// Record a pattern play. Idempotent: replays of the same pattern ID don't
    /// consume additional quota. Call this when a free user actually begins
    /// playing a pattern (Pro users are uncapped so this is a no-op for them).
    func recordPatternPlayed(_ patternId: String) {
        refreshDailyCountIfNeeded()
        dailyPatternIDsPlayedToday.insert(patternId)
        recordPatternHistory(patternId: patternId)
    }

    /// Append (or dedupe) a pattern-history entry. Same pattern on same day
    /// keeps only the latest entry so the 播放历史 list stays tidy.
    private func recordPatternHistory(patternId: String) {
        guard let (pattern, episode) = findPatternWithParent(id: patternId) else { return }

        let alreadyToday = patternHistory.contains {
            $0.patternId == patternId &&
            Calendar.current.isDateInToday($0.listenedAt)
        }
        guard !alreadyToday else { return }

        let record = ListenedPattern(
            patternId: pattern.id,
            episodeId: pattern.episodeId,
            template: pattern.template,
            translationZh: pattern.translationZh,
            scene: pattern.scene,
            level: episode.level,
            durationSeconds: pattern.durationSeconds,
            listenedAt: Date()
        )
        patternHistory.insert(record, at: 0)
        savePatternHistory()
    }

    private func findPatternWithParent(id: String) -> (Pattern, Episode)? {
        for ep in episodes {
            if let p = ep.patterns?.first(where: { $0.id == id }) {
                return (p, ep)
            }
        }
        return nil
    }

    /// Record a history entry as soon as the user starts playing a new episode.
    /// Also updates streak immediately so "今天已完成" shows without waiting for completion.
    /// Deduplicates: same episode on the same day won't create a second entry.
    func recordPlayStart(episode: Episode) {
        // Update streak on play start (not just on episode completion)
        updateStreak()

        let dominated = listenHistory.contains {
            $0.episodeId == episode.id &&
            Calendar.current.isDateInToday($0.listenedAt)
        }
        guard !dominated else { return }

        let record = ListenedEpisode(
            episodeId: episode.id,
            title: episode.title,
            level: episode.level,
            durationSeconds: episode.durationSeconds,
            listenedAt: Date()
        )
        listenHistory.insert(record, at: 0)
        saveListenHistory()

        Analytics.track(.episodePlayStart, params: [
            "episode_id": episode.id,
            "level": episode.level,
            "streak_day": "\(streakDays)"
        ])
    }

    /// Called when all rounds finish. Updates listening time and level progress.
    /// History + streak were already recorded in recordPlayStart.
    func completeEpisode(totalWords: Int, episode: Episode? = nil) {
        episodesCompleted += 1

        if let ep = episode ?? currentEpisode {
            totalListeningSeconds += ep.durationSeconds
        }
        let newLevel = ListeningLevel.checkLevel(episodes: episodesCompleted, words: totalWords)
        let didLevelUp = newLevel.rawValue > listeningLevel.rawValue
        if didLevelUp {
            pendingLevelUp = newLevel
            listeningLevel = newLevel
        }

        Analytics.track(.episodeComplete, params: [
            "episode_id": (episode ?? currentEpisode)?.id ?? "unknown",
            "level": (episode ?? currentEpisode)?.level ?? "unknown",
            "total_completed": "\(episodesCompleted)",
            "level_up": didLevelUp ? "1" : "0"
        ])

        // 首次完播 = 真·Aha 时刻，作为 FB 投放的激活信号（幂等，每台设备只报一次）。
        // 现有 episode_complete 每次都打，这个只报首次，CPI 质量分层更纯。
        let firstCompleteKey = "analytics_first_episode_complete_sent"
        if !UserDefaults.standard.bool(forKey: firstCompleteKey) {
            UserDefaults.standard.set(true, forKey: firstCompleteKey)
            Analytics.track(.firstEpisodeComplete, params: [
                "level": (episode ?? currentEpisode)?.level ?? "unknown"
            ])
        }

        // 每日任务：完整听完一集（挂方法体内，不挂 onEpisodeFinished 闭包——那有 3 份副本互相覆盖）
        NotificationCenter.default.post(
            name: .taskEventEpisodeCompleted,
            object: nil,
            userInfo: ["episode_id": (episode ?? currentEpisode)?.id ?? ""]
        )
    }

    func isChannelUnlocked(_ channel: PodcastLevel) -> Bool {
        listeningLevel.unlockedChannels.contains(channel)
    }

    // MARK: - Streak

    /// TaskEngine 用的公开包装：任务达成（含练习/课堂/句型等非听力任务）也点火苗。
    /// lastListenDate 同步更新，推送仲裁不会误报断连。
    func markStreakActivity() { updateStreak() }

    private func updateStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let last = lastListenDate {
            let lastDay = calendar.startOfDay(for: last)
            if lastDay == today {
                // Already listened today, no change
                return
            }
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            if lastDay == yesterday {
                // Consecutive day
                streakDays += 1
            } else {
                // Streak broken
                streakDays = 1
            }
        } else {
            streakDays = 1
        }

        lastListenDate = Date()

        // Check milestones
        let milestones = [7, 30, 100]
        if milestones.contains(streakDays) {
            streakMilestone = streakDays
        }
    }

    // MARK: - Listen History

    func saveListenHistoryPublic() { saveListenHistory() }

    private func saveListenHistory() {
        guard let data = try? JSONEncoder().encode(listenHistory) else { return }
        UserDefaults.standard.set(data, forKey: "listenHistory")
    }

    var starredOnly = false

    var starredHistory: [ListenedEpisode] {
        listenHistory.filter { $0.isStarred }
    }

    func toggleStar(_ record: ListenedEpisode) {
        guard let idx = listenHistory.firstIndex(where: { $0.id == record.id }) else { return }
        listenHistory[idx].isStarred.toggle()
        saveListenHistory()
    }

    func deleteHistory(_ record: ListenedEpisode) {
        listenHistory.removeAll { $0.id == record.id }
        saveListenHistory()
    }

    private let historyRetentionDays = 15

    private func loadListenHistory() {
        guard let data = UserDefaults.standard.data(forKey: "listenHistory"),
              let history = try? JSONDecoder().decode([ListenedEpisode].self, from: data) else {
            loadMockHistory()
            return
        }
        let cutoff = Date().addingTimeInterval(-Double(historyRetentionDays) * 86400)
        listenHistory = history.filter { $0.isStarred || $0.listenedAt > cutoff }
        if listenHistory.count != history.count { saveListenHistory() }
    }

    private func loadMockHistory() {
        // Start with empty history — only real user data
        listenHistory = []
        saveListenHistory()
    }

    // MARK: - Pattern History

    func togglePatternStar(_ record: ListenedPattern) {
        guard let idx = patternHistory.firstIndex(where: { $0.id == record.id }) else { return }
        patternHistory[idx].isStarred.toggle()
        savePatternHistory()
    }

    private func savePatternHistory() {
        guard let data = try? JSONEncoder().encode(patternHistory) else { return }
        UserDefaults.standard.set(data, forKey: "patternHistory")
    }

    private func loadPatternHistory() {
        guard let data = UserDefaults.standard.data(forKey: "patternHistory"),
              let history = try? JSONDecoder().decode([ListenedPattern].self, from: data) else {
            patternHistory = []
            return
        }
        let cutoff = Date().addingTimeInterval(-Double(historyRetentionDays) * 86400)
        patternHistory = history.filter { $0.isStarred || $0.listenedAt > cutoff }
        if patternHistory.count != history.count { savePatternHistory() }
    }

    // MARK: - Raw Podcast History (硅谷原声)

    /// 用户进入「硅谷原声」播放页就记一条历史 + 推 streak。同一条同一天去重，
    /// 跟 episode/pattern 一致。RawPodcastPlayerView.onAppear 调这个。
    func recordRawPodcastPlayStart(_ podcast: RawPodcast) {
        updateStreak()

        let alreadyToday = rawPodcastHistory.contains {
            $0.podcastId == podcast.id &&
            Calendar.current.isDateInToday($0.listenedAt)
        }
        guard !alreadyToday else { return }

        let record = ListenedRawPodcast(
            podcastId: podcast.id,
            title: podcast.title,
            speaker: podcast.speaker,
            mediaType: podcast.mediaType.rawValue,
            thumbnail: podcast.displayThumbnailUrl,
            durationSeconds: podcast.durationSeconds,
            listenedAt: Date()
        )
        rawPodcastHistory.insert(record, at: 0)
        saveRawPodcastHistory()
    }

    func toggleRawPodcastStar(_ record: ListenedRawPodcast) {
        guard let idx = rawPodcastHistory.firstIndex(where: { $0.id == record.id }) else { return }
        rawPodcastHistory[idx].isStarred.toggle()
        saveRawPodcastHistory()
    }

    private func saveRawPodcastHistory() {
        guard let data = try? JSONEncoder().encode(rawPodcastHistory) else { return }
        UserDefaults.standard.set(data, forKey: "rawPodcastHistory")
    }

    private func loadRawPodcastHistory() {
        guard let data = UserDefaults.standard.data(forKey: "rawPodcastHistory"),
              let history = try? JSONDecoder().decode([ListenedRawPodcast].self, from: data) else {
            rawPodcastHistory = []
            return
        }
        let cutoff = Date().addingTimeInterval(-Double(historyRetentionDays) * 86400)
        rawPodcastHistory = history.filter { $0.isStarred || $0.listenedAt > cutoff }
        if rawPodcastHistory.count != history.count { saveRawPodcastHistory() }
    }

    var totalListeningTimeDisplay: String {
        let hours = totalListeningSeconds / 3600
        let minutes = (totalListeningSeconds % 3600) / 60
        if hours > 0 { return "\(hours).\(minutes / 6)h" }
        return "\(minutes)min"
    }

    /// Group history by day for display
    var historyByDay: [(String, [ListenedEpisode])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: listenHistory) { episode in
            calendar.startOfDay(for: episode.listenedAt)
        }
        return grouped.sorted { $0.key > $1.key }.map { (date, episodes) in
            let label = episodes.first?.dayString ?? ""
            return (label, episodes)
        }
    }

    private func checkStreakContinuity() {
        guard let last = lastListenDate else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastDay = calendar.startOfDay(for: last)
        let daysDiff = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        if daysDiff > 1 {
            // Streak broken, reset to 1 (today is a fresh start)
            streakDays = 1
        }
    }
}
