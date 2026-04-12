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
                        }
                    )
                    .environment(dataStore)
                    .environment(vocabularyStore)
                    .environment(subscriptionManager)
                }
            }
            .task {
                setupPlayGate()
                // Request notification permission after first launch
                if dataStore.hasCompletedOnboarding {
                    notificationManager.requestPermission()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                dataStore.loadEpisodes()
            }
        }
    }

    private func setupPlayGate() {
        audioPlayer.playGate = { [self] episode in
            dataStore.recordPlayStart(episode: episode)

            if subscriptionManager.isProUser { return true }

            // Already played today? Allow replay without consuming a new daily slot.
            let alreadyPlayedToday = dataStore.listenHistory.contains {
                $0.episodeId == episode.id &&
                Calendar.current.isDateInToday($0.listenedAt)
            }
            if alreadyPlayedToday { return true }

            dataStore.refreshDailyCountIfNeeded()
            if dataStore.dailyEpisodesPlayed >= SubscriptionManager.freeMaxDailyEpisodes {
                return false
            }
            dataStore.recordDailyPlay()
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
            dataStore.completeEpisode(
                totalWords: vocabularyStore.totalCount,
                episode: audioPlayer.currentEpisode
            )
        }
    }
}
