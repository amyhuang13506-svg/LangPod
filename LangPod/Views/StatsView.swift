import SwiftUI

struct StatsView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AudioPlayer.self) private var audioPlayer
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var showPlayer = false
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                    streakCard
                    statsRow
                    weekProgress
                    historyList
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("记录")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .tracking(-0.5)
            Spacer()
            HStack(spacing: 4) {
                Text("Lv.\(dataStore.listeningLevel.rawValue)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
                Text(dataStore.listeningLevel.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primaryLight, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Streak Card

    private var streakCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("🔥")
                    .font(.system(size: 28))
                Text("连续 \(dataStore.streakDays) 天")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }

            HStack {
                Text(streakMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(streakColor)
                Spacer()
            }

            // Degradation warning
            if daysSinceLastListen >= 5 {
                HStack {
                    Text("再不回来等级要降了")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.danger)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(streakBorderColor, lineWidth: 1)
        )
    }

    private var daysSinceLastListen: Int {
        guard let last = dataStore.lastListenDate else { return 999 }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 999
    }

    private var listenedToday: Bool {
        guard let last = dataStore.lastListenDate else { return false }
        return Calendar.current.isDateInToday(last)
    }

    private var hoursUntilReset: Int {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) else { return 0 }
        return max(0, Int(tomorrow.timeIntervalSinceNow / 3600))
    }

    private var streakMessage: String {
        if listenedToday {
            return "今日已完成！继续保持"
        }
        if hoursUntilReset <= 3 {
            return "即将清零！还有 \(hoursUntilReset)h"
        }
        return "今天还没听！\(hoursUntilReset)h 后记录清零"
    }

    private var streakColor: Color {
        if listenedToday { return Color.success }
        if hoursUntilReset <= 3 { return Color.danger }
        return Color.warning
    }

    private var streakBorderColor: Color {
        if listenedToday { return Color.success.opacity(0.3) }
        if hoursUntilReset <= 3 { return Color.danger.opacity(0.3) }
        return Color.border
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(value: dataStore.totalListeningTimeDisplay, label: "总时长")
            statCard(value: "\(dataStore.episodesCompleted)", label: "已听集数")
            statCard(value: "\(vocabularyStore.strongWords.count)", label: "已掌握词汇")
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    // MARK: - Week Progress

    private var weekProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本周进度")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            HStack(spacing: 0) {
                ForEach(weekDays, id: \.date) { day in
                    VStack(spacing: 6) {
                        Text(day.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textTertiary)

                        Circle()
                            .fill(day.color)
                            .frame(width: 28, height: 28)
                            .overlay(
                                day.count > 0 ?
                                    Text("\(day.count)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                    : nil
                            )

                        if day.count > 0 {
                            Text("\(day.count)集")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textSecondary)
                        } else {
                            Text(" ")
                                .font(.system(size: 10))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    struct WeekDay {
        let date: Date
        let label: String
        let count: Int
        let isToday: Bool
        let isFuture: Bool

        var color: Color {
            if count > 0 { return Color.success }
            if isToday { return Color.warning }
            if isFuture { return Color.border }
            return Color.textQuaternary
        }
    }

    private var weekDays: [WeekDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let mondayOffset = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -mondayOffset, to: today) else { return [] }

        let labels = ["一", "二", "三", "四", "五", "六", "日"]

        return (0..<7).compactMap { i in
            guard let date = calendar.date(byAdding: .day, value: i, to: monday) else { return nil }
            let isToday = calendar.isDate(date, inSameDayAs: today)
            let isFuture = date > today
            let count = dataStore.listenHistory.filter {
                calendar.isDate($0.listenedAt, inSameDayAs: date)
            }.count

            return WeekDay(date: date, label: labels[i], count: count, isToday: isToday, isFuture: isFuture)
        }
    }

    // MARK: - History List

    /// Unified history entry for the 播放历史 list. Episodes + patterns share
    /// the same day grouping + star toggle + tap-to-play flow, but render
    /// differently (thumbnail vs. template card).
    private enum HistoryEntry: Identifiable {
        case episode(ListenedEpisode)
        case pattern(ListenedPattern)

        var id: String {
            switch self {
            case .episode(let e): "ep-\(e.id)"
            case .pattern(let p): "pt-\(p.id)"
            }
        }
        var listenedAt: Date {
            switch self {
            case .episode(let e): e.listenedAt
            case .pattern(let p): p.listenedAt
            }
        }
        var dayString: String {
            switch self {
            case .episode(let e): e.dayString
            case .pattern(let p): p.dayString
            }
        }
        var isStarred: Bool {
            switch self {
            case .episode(let e): e.isStarred
            case .pattern(let p): p.isStarred
            }
        }
    }

    /// All accessible episode history entries (filtered to starred if the
    /// global star toggle is on), deduped so a given episode appears once.
    private var displayEpisodes: [ListenedEpisode] {
        let source = dataStore.starredOnly ? dataStore.starredHistory : dataStore.listenHistory
        var seen = Set<String>()
        return source.filter { ep in
            if seen.contains(ep.episodeId) { return false }
            seen.insert(ep.episodeId)
            return true
        }
    }

    private var displayPatterns: [ListenedPattern] {
        let source = dataStore.starredOnly
            ? dataStore.patternHistory.filter { $0.isStarred }
            : dataStore.patternHistory
        var seen = Set<String>()
        return source.filter { p in
            if seen.contains(p.patternId) { return false }
            seen.insert(p.patternId)
            return true
        }
    }

    private var displayEntries: [HistoryEntry] {
        let episodes = displayEpisodes.map { HistoryEntry.episode($0) }
        let patterns = displayPatterns.map { HistoryEntry.pattern($0) }
        let combined: [HistoryEntry]
        switch dataStore.historyFilter {
        case .all: combined = episodes + patterns
        case .episode: combined = episodes
        case .pattern: combined = patterns
        }
        return combined.sorted { $0.listenedAt > $1.listenedAt }
    }

    private var displayEntriesByDay: [(String, [HistoryEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: displayEntries) { entry in
            calendar.startOfDay(for: entry.listenedAt)
        }
        return grouped.sorted { $0.key > $1.key }.map { (_, items) in
            let label = items.first?.dayString ?? ""
            return (label, items)
        }
    }

    private var filterSegment: some View {
        HStack(spacing: 6) {
            ForEach(DataStore.HistoryFilter.allCases, id: \.self) { f in
                let isSelected = dataStore.historyFilter == f
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        dataStore.historyFilter = f
                    }
                } label: {
                    Text(f.label)
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? .white : Color.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            isSelected ? Color.appPrimary : Color.divider,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("播放历史")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                if canPlayHistoryQueue {
                    Button { playHistoryQueue() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                            Text("顺序播放")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color.appPrimary)
                    }
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        dataStore.starredOnly.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: dataStore.starredOnly ? "star.fill" : "star")
                            .font(.system(size: 14))
                        Text(dataStore.starredOnly ? "收藏" : "全部")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(dataStore.starredOnly ? Color.warning : Color.textTertiary)
                }
            }

            filterSegment

            if displayEntries.isEmpty {
                Text(historyEmptyText)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(displayEntriesByDay, id: \.0) { dayLabel, entries in
                    Text(dayLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.top, 4)

                    ForEach(entries) { entry in
                        switch entry {
                        case .episode(let ep): historyRow(ep)
                        case .pattern(let p): patternHistoryRow(p)
                        }
                    }
                }
            }
        }
    }

    private var historyEmptyText: String {
        switch (dataStore.starredOnly, dataStore.historyFilter) {
        case (true, .pattern): "还没有收藏的句型"
        case (true, .episode): "还没有收藏的播客"
        case (true, .all): "还没有收藏记录"
        case (false, .pattern): "还没有句型播放记录"
        case (false, .episode): "还没有播客播放记录"
        case (false, .all): "还没有播放记录"
        }
    }

    /// Find the full Episode object for a history record — checks DataStore first,
    /// then constructs an Episode with proper OSS URLs from the record's metadata.
    private func episodeForRecord(_ record: ListenedEpisode) -> Episode {
        if let ep = dataStore.episodes.first(where: { $0.id == record.episodeId }) {
            return ep
        }
        // Construct with real OSS URLs derived from episode ID + level
        let base = "https://castlingo.oss-ap-southeast-1.aliyuncs.com/episodes"
        let path = "\(base)/\(record.level)/\(record.episodeId)"
        return Episode(
            id: record.episodeId, title: record.title, level: record.level,
            date: "", durationSeconds: record.durationSeconds,
            audio: EpisodeAudio(
                english: "\(path)/en.mp3",
                translationZh: "\(path)/zh.mp3"
            ),
            script: [], vocabulary: [],
            thumbnail: "\(path)/cover.jpg"
        )
    }

    private func historyRow(_ record: ListenedEpisode) -> some View {
        Button {
            let episode = episodeForRecord(record)
            let queue = displayEpisodes.map { episodeForRecord($0) }
            if audioPlayer.playEpisode(episode, in: queue) {
                showPlayer = true
            }
        } label: {
            HStack(spacing: 12) {
                historyThumbnail(record)

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    HStack(spacing: 6) {
                        Text(PodcastLevel(rawValue: record.level)?.tabName ?? "")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(levelColor(record.level))
                        Text("·")
                            .foregroundStyle(Color.textQuaternary)
                        Text("\(record.durationSeconds)秒")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Spacer()

                Button { dataStore.toggleStar(record) } label: {
                    Image(systemName: record.isStarred ? "star.fill" : "star")
                        .font(.system(size: 18))
                        .foregroundStyle(record.isStarred ? Color.warning : Color.textQuaternary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func historyThumbnail(_ record: ListenedEpisode) -> some View {
        EpisodeThumbnail(episode: episodeForRecord(record), size: 40)
    }

    /// 当前筛选视图下能否"顺序播放"。
    /// 句型模式需要至少 2 条 + 至少 1 条未被付费墙挡住。
    private var canPlayHistoryQueue: Bool {
        switch dataStore.historyFilter {
        case .all, .episode:
            return displayEpisodes.count >= 2
        case .pattern:
            return accessiblePatternItems.count >= 1 && displayPatterns.count >= 2
        }
    }

    /// 句型模式/全部模式下按历史顺序收集所有"能播的" pattern 条目。
    /// 历史记录里找不到父 episode 的 pattern 会被静默跳过（可能是切级别后内存里没加载）。
    private var accessiblePatternItems: [PlayItem] {
        displayPatterns.compactMap { record -> PlayItem? in
            guard let (p, parent) = patternWithParent(record) else { return nil }
            let ok = PatternAccessGate.canAccess(
                pattern: p,
                parentEpisode: parent,
                isPro: subscriptionManager.isProUser,
                playedTodayIds: dataStore.dailyPatternIDsPlayedToday
            )
            return ok ? .pattern(p, parentEpisode: parent) : nil
        }
    }

    private func playHistoryQueue() {
        switch dataStore.historyFilter {
        case .all, .episode:
            let queue = displayEpisodes.map { episodeForRecord($0) }
            guard let first = queue.first else { return }
            audioPlayer.playEpisode(first, in: queue)
            showPlayer = true
        case .pattern:
            let items = accessiblePatternItems
            guard case .pattern(let first, let parent) = items.first else {
                showPaywall = true
                return
            }
            audioPlayer.playPattern(first, parentEpisode: parent, in: items)
            showPlayer = true
            Analytics.track(.patternOpen, params: [
                "pattern_id": first.id,
                "episode_id": parent.id,
                "source": "history_play_all",
            ])
        }
    }

    // MARK: - Pattern Row

    /// Resolve a pattern history record back to the live Pattern + parent Episode.
    /// Returns nil when the parent episode is no longer in dataStore.episodes
    /// (e.g. the user switched channels or it rolled out of the cache) — in
    /// that case the row still renders but tapping shows a paywall / no-op.
    private func patternWithParent(_ record: ListenedPattern) -> (Pattern, Episode)? {
        guard let ep = dataStore.episodes.first(where: { $0.id == record.episodeId }),
              let p = ep.patterns?.first(where: { $0.id == record.patternId })
        else { return nil }
        return (p, ep)
    }

    private func patternHistoryRow(_ record: ListenedPattern) -> some View {
        Button {
            guard let (pattern, parent) = patternWithParent(record) else {
                showPaywall = true
                return
            }
            let accessible = PatternAccessGate.canAccess(
                pattern: pattern,
                parentEpisode: parent,
                isPro: subscriptionManager.isProUser,
                playedTodayIds: dataStore.dailyPatternIDsPlayedToday
            )
            if accessible {
                audioPlayer.playPattern(pattern, parentEpisode: parent)
                showPlayer = true
                Analytics.track(.patternOpen, params: [
                    "pattern_id": pattern.id,
                    "episode_id": parent.id,
                    "source": "history_tab",
                ])
            } else {
                showPaywall = true
            }
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(patternCardColor(record))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "quote.bubble.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(white: 0.35))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.template)
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("句型")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.appPrimary)
                        Text("·")
                            .foregroundStyle(Color.textQuaternary)
                        Text(PodcastLevel(rawValue: record.level)?.tabName ?? "")
                            .font(.system(size: 11))
                            .foregroundStyle(levelColor(record.level))
                        Text("·")
                            .foregroundStyle(Color.textQuaternary)
                        Text(record.scene)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button { dataStore.togglePatternStar(record) } label: {
                    Image(systemName: record.isStarred ? "star.fill" : "star")
                        .font(.system(size: 18))
                        .foregroundStyle(record.isStarred ? Color.warning : Color.textQuaternary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func patternCardColor(_ record: ListenedPattern) -> Color {
        if let hex = patternWithParent(record)?.0.thumbnailColor {
            return Color(hex: hex)
        }
        return Color(hex: "F1EBE1")
    }

    private func levelColor(_ level: String) -> Color {
        switch level {
        case "easy": Color.success
        case "medium": Color.appPrimary
        case "hard": Color.hardOrange
        default: Color.textTertiary
        }
    }
}

#Preview {
    StatsView()
        .environment(DataStore())
        .environment(AudioPlayer())
        .environment(VocabularyStore())
        .environment(SubscriptionManager())
}
