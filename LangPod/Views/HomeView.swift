import SwiftUI

struct HomeView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AudioPlayer.self) private var audioPlayer
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var showPlayer = false
    @State private var showAllEpisodes = false
    @State private var showPaywall = false
    @State private var showPatternHistory = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    headerSection
                    levelTabs
                    nowPlayingCard
                    todayList
                    todayPatternsSection
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
        .fullScreenCover(isPresented: $showPatternHistory) {
            PatternHistoryView()
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

    private func nowPlayingBadge(for episode: Episode) -> String {
        // When a pattern is playing, show a different badge instead of "第 X/5 遍"
        if case .pattern = audioPlayer.currentPlayItem {
            return "句型讲解"
        }
        if audioPlayer.currentEpisode?.id == episode.id {
            return audioPlayer.phase.roundDisplay(isPro: subscriptionManager.isProUser)
        }
        return "第 1/\(subscriptionManager.isProUser ? 5 : 4) 遍"
    }

    private var nowPlayingCard: some View {
        Group {
            if let episode = nowPlayingEpisode {
                Button {
                    // Quota gate: if a free user has exhausted the day's quota
                    // and this card's episode is NEW (not in today's history),
                    // block entry to the player and show paywall. Replaying
                    // an already-played episode stays free.
                    if !subscriptionManager.isProUser {
                        dataStore.refreshDailyCountIfNeeded()
                        let alreadyPlayedToday = dataStore.listenHistory.contains {
                            $0.episodeId == episode.id &&
                            Calendar.current.isDateInToday($0.listenedAt)
                        }
                        if dataStore.dailyEpisodesPlayed >= SubscriptionManager.freeMaxDailyEpisodes
                            && !alreadyPlayedToday {
                            showPaywall = true
                            return
                        }
                    }

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
                            Text(nowPlayingBadge(for: episode))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.appPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.primaryLight, in: RoundedRectangle(cornerRadius: 8))
                        }

                        // Title — shows current pattern when a pattern is playing,
                        // falls back to the parent/now-playing episode otherwise.
                        VStack(alignment: .leading, spacing: 4) {
                            if case .pattern(let pattern, _) = audioPlayer.currentPlayItem {
                                Text(pattern.template)
                                    .font(.system(size: 20, weight: .bold, design: .serif))
                                    .foregroundStyle(Color.textPrimary)
                                    .tracking(-0.3)
                                    .lineLimit(2)
                                Text("今日句型讲解 · \(pattern.scene)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.textTertiary)
                                    .lineLimit(1)
                            } else {
                                Text(episode.title)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(Color.textPrimary)
                                    .tracking(-0.3)
                                Text("\(episode.dateDisplay) · \(episode.durationDisplay)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.textTertiary)
                            }
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
                            Button {
                                if audioPlayer.currentEpisode == nil {
                                    // Nothing playing yet — prev = start the card episode
                                    if !audioPlayer.playEpisode(episode, in: dataStore.episodes) {
                                        showPaywall = true
                                    }
                                } else if !audioPlayer.skipToPreviousEpisode() {
                                    showPaywall = true
                                }
                            } label: {
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
                                    // Not playing yet — start card episode first, then skip
                                    if !audioPlayer.playEpisode(episode, in: dataStore.episodes) {
                                        showPaywall = true
                                        return
                                    }
                                    if !audioPlayer.skipToNextEpisode() {
                                        showPaywall = true
                                    }
                                } else {
                                    if audioPlayer.episodeQueue.isEmpty {
                                        audioPlayer.episodeQueue = dataStore.episodes
                                    }
                                    if !audioPlayer.skipToNextEpisode() {
                                        showPaywall = true
                                    }
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

                if isEpisodePlaying(episode) {
                    NowPlayingBars(isAnimating: audioPlayer.isPlaying, barHeight: 16)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.appPrimary)
                }
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

                if isEpisodePlaying(episode) {
                    NowPlayingBars(isAnimating: audioPlayer.isPlaying, barHeight: 14)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.appPrimary)
                }
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
            // Starting a new episode — if gate blocks, surface paywall
            // instead of silently no-op'ing.
            if !audioPlayer.playEpisode(episode, in: dataStore.episodes) {
                showPaywall = true
            }
        }
    }

    private func progressWidth(_ episode: Episode, in totalWidth: CGFloat) -> CGFloat {
        guard audioPlayer.currentEpisode?.id == episode.id, audioPlayer.duration > 0 else { return 0 }
        return totalWidth * CGFloat(audioPlayer.progress / audioPlayer.duration)
    }

    // MARK: - Today's Patterns

    /// Patterns extracted from today's episodes across all levels.
    /// Flat list so the user sees all today's explainers regardless of current level tab.
    private var todayPatterns: [(pattern: Pattern, parent: Episode)] {
        let today = DateFormatter.episodeDate.string(from: Date())
        var results: [(Pattern, Episode)] = []
        for ep in dataStore.episodes where ep.date == today {
            if let patterns = ep.patterns {
                for p in patterns { results.append((p, ep)) }
            }
        }
        return results
    }

    private var hasAnyPattern: Bool {
        dataStore.episodes.contains { ($0.patterns?.isEmpty == false) }
    }

    @ViewBuilder
    private var todayPatternsSection: some View {
        let items = todayPatterns
        if !items.isEmpty {
            // Today has patterns — horizontal small cards (158×158), scrolls through all levels' patterns.
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("今日句型讲解")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("· \(items.count) 个")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    if !subscriptionManager.isProUser {
                        patternQuotaBadge
                    }
                    historyLink
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items, id: \.pattern.id) { item in
                            patternCard(pattern: item.pattern, parent: item.parent)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        } else if hasAnyPattern {
            // No today patterns, but history exists — compact link row
            Button { showPatternHistory = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "E8B800"))
                        .frame(width: 36, height: 36)
                        .background(Color(hex: "FFF4D6"), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("句型讲解")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("查看往期句型回顾")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textTertiary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
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
    }

    /// True only when the AudioPlayer is actively on an EPISODE item matching
    /// this row. When a pattern is playing, the parent episode is NOT considered
    /// "playing" — patterns are their own thing (see PatternHistoryView row).
    private func isEpisodePlaying(_ episode: Episode) -> Bool {
        if case .episode(let current) = audioPlayer.currentPlayItem {
            return current.id == episode.id
        }
        return false
    }

    /// Small badge showing today's remaining free pattern quota. Hidden for Pro.
    private var patternQuotaBadge: some View {
        let used = dataStore.dailyPatternIDsPlayedToday.count
        let max = SubscriptionManager.freeMaxDailyPatterns
        let remaining = Swift.max(0, max - used)
        return HStack(spacing: 3) {
            Image(systemName: remaining == 0 ? "lock.fill" : "sparkles")
                .font(.system(size: 10, weight: .semibold))
            Text("今日免费 \(remaining)/\(max)")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(remaining == 0 ? Color.warning : Color.appPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (remaining == 0 ? Color.warningLight : Color.primaryLight),
            in: Capsule()
        )
    }

    private var historyLink: some View {
        Button { showPatternHistory = true } label: {
            HStack(spacing: 2) {
                Text("往期回顾")
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.appPrimary)
        }
    }

    private func patternCard(pattern: Pattern, parent: Episode) -> some View {
        let accessible = PatternAccessGate.canAccess(
            pattern: pattern,
            parentEpisode: parent,
            isPro: subscriptionManager.isProUser,
            playedTodayIds: dataStore.dailyPatternIDsPlayedToday
        )
        return Button {
            if accessible {
                // Queue = all today's ACCESSIBLE patterns interleaved from parent
                // episodes, so mixed browsing doesn't hit a wall mid-sequence.
                let items: [PlayItem] = todayPatterns
                    .filter {
                        PatternAccessGate.canAccess(
                            pattern: $0.pattern,
                            parentEpisode: $0.parent,
                            isPro: subscriptionManager.isProUser,
                            playedTodayIds: dataStore.dailyPatternIDsPlayedToday
                        )
                    }
                    .map { .pattern($0.pattern, parentEpisode: $0.parent) }
                audioPlayer.playPattern(pattern, parentEpisode: parent, in: items)
                showPlayer = true
                Analytics.track(.patternOpen, params: [
                    "pattern_id": pattern.id,
                    "episode_id": parent.id,
                    "source": "home_today",
                ])
            } else {
                Analytics.track(.patternPaywallView, params: [
                    "pattern_id": pattern.id,
                    "source": "home_today_quota",
                ])
                showPaywall = true
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(pattern.template)
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(Color(white: 0.15))
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 0)

                    Text(pattern.translationZh)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.32))
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Image(systemName: accessible ? "play.circle.fill" : "lock.fill")
                            .font(.system(size: 12))
                        Text(pattern.durationDisplay)
                            .font(.system(size: 11, weight: .medium))
                        Spacer(minLength: 6)
                        Text(pattern.scene)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(Color(white: 0.35))
                }
                .padding(14)
                .frame(width: 158, height: 158)
                .background(cardColor(pattern: pattern))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
                .opacity(accessible ? 1 : 0.55)
            }
        }
        .buttonStyle(.plain)
    }

    private func cardColor(pattern: Pattern) -> Color {
        if let hex = pattern.thumbnailColor, let c = colorFromHex(hex) {
            return c
        }
        return colorFromHex("#E8DCC4") ?? Color(hex: "E8DCC4")
    }

    private func colorFromHex(_ hex: String) -> Color? {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        return Color(
            red: Double((v >> 16) & 0xFF) / 255.0,
            green: Double((v >> 8) & 0xFF) / 255.0,
            blue: Double(v & 0xFF) / 255.0
        )
    }
}

/// Animated 3-bar "now playing" indicator. Pauses cleanly when `isAnimating`
/// is false (the bars drop to a short static state to keep showing which row
/// is current without distracting motion).
struct NowPlayingBars: View {
    var isAnimating: Bool
    var color: Color = .appPrimary
    var barHeight: CGFloat = 16

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2.5) {
                bar(index: 0, t: t)
                bar(index: 1, t: t)
                bar(index: 2, t: t)
            }
            .frame(width: 20, height: barHeight, alignment: .bottom)
        }
    }

    private func bar(index: Int, t: TimeInterval) -> some View {
        let maxH = barHeight
        let minH = maxH * 0.6
        // Per-bar irregular motion: sum of 2 sines at coprime-ish frequencies,
        // each bar gets its own pair + phase so they never sync up.
        let params: [(f1: Double, f2: Double, phase: Double)] = [
            (2.3, 3.7, 0.6),
            (2.9, 1.8, 2.4),
            (3.4, 2.1, 4.7),
        ]
        let p = params[index % params.count]
        let s = (sin(t * p.f1 + p.phase) + sin(t * p.f2 + p.phase * 1.7)) / 2
        let normalized = (s + 1) / 2
        let h: CGFloat = isAnimating ? minH + CGFloat(normalized) * (maxH - minH) : minH
        return RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: 3, height: h)
    }
}

#Preview {
    HomeView()
        .environment(DataStore())
        .environment(AudioPlayer())
        .environment(SubscriptionManager())
}
