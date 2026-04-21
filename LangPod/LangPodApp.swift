import SwiftUI

@Observable
class AppState {
    var showToast = false
    var showCompletePage = false
    var toastTitle = ""
    var toastWordCount = 0
    var completedEpisode: Episode?
}

@main
struct LangPodApp: App {
    @State private var dataStore = DataStore()
    @State private var audioPlayer = AudioPlayer()
    @State private var vocabularyStore = VocabularyStore()
    @State private var appState = AppState()
    @State private var notificationManager = NotificationManager()
    @State private var subscriptionManager = SubscriptionManager()

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
            .task {
                setupPlayGate()
                // Deferred analytics bootstrap: runs after first frame.
                Analytics.setup()
                Analytics.track(.appLaunch)
                // Request notification permission after first launch
                if dataStore.hasCompletedOnboarding {
                    notificationManager.requestPermission()
                }
                refreshDailyNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                dataStore.loadEpisodes()
                refreshDailyNotification()
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

        return NotificationContext(
            streakDays: dataStore.streakDays,
            lastListenDate: dataStore.lastListenDate,
            listenedToday: listenedToday,
            newestEpisodeTitle: newEpisode?.title,
            hasNewEpisodeToday: newEpisode != nil,
            forgottenWordsCount: forgottenCount,
            recentEncounteredWords: recentEncounters,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute
        )
    }
}
