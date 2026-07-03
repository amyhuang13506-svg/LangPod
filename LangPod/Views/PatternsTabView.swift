import SwiftUI

/// 句型 tab 主页（替代原「记录」页）：每日句型讲解以文本形式集中展现。
/// 结构仿词汇 tab：居中标题 + 右上「我的」（我的句子收藏）。
struct PatternsTabView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(SentenceStore.self) private var sentenceStore

    @State private var selected: PatternDetailTarget?
    @State private var showMySentences = false
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(groupedByDate, id: \.date) { group in
                            section(for: group)
                        }
                        if groupedByDate.isEmpty {
                            emptyState
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 60)
                }
            }
        }
        .sheet(item: $selected) { target in
            PatternTextDetailView(pattern: target.pattern, parentEpisode: target.parent)
                .environment(sentenceStore)
        }
        .fullScreenCover(isPresented: $showMySentences) {
            MySentencesView()
                .environment(sentenceStore)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(subscriptionManager)
        }
    }

    // MARK: - Header（居中标题 + 右上我的）

    private var header: some View {
        ZStack {
            Text("句型")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .tracking(-0.3)

            HStack {
                Spacer()
                Button { showMySentences = true } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 16))
                        Text("我的")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Color.appPrimary)
                }
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 24)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Grouping（复用往期回顾的分组逻辑）

    private struct PatternGroup {
        let date: String
        let dateDisplay: String
        let items: [(pattern: Pattern, parent: Episode)]
    }

    private var groupedByDate: [PatternGroup] {
        var byDate: [String: [(Pattern, Episode)]] = [:]
        for ep in dataStore.episodes {
            guard let patterns = ep.patterns, !patterns.isEmpty else { continue }
            byDate[ep.date, default: []].append(contentsOf: patterns.map { ($0, ep) })
        }
        let sorted = byDate.keys.sorted(by: >)
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return sorted.map { date in
            let display = DateFormatter.episodeDate.date(from: date).map { formatter.string(from: $0) } ?? date
            return PatternGroup(date: date, dateDisplay: display, items: byDate[date] ?? [])
        }
    }

    // MARK: - Section & Card

    @ViewBuilder
    private func section(for group: PatternGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(group.dateDisplay)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                if PatternAccessGate.isToday(group.date) {
                    Text("今日")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
            }

            ForEach(group.items, id: \.pattern.id) { item in
                patternCard(pattern: item.pattern, parent: item.parent, locked: isLocked(item.pattern, item.parent))
            }
        }
    }

    private func patternCard(pattern: Pattern, parent: Episode, locked: Bool) -> some View {
        Button {
            if locked {
                Analytics.track(.patternPaywallView, params: [
                    "pattern_id": pattern.id, "source": "patterns_tab",
                ])
                showPaywall = true
            } else {
                Analytics.track(.patternOpen, params: [
                    "pattern_id": pattern.id, "episode_id": parent.id, "source": "patterns_tab",
                ])
                selected = PatternDetailTarget(pattern: pattern, parent: parent)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(pattern.template)
                        .font(.system(size: 19, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.warning)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textQuaternary)
                    }
                }
                Text(pattern.translationZh)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
                HStack(spacing: 6) {
                    Text(pattern.scene)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.gold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.warningLight))
                        .lineLimit(1)
                    Spacer()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func isLocked(_ pattern: Pattern, _ parent: Episode) -> Bool {
        !PatternAccessGate.canAccess(
            pattern: pattern,
            parentEpisode: parent,
            isPro: subscriptionManager.isProUser,
            playedTodayIds: dataStore.dailyPatternIDsPlayedToday
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 36))
                .foregroundStyle(Color.textTertiary)
            Text("暂无句型")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            Text("随着每日播客更新，句型讲解会陆续积累")
                .font(.system(size: 12))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

/// sheet(item:) 需要 Identifiable 的组合目标
struct PatternDetailTarget: Identifiable {
    let pattern: Pattern
    let parent: Episode
    var id: String { pattern.id }
}

// MARK: - 句型文本详情

/// 句型讲解的纯文本呈现（音频为辅）：讲解正文分段 + 3 个例句
/// （例句 🔊 = 讲解音频按时间戳截段播放，＋ = 加入我的句子）。
struct PatternTextDetailView: View {
    let pattern: Pattern
    let parentEpisode: Episode

    @Environment(\.dismiss) private var dismiss
    @Environment(SentenceStore.self) private var sentenceStore

    /// 例句（en + zh 前缀 + 截段时间戳），新数据从讲解稿取，老数据回落 example_sentences
    private struct ExampleItem: Identifiable {
        let english: String
        let chinese: String
        let start: Double?
        let end: Double?
        var id: String { english }
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    headerBlock
                    explainerBlock
                    examplesBlock
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pattern.template)
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(Color.textPrimary)
            Text(pattern.translationZh)
                .font(.system(size: 15))
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 8) {
                Text(pattern.scene)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.gold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.warningLight))
                Button {
                    LessonAudioPlayer.shared.play(pattern.audioUrl) {}
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill").font(.system(size: 10))
                        Text("播放讲解").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.appPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primaryLight))
                }
                Spacer()
            }
        }
    }

    // MARK: - 讲解正文（按 section 分段渲染）

    private var explainerBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(explainerSections, id: \.section) { block in
                VStack(alignment: .leading, spacing: 6) {
                    Text(block.section.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.appPrimary)
                    ForEach(Array(block.paragraphs.enumerated()), id: \.offset) { _, para in
                        VStack(alignment: .leading, spacing: 3) {
                            if !para.zh.isEmpty {
                                Text(para.zh)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.bodyText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !para.en.isEmpty {
                                Text(para.en)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private struct SectionBlock {
        let section: PatternSection
        let paragraphs: [(zh: String, en: String)]
    }

    /// 正文只展示讲解性段落（读音/跟读/意思/场景），例句段落单独在下方成块。
    /// 跟读段的 3 次重复在文本形态下去重只留一次。
    private var explainerSections: [SectionBlock] {
        let textSections: [PatternSection] = [.pronunciation, .pronunciationDrill, .meaning, .sceneAndFeeling]
        return textSections.compactMap { section in
            let lines = pattern.explainerScript.filter { $0.section == section }
            guard !lines.isEmpty else { return nil }
            var paragraphs: [(zh: String, en: String)] = []
            var seenEn = Set<String>()
            for line in lines {
                let en = line.textEn.trimmingCharacters(in: .whitespaces)
                if !en.isEmpty {
                    if seenEn.contains(en) { continue }  // 跟读重复 3 次 → 文本只留 1 次
                    seenEn.insert(en)
                }
                paragraphs.append((zh: line.textZh, en: en))
            }
            return SectionBlock(section: section, paragraphs: paragraphs)
        }
    }

    // MARK: - 例句

    private var examplesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("💬 例句")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            ForEach(examples) { example in
                exampleRow(example)
            }
        }
    }

    private func exampleRow(_ example: ExampleItem) -> some View {
        let saved = sentenceStore.isSaved(example.english)
        return HStack(alignment: .top, spacing: 10) {
            Button {
                LessonAudioPlayer.shared.play(pattern.audioUrl, from: example.start, to: example.end) {
                    WordSpeaker.shared.speakSentence(example.english)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(example.english)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.appPrimary)
                            .padding(.top, 3)
                    }
                    if !example.chinese.isEmpty {
                        Text(example.chinese)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                guard !saved else { return }
                let added = sentenceStore.add(SavedSentence(
                    english: example.english,
                    chinese: example.chinese,
                    scene: pattern.scene,
                    source: "pattern",
                    sourceLabel: pattern.template,
                    audioUrl: pattern.audioUrl,
                    audioStart: example.start,
                    audioEnd: example.end,
                    savedDate: Date()
                ))
                if added {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } label: {
                Image(systemName: saved ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(saved ? Color.success : Color.textQuaternary)
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    /// 新数据：讲解稿 example1/2/3 段（text_en + 同段 text_zh 前缀 + 时间戳截段）
    /// 老数据：example_sentences 数组（无时间戳 → 播放走 TTS 兜底）
    private var examples: [ExampleItem] {
        let exampleSections: [PatternSection] = [.example1, .example2, .example3]
        var items: [ExampleItem] = []
        for section in exampleSections {
            let lines = pattern.explainerScript.filter { $0.section == section }
            guard let enLine = lines.first(where: { !$0.textEn.trimmingCharacters(in: .whitespaces).isEmpty }) else { continue }
            let zh = lines.filter { !$0.textZh.isEmpty }.map(\.textZh).joined()
            items.append(ExampleItem(
                english: enLine.textEn.trimmingCharacters(in: .whitespaces),
                chinese: zh,
                start: enLine.start,
                end: enLine.end
            ))
        }
        if items.isEmpty {
            items = pattern.exampleSentences.map {
                ExampleItem(english: $0.english, chinese: $0.chinese, start: nil, end: nil)
            }
        }
        return items
    }
}
