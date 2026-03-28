import SwiftUI

struct StatsView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AudioPlayer.self) private var audioPlayer
    @State private var showPlayer = false
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            Color(hex: "F7F8FC").ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                    statsRow
                    streakCalendar
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
                .foregroundStyle(Color(hex: "1E293B"))
                .tracking(-0.5)
            Spacer()
            HStack(spacing: 4) {
                Text("Lv.\(dataStore.listeningLevel.rawValue)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "3B82F6"))
                Text(dataStore.listeningLevel.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "3B82F6"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(hex: "EFF6FF"), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(value: dataStore.totalListeningTimeDisplay, label: "总时长")
            statCard(value: "\(dataStore.episodesCompleted)", label: "已听集数")
            statCard(value: "\(dataStore.streakDays)", label: "连续天数", accent: true)
        }
    }

    private func statCard(value: String, label: String, accent: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(accent ? Color(hex: "F59E0B") : Color(hex: "1E293B"))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: "94A3B8"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
        )
    }

    // MARK: - Streak Calendar (last 5 weeks)

    private var streakCalendar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("学习日历")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: "1E293B"))

            let days = last35Days
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(days, id: \.self) { date in
                    let hasActivity = hasListenedOn(date)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hasActivity ? Color(hex: "3B82F6") : Color(hex: "E2E8F0"))
                        .frame(height: 28)
                        .overlay(
                            Text(dayNumber(date))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(hasActivity ? .white : Color(hex: "94A3B8"))
                        )
                }
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
        )
    }

    private var last35Days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Start from the most recent Monday
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7 // Monday = 0
        let startOfWeek = calendar.date(byAdding: .day, value: -daysFromMonday, to: today)!
        let startDate = calendar.date(byAdding: .day, value: -28, to: startOfWeek)!

        return (0..<35).compactMap { calendar.date(byAdding: .day, value: $0, to: startDate) }
    }

    private func hasListenedOn(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return dataStore.listenHistory.contains { calendar.isDate($0.listenedAt, inSameDayAs: date) }
    }

    private func dayNumber(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        return "\(day)"
    }

    // MARK: - History List

    private var displayHistory: [ListenedEpisode] {
        dataStore.starredOnly ? dataStore.starredHistory : dataStore.listenHistory
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
            // Header with play all + star filter
            HStack(spacing: 8) {
                // Play all with Pro badge
                if !displayHistory.isEmpty {
                    Button { showPaywall = true } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color(hex: "3B82F6"))

                            Text("Pro")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Color(hex: "92400E"))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Color(hex: "FEF3C7"), in: Capsule())
                                .offset(x: 5, y: -3)
                        }
                    }
                }

                Text("播放历史")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "1E293B"))

                Spacer()

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
                    .foregroundStyle(dataStore.starredOnly ? Color(hex: "F59E0B") : Color(hex: "94A3B8"))
                }
            }

            if displayHistory.isEmpty {
                Text(dataStore.starredOnly ? "还没有收藏的播客" : "还没有播放记录")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "94A3B8"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(displayHistoryByDay, id: \.0) { dayLabel, episodes in
                    Text(dayLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "94A3B8"))
                        .padding(.top, 4)

                    ForEach(episodes) { episode in
                        historyRow(episode)
                    }
                }
            }
        }
    }

    private func historyRow(_ record: ListenedEpisode) -> some View {
        Button {
            let allEpisodes = MockDataLoader.loadAllEpisodes()
            if let episode = allEpisodes.first(where: { $0.id == record.episodeId }) {
                audioPlayer.playEpisode(episode)
                showPlayer = true
            }
        } label: {
            HStack(spacing: 12) {
                // Thumbnail from mock data lookup
                historyThumbnail(record)

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "1E293B"))
                    HStack(spacing: 6) {
                        Text(PodcastLevel(rawValue: record.level)?.tabName ?? "")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(levelColor(record.level))
                        Text("·")
                            .foregroundStyle(Color(hex: "CBD5E1"))
                        Text("\(record.durationSeconds / 60) 分钟")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "94A3B8"))
                    }
                }

                Spacer()

                // Star button (stops propagation)
                Button { dataStore.toggleStar(record) } label: {
                    Image(systemName: record.isStarred ? "star.fill" : "star")
                        .font(.system(size: 18))
                        .foregroundStyle(record.isStarred ? Color(hex: "F59E0B") : Color(hex: "CBD5E1"))
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
                    .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func historyThumbnail(_ record: ListenedEpisode) -> some View {
        let allEpisodes = MockDataLoader.loadAllEpisodes()
        let episode = allEpisodes.first(where: { $0.id == record.episodeId })
        // Create a minimal episode for thumbnail if not found
        let ep = episode ?? Episode(
            id: record.episodeId, title: record.title, level: record.level,
            date: "", durationSeconds: record.durationSeconds,
            audio: EpisodeAudio(english: "", translationZh: ""),
            script: [], vocabulary: []
        )
        return EpisodeThumbnail(episode: ep, size: 40)
    }

    private func levelColor(_ level: String) -> Color {
        switch level {
        case "easy": Color(hex: "22C55E")
        case "medium": Color(hex: "3B82F6")
        case "hard": Color(hex: "F97316")
        default: Color(hex: "94A3B8")
        }
    }
}

#Preview {
    StatsView()
        .environment(DataStore())
        .environment(AudioPlayer())
}
