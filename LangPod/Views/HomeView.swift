import SwiftUI

struct HomeView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AudioPlayer.self) private var audioPlayer
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var showPlayer = false
    @State private var showAllEpisodes = false
    @State private var showPaywall = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()

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
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(subscriptionManager)
        }
        .task {
            // Preload today's episode thumbnails + now-playing cover so they appear instantly
            await preloadVisibleThumbnails()
        }
    }

    /// Preload thumbnails for the most important episodes (today's + now playing)
    /// so they're in ImageCache before the user scrolls to them.
    private func preloadVisibleThumbnails() async {
        var urls: [String] = []

        // Now-playing episode cover (most visible)
        if let thumb = nowPlayingEpisode?.thumbnail {
            urls.append(thumb)
        }

        // Today's episodes
        for ep in todayEpisodes.reversed() { // newest first
            if let thumb = ep.thumbnail {
                urls.append(thumb)
            }
        }

        // Weekly picks (next priority)
        for ep in weeklyPicks.prefix(3) {
            if let thumb = ep.thumbnail {
                urls.append(thumb)
            }
        }

        // Fire all preloads concurrently
        await withTaskGroup(of: Void.self) { group in
            for url in urls.prefix(8) { // cap at 8 to avoid overwhelming
                group.addTask {
                    _ = await ImageCache.shared.image(for: url)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textTertiary)

                Text(dataStore.userName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .tracking(-0.5)
            }

            Spacer()

            // Streak badge
            HStack(spacing: 6) {
                Text("🔥")
                    .font(.system(size: 14))
                Text("\(dataStore.streakDays)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.gold)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.warningLight, in: Capsule())
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
        case .easy: Color.success
        case .medium: Color.appPrimary
        case .hard: Color.hardOrange
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
                    .foregroundStyle(isSelected ? .white : Color.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.appPrimary : Color.divider,
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
                        if !audioPlayer.playEpisode(episode, in: dataStore.episodes) {
                            showPaywall = true
                            return
                        }
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
                                    .foregroundStyle(Color.appPrimary)
                                    .tracking(1)
                            }
                            Spacer()
                            Text(audioPlayer.currentEpisode?.id == episode.id ? audioPlayer.phase.roundDisplay(isPro: subscriptionManager.isProUser) : "第 1/\(subscriptionManager.isProUser ? 5 : 4) 遍")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.appPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.primaryLight, in: RoundedRectangle(cornerRadius: 8))
                        }

                        // Title
                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.title)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Color.textPrimary)
                                .tracking(-0.3)

                            Text("\(episode.dateDisplay) · \(episode.durationDisplay)")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Progress bar (draggable)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.divider)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.appPrimary)
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
                                    .foregroundStyle(Color.textTertiary)
                            }
                            Button { playOrToggle(episode) } label: {
                                Image(systemName: isCurrentAndPlaying(episode) ? "pause.fill" : "play.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 52)
                                    .background(Color.appPrimary, in: Circle())
                            }
                            Button {
                                if audioPlayer.currentEpisode == nil {
                                    // Not playing yet — start playing this episode first, then skip
                                    audioPlayer.playEpisode(episode, in: dataStore.episodes)
                                    audioPlayer.skipToNextEpisode()
                                } else if audioPlayer.episodeQueue.isEmpty {
                                    // Playing but no queue — set queue then skip
                                    audioPlayer.episodeQueue = dataStore.episodes
                                    audioPlayer.skipToNextEpisode()
                                } else {
                                    audioPlayer.skipToNextEpisode()
                                }
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Today's Episodes

    private func playAll(_ episodes: [Episode]) {
        guard let first = episodes.first else { return }
        if audioPlayer.playEpisode(first, in: episodes) {
            showPlayer = true
        } else {
            showPaywall = true
        }
    }

    private var todayEpisodes: [Episode] {
        let today = DateFormatter.episodeDate.string(from: Date())
        return dataStore.episodes.filter { $0.date == today }
    }

    private var todayList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !todayEpisodes.isEmpty {
                HStack {
                    Text("今日播客")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Button { playAll(todayEpisodes) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("全部播放")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color.appPrimary)
                    }
                }

                ForEach(todayEpisodes) { episode in
                    episodeRow(episode)
                }
            }
        }
    }

    private func episodeRow(_ episode: Episode) -> some View {
        Button {
            if audioPlayer.playEpisode(episode, in: dataStore.episodes) {
                showPlayer = true
            } else {
                showPaywall = true
            }
        } label: {
            HStack(spacing: 14) {
                EpisodeThumbnail(episode: episode, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    HStack(spacing: 6) {
                        Text(episode.podcastLevel?.tabName ?? "")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(levelDotColor(episode.level))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(levelBgColor(episode.level), in: RoundedRectangle(cornerRadius: 4))
                        Text("\(episode.dateDisplay) · \(episode.durationDisplay)")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.appPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Weekly Picks

    private var weeklyPicksList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !weeklyPicks.isEmpty {
                HStack {
                    Text("本周精选")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Button { playAll(weeklyPicks) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("全部播放")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color.appPrimary)
                    }
                }

                ForEach(weeklyPicks) { episode in
                    episodeRow(episode)
                }
            }
        }
    }

    private var weeklyPicks: [Episode] {
        // Same level, last 7 days excluding today
        let today = DateFormatter.episodeDate.string(from: Date())
        guard let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return [] }
        let cutoff = DateFormatter.episodeDate.string(from: weekAgo)
        return dataStore.episodes.filter {
            $0.date != today && $0.date >= cutoff
        }.reversed() // newest first
    }

    private func levelDotColor(_ level: String) -> Color {
        switch level {
        case "easy": Color.success
        case "medium": Color.appPrimary
        case "hard": Color.hardOrange
        default: Color.textTertiary
        }
    }

    private func levelBgColor(_ level: String) -> Color {
        switch level {
        case "easy": Color.successLight
        case "medium": Color.primaryLight
        case "hard": Color.warningLight
        default: Color.divider
        }
    }

    // MARK: - Past Episodes

    private var pastEpisodes: [Episode] {
        let today = DateFormatter.episodeDate.string(from: Date())
        // Only show current level, within last 15 days
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -15, to: Date()) else {
            return []
        }
        let cutoff = DateFormatter.episodeDate.string(from: cutoffDate)
        return dataStore.episodes.filter {
            $0.date != today && $0.date >= cutoff
        }.reversed() // newest first
    }

    private var pastEpisodesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("往期回顾")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                if !pastEpisodes.isEmpty {
                    Button { playAll(pastEpisodes) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("全部播放")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color.appPrimary)
                    }
                }

                Spacer()
                if pastEpisodes.count > 5 {
                    Button { showAllEpisodes = true } label: {
                        HStack(spacing: 4) {
                            Text("查看全部")
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(Color.appPrimary)
                    }
                }
            }

            if pastEpisodes.isEmpty {
                Text("暂无往期内容")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                ForEach(pastEpisodes.prefix(5)) { episode in
                    pastEpisodeRow(episode)
                }
            }
        }
    }

    private func pastEpisodeRow(_ episode: Episode) -> some View {
        Button {
            if audioPlayer.playEpisode(episode, in: Array(pastEpisodes)) {
                showPlayer = true
            } else {
                showPaywall = true
            }
        } label: {
            HStack(spacing: 14) {
                EpisodeThumbnail(episode: episode, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    HStack(spacing: 6) {
                        Text(episode.podcastLevel?.tabName ?? "")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(levelDotColor(episode.level))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(levelBgColor(episode.level), in: RoundedRectangle(cornerRadius: 4))
                        Text("\(episode.dateDisplay) · \(episode.durationDisplay)")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.appPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
        .environment(SubscriptionManager())
}
