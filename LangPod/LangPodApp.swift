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

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .bottom) {
                ContentView()
                    .environment(dataStore)
                    .environment(audioPlayer)
                    .environment(vocabularyStore)
                    .environment(appState)

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
                }
            }
            .task {
                setupBackgroundCompletion()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // When app comes back, check if we need to auto-play next
                if audioPlayer.pendingAutoNext && audioPlayer.phase == .finished {
                    audioPlayer.pendingAutoNext = false
                    audioPlayer.skipToNextEpisode()
                }
            }
        }
    }

    private func setupBackgroundCompletion() {
        audioPlayer.onEpisodeFinishedBackground = {
            guard let episode = audioPlayer.currentEpisode else { return }

            // Auto-save vocabulary
            vocabularyStore.saveWords(from: episode)

            // Record completion
            dataStore.completeEpisode(totalWords: vocabularyStore.totalCount, episode: episode)

            // Store for potential complete page view
            appState.completedEpisode = episode

            // Show toast
            appState.toastTitle = episode.title
            appState.toastWordCount = episode.vocabulary.count
            withAnimation(.easeInOut(duration: 0.3)) {
                appState.showToast = true
            }

            // Hide toast after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    appState.showToast = false
                }
            }
            // Note: auto play next is handled directly by AudioPlayer.advancePhase()
        }
    }
}
