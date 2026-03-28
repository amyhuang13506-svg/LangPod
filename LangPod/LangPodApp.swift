import SwiftUI

@main
struct LangPodApp: App {
    @State private var dataStore = DataStore()
    @State private var audioPlayer = AudioPlayer()
    @State private var vocabularyStore = VocabularyStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dataStore)
                .environment(audioPlayer)
                .environment(vocabularyStore)
        }
    }
}
