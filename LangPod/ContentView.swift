import SwiftUI

struct ContentView: View {
    @Environment(DataStore.self) private var dataStore

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
        } else {
            OnboardingView()
        }
    }
}

#Preview {
    ContentView()
        .environment(DataStore())
}
