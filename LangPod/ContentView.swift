import SwiftUI

struct ContentView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AudioPlayer.self) private var audioPlayer
    @Environment(SubscriptionManager.self) private var subscriptionManager

    var body: some View {
        if dataStore.hasCompletedOnboarding {
            TabView {
                HomeView()
                    .tabItem {
                        Label("首页", systemImage: "headphones")
                    }
                VocabularyView()
                    .tabItem {
                        Label("词汇", systemImage: "character.book.closed")
                    }
                PatternsTabView()
                    .tabItem {
                        Label("句型", systemImage: "quote.bubble")
                    }
                ProfileView()
                    .tabItem {
                        Label("我的", systemImage: "person")
                    }
            }
            .tint(.accent)
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
        } else {
            OnboardingView()
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
