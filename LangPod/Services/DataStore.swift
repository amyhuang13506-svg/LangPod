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

    // Listening history
    var listenHistory: [ListenedEpisode] = []
    var totalListeningSeconds: Int {
        didSet { UserDefaults.standard.set(totalListeningSeconds, forKey: "totalListeningSeconds") }
    }

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let levelRaw = UserDefaults.standard.string(forKey: "selectedLevel") ?? "easy"
        self.userName = UserDefaults.standard.string(forKey: "userName") ?? "英语学习者"
        self.selectedLevel = PodcastLevel(rawValue: levelRaw) ?? .easy
        self.listeningLevel = ListeningLevel(rawValue: UserDefaults.standard.integer(forKey: "listeningLevel")) ?? .lv1
        self.episodesCompleted = UserDefaults.standard.integer(forKey: "episodesCompleted")
        self.streakDays = UserDefaults.standard.integer(forKey: "streakDays")
        let lastTs = UserDefaults.standard.double(forKey: "lastListenDate")
        self.lastListenDate = lastTs > 0 ? Date(timeIntervalSince1970: lastTs) : nil
        self.totalListeningSeconds = UserDefaults.standard.integer(forKey: "totalListeningSeconds")
        if self.streakDays == 0 { self.streakDays = 1 }
        checkStreakContinuity()
        loadListenHistory()
        loadEpisodes()
    }

    func loadEpisodes() {
        episodes = MockDataLoader.loadEpisodes(for: selectedLevel)
        currentEpisode = episodes.first
        print("📋 DataStore: Loaded \(episodes.count) episodes, first audio: \(episodes.first?.audio.english ?? "nil")")
        // TODO: Re-enable after OSS is set up
        // fetchRemoteEpisodes()
    }

    private func fetchRemoteEpisodes() {
        isLoadingEpisodes = true
        Task {
            let remoteEpisodes = await APIService.shared.fetchEpisodes(for: selectedLevel)
            await MainActor.run {
                if !remoteEpisodes.isEmpty {
                    self.episodes = remoteEpisodes
                    if self.currentEpisode == nil || self.currentEpisode?.level != self.selectedLevel.rawValue {
                        self.currentEpisode = remoteEpisodes.first
                    }
                }
                self.isLoadingEpisodes = false
            }
        }
    }

    /// Call after completing an episode to check for level up
    func completeEpisode(totalWords: Int) {
        episodesCompleted += 1
        updateStreak()

        // Record history
        if let episode = currentEpisode {
            let record = ListenedEpisode(
                episodeId: episode.id,
                title: episode.title,
                level: episode.level,
                durationSeconds: episode.durationSeconds,
                listenedAt: Date()
            )
            listenHistory.insert(record, at: 0)
            totalListeningSeconds += episode.durationSeconds
            saveListenHistory()
        }
        let newLevel = ListeningLevel.checkLevel(episodes: episodesCompleted, words: totalWords)
        if newLevel.rawValue > listeningLevel.rawValue {
            pendingLevelUp = newLevel
            listeningLevel = newLevel
        }
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
        listenHistory = history.filter { $0.listenedAt > cutoff }
        if listenHistory.count != history.count { saveListenHistory() }
    }

    private func loadMockHistory() {
        let allEpisodes = MockDataLoader.loadAllEpisodes()
        for (i, ep) in allEpisodes.enumerated() {
            let daysAgo = Double(i) * 0.5
            listenHistory.append(ListenedEpisode(
                episodeId: ep.id,
                title: ep.title,
                level: ep.level,
                durationSeconds: ep.durationSeconds,
                listenedAt: Date().addingTimeInterval(-daysAgo * 86400)
            ))
            totalListeningSeconds += ep.durationSeconds
        }
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
