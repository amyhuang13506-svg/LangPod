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
                // Reserved for future foreground resume logic
            }
        }
    }

    private func setupBackgroundCompletion() {
        // Background completion is handled by AudioPlayer.onEpisodeFinished callback
        // set in PlayerView. This method is reserved for future background-specific logic.
    }
}
