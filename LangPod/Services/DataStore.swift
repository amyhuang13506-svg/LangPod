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
    var totalListeningSeconds: Int {
        didSet { UserDefaults.standard.set(totalListeningSeconds, forKey: "totalListeningSeconds") }
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
        loadEpisodes()
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
    }

    func isChannelUnlocked(_ channel: PodcastLevel) -> Bool {
        listeningLevel.unlockedChannels.contains(channel)
    }

    // MARK: - Streak

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
