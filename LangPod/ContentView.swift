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
                StatsView()
                    .tabItem {
                        Label("记录", systemImage: "clock.arrow.circlepath")
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
        } else {
            OnboardingView()
        }
    }
}

#Preview {
    ContentView()
        .environment(DataStore())
        .environment(AudioPlayer())
        .environment(SubscriptionManager())
}
