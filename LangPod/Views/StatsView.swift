import SwiftUI

struct StatsView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AudioPlayer.self) private var audioPlayer
    @Environment(VocabularyStore.self) private var vocabularyStore
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

    private var displayHistory: [ListenedEpisode] {
        let source = dataStore.starredOnly ? dataStore.starredHistory : dataStore.listenHistory
        // Deduplicate: keep only the most recent record per episode
        var seen = Set<String>()
        return source.filter { ep in
            if seen.contains(ep.episodeId) { return false }
            seen.insert(ep.episodeId)
            return true
        }
    }

    private var displayHistoryByDay: [(String, [ListenedEpisode])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: displayHistory) { episode in
            calendar.startOfDay(for: episode.listenedAt)
        }
        return grouped.sorted { $0.key > $1.key }.map { (_, episodes) in
            let label = episodes.first?.dayString ?? ""
            return (label, episodes)
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("播放历史")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                if displayHistory.count >= 2 {
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

            if displayHistory.isEmpty {
                Text(dataStore.starredOnly ? "还没有收藏的播客" : "还没有播放记录")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(displayHistoryByDay, id: \.0) { dayLabel, episodes in
                    Text(dayLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.top, 4)

                    ForEach(episodes) { episode in
                        historyRow(episode)
                    }
                }
            }
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
            let queue = displayHistory.map { episodeForRecord($0) }
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

    private func playHistoryQueue() {
        let queue = displayHistory.map { episodeForRecord($0) }
        guard let first = queue.first else { return }
        audioPlayer.playEpisode(first, in: queue)
        showPlayer = true
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
}
