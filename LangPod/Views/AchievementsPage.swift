import SwiftUI

struct AchievementsPage: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(VocabularyStore.self) private var vocabularyStore

    struct Badge: Identifiable {
        let id: String
        let icon: String
        let name: String
        let condition: String
        let color1: String
        let color2: String
        let ringColor: String
        var unlocked: Bool = false
    }

    private var badges: [Badge] {
        let streak = dataStore.streakDays
        let totalEpisodes = dataStore.listenHistory.count
        let totalWords = vocabularyStore.totalCount
        let matchCount = vocabularyStore.words.reduce(0) { $0 + $1.matchCorrectCount }
        let sentenceCount = vocabularyStore.words.reduce(0) { $0 + $1.sentenceCorrectCount }

        return [
            Badge(id: "first_play", icon: "🎧", name: "初次播放", condition: "听完第1集",
                  color1: "60A5FA", color2: "3B82F6", ringColor: "93C5FD", unlocked: totalEpisodes >= 1),
            Badge(id: "streak_3", icon: "🔥", name: "三日坚持", condition: "连续3天",
                  color1: "FB923C", color2: "EA580C", ringColor: "FDBA74", unlocked: streak >= 3),
            Badge(id: "streak_7", icon: "⚡", name: "七日坚持", condition: "连续7天",
                  color1: "FBBF24", color2: "D97706", ringColor: "FDE68A", unlocked: streak >= 7),
            Badge(id: "streak_30", icon: "👑", name: "三十日", condition: "连续30天",
                  color1: "A78BFA", color2: "7C3AED", ringColor: "C4B5FD", unlocked: streak >= 30),
            Badge(id: "words_10", icon: "📖", name: "词汇新手", condition: "保存10词",
                  color1: "6EE7B7", color2: "10B981", ringColor: "A7F3D0", unlocked: totalWords >= 10),
            Badge(id: "words_100", icon: "📚", name: "词汇达人", condition: "保存100词",
                  color1: "34D399", color2: "059669", ringColor: "6EE7B7", unlocked: totalWords >= 100),
            Badge(id: "match_50", icon: "🎯", name: "配对高手", condition: "配对50次",
                  color1: "F472B6", color2: "DB2777", ringColor: "FBCFE8", unlocked: matchCount >= 50),
            Badge(id: "sentence_20", icon: "✍️", name: "造句达人", condition: "造句20次",
                  color1: "818CF8", color2: "4F46E5", ringColor: "A5B4FC", unlocked: sentenceCount >= 20),
            Badge(id: "easy_done", icon: "🌱", name: "初级毕业", condition: "初级听完10集",
                  color1: "86EFAC", color2: "22C55E", ringColor: "BBF7D0", unlocked: totalEpisodes >= 10),
            Badge(id: "medium_done", icon: "🚀", name: "中级毕业", condition: "中级听完10集",
                  color1: "60A5FA", color2: "2563EB", ringColor: "93C5FD", unlocked: totalEpisodes >= 20),
            Badge(id: "hard_done", icon: "💎", name: "高级毕业", condition: "高级听完10集",
                  color1: "F87171", color2: "DC2626", ringColor: "FCA5A5", unlocked: totalEpisodes >= 30),
            Badge(id: "master", icon: "🏆", name: "全能学者", condition: "解锁全部",
                  color1: "FCD34D", color2: "B45309", ringColor: "FDE68A", unlocked: false),
        ]
    }

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            let unlockedCount = badges.filter(\.unlocked).count
            Text("\(unlockedCount)/\(badges.count) 已解锁")
                .font(.system(size: 14))
                .foregroundStyle(Color.textTertiary)
                .padding(.top, 8)

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(badges) { badge in
                    badgeView(badge)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color.appBackground)
        .navigationTitle("成就徽章")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func badgeView(_ badge: Badge) -> some View {
        VStack(spacing: 6) {
            ZStack {
                // Main circle
                Circle()
                    .fill(
                        badge.unlocked
                        ? LinearGradient(
                            colors: [Color(hex: badge.color1), Color(hex: badge.color2)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(
                            colors: [Color.divider, Color(hex: "E8ECF1")],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 86, height: 86)
                    .shadow(
                        color: badge.unlocked ? Color(hex: badge.color2).opacity(0.3) : .clear,
                        radius: 8, y: 4
                    )

                // Border ring
                Circle()
                    .stroke(
                        badge.unlocked
                        ? Color(hex: badge.ringColor).opacity(0.8)
                        : Color.textQuaternary.opacity(0.6),
                        style: badge.unlocked
                        ? StrokeStyle(lineWidth: 2.5)
                        : StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
                    .frame(width: 90, height: 90)

                // Inner decorative ring
                if badge.unlocked {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        .frame(width: 72, height: 72)
                }

                // Content
                VStack(spacing: 3) {
                    Text(badge.unlocked ? badge.icon : "🔒")
                        .font(.system(size: 26))

                    Text(badge.name)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(badge.unlocked ? .white : Color.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: 100, height: 100)

            // Subtitle
            Text(badge.unlocked ? "已解锁" : badge.condition)
                .font(.system(size: 10))
                .foregroundStyle(badge.unlocked ? Color(hex: badge.color2) : Color.textQuaternary)
        }
    }
}

#Preview {
    NavigationStack {
        AchievementsPage()
            .environment(DataStore())
            .environment(VocabularyStore())
    }
}
