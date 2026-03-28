import SwiftUI

struct HomeView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AudioPlayer.self) private var audioPlayer
    @State private var showPlayer = false
    @State private var showAllEpisodes = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: "F7F8FC").ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    headerSection
                    levelTabs
                    nowPlayingCard
                    todayList
                    weeklyPicksList
                    pastEpisodesList
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
        }
        .fullScreenCover(isPresented: $showAllEpisodes) {
            AllEpisodesView()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: "94A3B8"))

                Text(dataStore.userName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(hex: "1E293B"))
                    .tracking(-0.5)
            }

            Spacer()

            // Streak badge
            HStack(spacing: 6) {
                Text("🔥")
                    .font(.system(size: 14))
                Text("\(dataStore.streakDays)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: "92400E"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(hex: "FEF3C7"), in: Capsule())
        }
    }

    // MARK: - Level Tabs

    private var levelTabs: some View {
        HStack(spacing: 8) {
            ForEach(PodcastLevel.allCases, id: \.self) { level in
                levelTab(level)
            }
            Spacer()
        }
    }

    private func levelTab(_ level: PodcastLevel) -> some View {
        let isSelected = dataStore.selectedLevel == level
        let dotColor: Color = switch level {
        case .easy: Color(hex: "22C55E")
        case .medium: Color(hex: "3B82F6")
        case .hard: Color(hex: "F97316")
        }

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                dataStore.selectedLevel = level
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isSelected ? .white : dotColor)
                    .frame(width: 8, height: 8)
                Text(level.tabName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : Color(hex: "64748B"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color(hex: "3B82F6") : Color(hex: "F1F5F9"),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Now Playing Card

    // Show what's actually playing, or fall back to current level's first episode
    private var nowPlayingEpisode: Episode? {
        audioPlayer.currentEpisode ?? dataStore.currentEpisode
    }

    private var isActuallyPlaying: Bool {
        audioPlayer.currentEpisode != nil
    }

    private var nowPlayingCard: some View {
        Group {
            if let episode = nowPlayingEpisode {
                Button {
                    if audioPlayer.currentEpisode == nil {
                        audioPlayer.playEpisode(episode, in: dataStore.episodes)
                    }
                    showPlayer = true
                } label: {
                    VStack(spacing: 14) {
                        // Header row
                        HStack {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: isActuallyPlaying ? "3B82F6" : "94A3B8"))
                                    .frame(width: 8, height: 8)
                                Text(isActuallyPlaying ? "正在播放" : "即将播放")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(hex: "3B82F6"))
                                    .tracking(1)
                            }
                            Spacer()
                            Text(audioPlayer.currentEpisode?.id == episode.id ? audioPlayer.phase.roundDisplay : "第 1/5 遍")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(hex: "3B82F6"))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(hex: "EFF6FF"), in: RoundedRectangle(cornerRadius: 8))
                        }

                        // Title
                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.title)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Color(hex: "1E293B"))
                                .tracking(-0.3)

                            Text("第 \(episodeNumber(episode)) 集 · \(episode.durationSeconds / 60) 分钟")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "94A3B8"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Progress bar (draggable)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(hex: "F1F5F9"))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(hex: "3B82F6"))
                                    .frame(width: progressWidth(episode, in: geo.size.width), height: 6)
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard audioPlayer.currentEpisode?.id == episode.id else { return }
                                        let ratio = max(0, min(1, value.location.x / geo.size.width))
                                        let time = Double(ratio) * audioPlayer.duration
                                        audioPlayer.seek(to: time)
                                    }
                            )
                        }
                        .frame(height: 20)
                        .contentShape(Rectangle())

                        // Playback controls
                        HStack(spacing: 32) {
                            Button { audioPlayer.skipToPreviousEpisode() } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color(hex: "94A3B8"))
                            }
                            Button { playOrToggle(episode) } label: {
                                Image(systemName: isCurrentAndPlaying(episode) ? "pause.fill" : "play.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 52)
                                    .background(Color(hex: "3B82F6"), in: Circle())
                            }
                            Button { audioPlayer.skipToNextEpisode() } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color(hex: "94A3B8"))
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Today's Episodes

    private var todayList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日播客")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(hex: "1E293B"))

            ForEach(dataStore.episodes.dropFirst()) { episode in
                episodeRow(episode)
            }
        }
    }

    private func episodeRow(_ episode: Episode) -> some View {
        Button {
            audioPlayer.playEpisode(episode, in: dataStore.episodes)
            showPlayer = true
        } label: {
            HStack(spacing: 14) {
                EpisodeThumbnail(episode: episode, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "1E293B"))
                    Text("第 \(episodeNumber(episode)) 集 · \(episode.durationSeconds / 60) 分钟")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "94A3B8"))
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: "3B82F6"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Weekly Picks

    private var weeklyPicksList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本周播客精选")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(hex: "1E293B"))

            ForEach(weeklyPicks) { episode in
                weeklyPickRow(episode)
            }
        }
    }

    private var weeklyPicks: [Episode] {
        // Show episodes from other levels as "picks"
        let otherLevels = PodcastLevel.allCases.filter { $0 != dataStore.selectedLevel }
        return otherLevels.flatMap { MockDataLoader.loadEpisodes(for: $0).prefix(2) }
    }

    private func weeklyPickRow(_ episode: Episode) -> some View {
        Button {
            audioPlayer.playEpisode(episode)
            showPlayer = true
        } label: {
            HStack(spacing: 14) {
                EpisodeThumbnail(episode: episode, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "1E293B"))
                    HStack(spacing: 6) {
                        Text(episode.podcastLevel?.tabName ?? "")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(levelDotColor(episode.level))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(levelBgColor(episode.level), in: RoundedRectangle(cornerRadius: 4))
                        Text("\(episode.durationSeconds / 60) 分钟 · \(episode.vocabulary.count) 个生词")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "94A3B8"))
                    }
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "3B82F6"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func levelDotColor(_ level: String) -> Color {
        switch level {
        case "easy": Color(hex: "22C55E")
        case "medium": Color(hex: "3B82F6")
        case "hard": Color(hex: "F97316")
        default: Color(hex: "94A3B8")
        }
    }

    private func levelBgColor(_ level: String) -> Color {
        switch level {
        case "easy": Color(hex: "DCFCE7")
        case "medium": Color(hex: "EFF6FF")
        case "hard": Color(hex: "FEF3C7")
        default: Color(hex: "F1F5F9")
        }
    }

    // MARK: - Past Episodes

    private var pastEpisodes: [Episode] {
        // All episodes from all levels, simulating accumulated content
        let all = MockDataLoader.loadAllEpisodes()
        // Exclude episodes already shown in today list
        let todayIds = Set(dataStore.episodes.map(\.id))
        return all.filter { !todayIds.contains($0.id) }
    }

    private var pastEpisodesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("往期回顾")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: "1E293B"))
                Spacer()
                if pastEpisodes.count > 5 {
                    Button { showAllEpisodes = true } label: {
                        HStack(spacing: 4) {
                            Text("查看全部")
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(Color(hex: "3B82F6"))
                    }
                }
            }

            if pastEpisodes.isEmpty {
                Text("暂无往期内容")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "94A3B8"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                ForEach(pastEpisodes.prefix(5)) { episode in
                    episodeRow(episode)
                }
            }
        }
    }

    // MARK: - Helpers

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "早上好" }
        if hour < 18 { return "下午好" }
        return "晚上好"
    }

    private func episodeNumber(_ episode: Episode) -> Int {
        (dataStore.episodes.firstIndex(where: { $0.id == episode.id }) ?? 0) + 1
    }

    private func isCurrentAndPlaying(_ episode: Episode) -> Bool {
        audioPlayer.currentEpisode?.id == episode.id && audioPlayer.isPlaying
    }

    private func playOrToggle(_ episode: Episode) {
        if audioPlayer.currentEpisode?.id == episode.id {
            audioPlayer.togglePlayPause()
        } else {
            audioPlayer.playEpisode(episode, in: dataStore.episodes)
        }
    }

    private func progressWidth(_ episode: Episode, in totalWidth: CGFloat) -> CGFloat {
        guard audioPlayer.currentEpisode?.id == episode.id, audioPlayer.duration > 0 else { return 0 }
        return totalWidth * CGFloat(audioPlayer.progress / audioPlayer.duration)
    }
}

#Preview {
    HomeView()
        .environment(DataStore())
        .environment(AudioPlayer())
}
