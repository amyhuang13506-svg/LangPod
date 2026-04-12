import SwiftUI

struct EpisodeCompleteView: View {
    let episode: Episode
    var onNextEpisode: () -> Void
    var onSaveVocabulary: () -> Void

    @Environment(DataStore.self) private var dataStore
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var encounteredWords: [SavedWord] = []
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Header
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.successLight)
                                .frame(width: 32, height: 32)
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.success)
                        }
                        Text("本集完成！")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                    }

                    // Stats row
                    statsRow

                    // Encountered words (recycled from previous episodes)
                    if !encounteredWords.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color(hex: "8B5CF6"))
                                Text("你的旧词又出现了")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Color.textPrimary)
                            }

                            ForEach(encounteredWords) { word in
                                HStack(spacing: 10) {
                                    Text(word.word)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Color(hex: "8B5CF6"))
                                    Spacer()
                                    Text("已听到 \(word.encounterCount) 次")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.textTertiary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color(hex: "F5F3FF"), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }

                    // Vocabulary section
                    Text("本集重点生词")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    let visibleVocab = subscriptionManager.isProUser
                        ? episode.vocabulary
                        : Array(episode.vocabulary.prefix(SubscriptionManager.freeMaxVocabPerEpisode))

                    ForEach(visibleVocab) { word in
                        vocabularyCard(word)
                    }

                    // Locked vocab hint for free users
                    if !subscriptionManager.isProUser && episode.vocabulary.count > SubscriptionManager.freeMaxVocabPerEpisode {
                        Button { showPaywall = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.warning)
                                Text("解锁 Pro 查看全部 \(episode.vocabulary.count) 个生词")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.appPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.primaryLight, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.appPrimary.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }

                    // Action buttons
                    VStack(spacing: 10) {
                        Button(action: onNextEpisode) {
                            Text("下一集")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
                        }

                        Button(action: onSaveVocabulary) {
                            Text("保存到我的词汇")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.appPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.border, lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 62)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(subscriptionManager)
        }
        .onAppear {
            // Detect words from user's vocabulary that appeared in this episode
            let newVocabWords = Set(episode.vocabulary.map { $0.word.lowercased() })
            encounteredWords = vocabularyStore.detectEncounteredWords(in: episode)
                .filter { !newVocabWords.contains($0.word.lowercased()) } // exclude this episode's own vocab
                .filter { $0.encounterCount > 1 }

            // Schedule local notification for encountered words
            if !encounteredWords.isEmpty {
                NotificationManager().scheduleEncounterReminder(
                    words: encounteredWords.map(\.word)
                )
            }
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 0) {
            statItem(value: "+\(episode.vocabulary.count)", label: "新词", color: Color.appPrimary)
            divider
            statItem(value: "\(vocabularyStore.totalCount)", label: "累计", color: Color.textPrimary)
            divider
            statItem(value: "🔥\(dataStore.streakDays)天", label: "连续", color: Color.warning)
            divider
            statItem(value: levelProgressText, label: levelProgressLabel, color: Color.appPrimary)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(width: 1, height: 32)
    }

    private var levelProgressText: String {
        if dataStore.listeningLevel.next != nil,
           let remaining = dataStore.listeningLevel.episodesUntilNext(current: dataStore.episodesCompleted) {
            return "差\(remaining)集"
        }
        return "已满级"
    }

    private var levelProgressLabel: String {
        if let next = dataStore.listeningLevel.next {
            return "升Lv.\(next.rawValue)"
        }
        return "Lv.5"
    }

    // MARK: - Vocabulary Card

    private func vocabularyCard(_ word: VocabularyItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(word.word)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(word.phonetic)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
            }

            Text(word.translationZh)
                .font(.system(size: 13))
                .foregroundStyle(Color.appPrimary)

            Text("\"\(word.example)\"")
                .font(.system(size: 12).italic())
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.border, lineWidth: 1)
        )
    }
}

#Preview {
    let episodes = MockDataLoader.loadEpisodes(for: .medium)
    EpisodeCompleteView(
        episode: episodes[0],
        onNextEpisode: {},
        onSaveVocabulary: {}
    )
    .environment(DataStore())
    .environment(SubscriptionManager())
}
