import SwiftUI
import StoreKit
import UserNotifications

struct EpisodeCompleteView: View {
    let episode: Episode
    var onNextEpisode: () -> Void
    var onSaveVocabulary: () -> Void
    var onPlayPatterns: (() -> Void)? = nil
    /// 2026-08 完成结构改革：完成页在第 1 遍后弹出，此 CTA 继续第 2-5 遍。
    var onContinueListening: (() -> Void)? = nil

    @Environment(DataStore.self) private var dataStore
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.requestReview) private var requestReview
    @State private var encounteredWords: [SavedWord] = []
    @State private var showPaywall = false
    /// 推送授权铺垫卡（2026-08 弹窗改造：授权弹窗从落地时刻挪到这里）
    @State private var showPushPrePrompt = false

    private static let pushDeclineCountKey = "pushPrePromptDeclineCount"

    var body: some View {
        ZStack(alignment: .bottom) {
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

                    // 推送授权铺垫卡：价值时刻才开口要权限（点「允许」再弹系统框，
                    // 点「暂不」不消耗系统弹窗机会，streak ≥3 天时再问一次）
                    if showPushPrePrompt {
                        pushPrePromptCard
                    }

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

                    // Today's patterns (if any) — list rows (same style as vocab rows)
                    if let patterns = episode.patterns, !patterns.isEmpty {
                        patternsSection(patterns: patterns)
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
                }
                .padding(.horizontal, 24)
                .padding(.top, 62)
                .padding(.bottom, 240)  // leave room for fixed CTA bar (3 rows)
            }

            // Fixed bottom CTAs (don't scroll with content)
            fixedBottomCTAs
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(subscriptionManager)
        }
        .onAppear {
            // Detect words from user's vocabulary that appeared in this episode.
            // This updates encounterCount + lastEncounterDate on the words, which
            // the daily notification arbiter reads on next app background.
            let newVocabWords = Set(episode.vocabulary.map { $0.word.lowercased() })
            encounteredWords = vocabularyStore.detectEncounteredWords(in: episode)
                .filter { !newVocabWords.contains($0.word.lowercased()) } // exclude this episode's own vocab
                .filter { $0.encounterCount > 1 }

            // 完播是最佳好评时机：第 3 次完播起请求系统评分弹窗（60 天冷却）
            if ReviewPrompter.shouldAsk(episodesCompleted: dataStore.episodesCompleted) {
                ReviewPrompter.recordAsked()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    requestReview()
                }
            }

            evaluatePushPrePrompt()
        }
    }

    // MARK: - Push Pre-Prompt

    /// 系统权限还没问过（notDetermined）且铺垫卡没被拒绝过（或拒绝过一次但
    /// streak 已 ≥3 天）时展示。评分弹窗和它同刻出现的概率极低（第 3 次完播
    /// 时权限一般早已决定），不做互斥。
    private func evaluatePushPrePrompt() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            let declines = UserDefaults.standard.integer(forKey: Self.pushDeclineCountKey)
            let eligible = declines == 0 || (declines == 1 && dataStore.streakDays >= 3)
            guard eligible else { return }
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.25)) { showPushPrePrompt = true }
            }
        }
    }

    private var pushPrePromptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("🔔")
                    .font(.system(size: 18))
                Text("明天新内容上线时提醒你？")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
            }
            Text("每天最多一条，可随时在设置里关闭")
                .font(.system(size: 12))
                .foregroundStyle(Color.textTertiary)

            HStack(spacing: 10) {
                Button {
                    let declines = UserDefaults.standard.integer(forKey: Self.pushDeclineCountKey)
                    let source = declines == 0 ? "first_complete" : "streak3"
                    PushService.shared.requestPushAuthorization(source: source)
                    withAnimation { showPushPrePrompt = false }
                } label: {
                    Text("好，提醒我")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 12))
                }
                Button {
                    let declines = UserDefaults.standard.integer(forKey: Self.pushDeclineCountKey)
                    UserDefaults.standard.set(declines + 1, forKey: Self.pushDeclineCountKey)
                    withAnimation { showPushPrePrompt = false }
                } label: {
                    Text("暂不")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 88)
                        .frame(height: 40)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.border, lineWidth: 1)
                        )
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primaryLight, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.appPrimary.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Patterns Section (list rows, same style as vocab rows)

    private func patternsSection(patterns: [Pattern]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("今日句型")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text("· \(patterns.count) 个")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
            }

            ForEach(patterns) { pattern in
                patternRow(pattern)
            }
        }
    }

    private func patternRow(_ pattern: Pattern) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pattern.template)
                .font(.system(size: 15, weight: .bold, design: .serif))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Text(pattern.translation)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "14B8A6"))

            Text(pattern.scene)
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

    // MARK: - Fixed Bottom CTAs

    private var fixedBottomCTAs: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.appBackground.opacity(0), Color.appBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 16)

            VStack(spacing: 10) {
                // Row 0: 再听加深（第 1 遍完成即弹完成页，2-5 遍变成这里的选项）
                if let onContinueListening {
                    Button(action: onContinueListening) {
                        HStack(spacing: 6) {
                            Image(systemName: "headphones")
                                .font(.system(size: 14, weight: .semibold))
                            Text("再听加深 · 磨耳朵模式")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
                    }
                }

                // Row 1: 播放句型讲解 | 下一集
                HStack(spacing: 10) {
                    if let patterns = episode.patterns, !patterns.isEmpty,
                       let onPlayPatterns = onPlayPatterns {
                        let firstPatternAccessible = PatternAccessGate.canAccess(
                            pattern: patterns[0],
                            parentEpisode: episode,
                            isPro: subscriptionManager.isProUser,
                            playedTodayIds: dataStore.dailyPatternIDsPlayedToday
                        )
                        Button {
                            if firstPatternAccessible {
                                onPlayPatterns()
                            } else {
                                Analytics.track(.patternPaywallView, params: [
                                    "pattern_id": patterns[0].id,
                                    "source": "complete_cta",
                                ])
                                showPaywall = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if !firstPatternAccessible {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                Text("播放句型")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(hex: "14B8A6"), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    Button(action: onNextEpisode) {
                        Text("下一集")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(onContinueListening == nil ? .white : Color.appPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                onContinueListening == nil ? Color.appPrimary : Color.primaryLight,
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                    }
                }

                // Row 2: 保存词汇 (大按钮, full width)
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
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .background(Color.appBackground)
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

            Text(word.translation)
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
