import SwiftUI
import UIKit

struct PlayerView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(DataStore.self) private var dataStore
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(\.dismiss) private var dismiss
    @State private var showComplete = false
    @State private var showLevelUp = false
    @State private var showShareCard = false
    @State private var showSpeedPicker = false
    @State private var showPaywall = false
    /// Non-nil while the user is dragging the scrub bar. Locks the displayed
    /// ratio to the finger position so the live `player.progress` tick doesn't
    /// fight the drag. Committed via player.seek on release, then cleared.
    @State private var scrubbingRatio: CGFloat?
    @Environment(SubscriptionManager.self) private var subscriptionManager

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if showLevelUp, let level = dataStore.pendingLevelUp {
                LevelUpView(
                    level: level,
                    episodesCompleted: dataStore.episodesCompleted,
                    wordsLearned: vocabularyStore.totalCount,
                    onShare: {
                        dataStore.pendingLevelUp = nil
                        showLevelUp = false
                        showShareCard = true
                    },
                    onContinue: {
                        dataStore.pendingLevelUp = nil
                        showLevelUp = false
                        showComplete = false
                        player.skipToNextEpisode()
                    }
                )
            } else if showComplete,
                      case .episode(let episode) = player.currentPlayItem {
                EpisodeCompleteView(
                    episode: episode,
                    onNextEpisode: {
                        showComplete = false
                        if !player.skipToNextEpisode() {
                            showPaywall = true
                        }
                    },
                    onSaveVocabulary: {
                        vocabularyStore.saveWords(from: episode)
                        checkLevelUp()
                        if !showLevelUp {
                            showComplete = false
                            if !player.skipToNextEpisode() {
                                showPaywall = true
                            }
                        }
                    },
                    onPlayPatterns: {
                        guard let first = episode.patterns?.first else { return }
                        showComplete = false
                        player.playPattern(first, parentEpisode: episode, in: player.playQueue)
                    }
                )
            } else {
                playerContent
            }
        }
        .onAppear {
            player.onEpisodeFinished = {
                if let ep = player.currentEpisode {
                    vocabularyStore.saveWords(from: ep)
                }
                dataStore.completeEpisode(totalWords: vocabularyStore.totalCount, episode: player.currentEpisode)
                // Lock screen / background: auto-advance like a podcast.
                // Foreground: show completion page for vocab + stats review.
                if UIApplication.shared.applicationState == .active {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showComplete = true
                    }
                } else {
                    player.skipToNextEpisode()
                }
            }
        }
        .onDisappear {
            // Restore default handler: record history + auto-advance even when PlayerView is not visible.
            // Previously this handler forgot to call skipToNextEpisode, so playback silently stopped
            // after one episode when the user wasn't looking at the full player.
            player.onEpisodeFinished = { [dataStore, vocabularyStore, player] in
                if let ep = player.currentEpisode {
                    vocabularyStore.saveWords(from: ep)
                }
                dataStore.completeEpisode(
                    totalWords: vocabularyStore.totalCount,
                    episode: player.currentEpisode
                )
                player.skipToNextEpisode()
            }
        }
        .fullScreenCover(isPresented: $showShareCard) {
            ShareCardView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(subscriptionManager)
        }


    }

    private func checkLevelUp() {
        if dataStore.pendingLevelUp != nil {
            withAnimation(.easeInOut(duration: 0.3)) {
                showLevelUp = true
            }
        }
    }

    // MARK: - Player Content

    private var playerContent: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header — close button is a filled circular xmark so it reads
                // as "close this overlay" across both episode and pattern pages.
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                            .frame(width: 34, height: 34)
                            .background(Color.divider.opacity(0.7), in: Circle())
                    }
                    Spacer()
                    Text("正在播放")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    // Invisible spacer to keep title centered
                    Color.clear.frame(width: 34, height: 34)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer().frame(height: 40)

                // Content area — episode vs pattern
                switch player.currentPlayItem {
                case .pattern(let pattern, _):
                    PatternPlayerContent(pattern: pattern, currentTime: player.progress)
                        .padding(.horizontal, 24)
                case .episode(let episode):
                    EpisodeThumbnail(episode: episode, size: 260)
                    VStack(spacing: 6) {
                        Text(episode.title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                            .tracking(-0.5)
                        Text(episodeMetaText)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textTertiary)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.appPrimary)
                                .frame(width: 8, height: 8)
                            Text(player.phase.label(isPro: subscriptionManager.isProUser))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.appPrimary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.primaryLight, in: Capsule())
                    }
                    .padding(.top, 28)
                    .padding(.horizontal, 24)
                case .none:
                    EmptyView()
                }

                // Pro upsell card (free users, after 4th round)
                if player.phase == .proUpsell {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pro 专属：第 5 遍英语原音")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.textPrimary)
                            Text("再听一遍加深记忆")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Button { showPaywall = true } label: {
                            Text("升级 Pro")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(14)
                    .background(Color.warningLight, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.warning.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Progress bar (draggable). Seek is committed on release only;
                // during drag we just show a local preview ratio so the bar
                // doesn't jitter from repeated AVPlayer.seek calls each frame.
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        let displayedRatio = scrubbingRatio ?? liveRatio
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.border)
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.appPrimary)
                                .frame(width: max(0, geo.size.width * displayedRatio), height: 6)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    scrubbingRatio = max(0, min(1, value.location.x / geo.size.width))
                                }
                                .onEnded { _ in
                                    if let r = scrubbingRatio {
                                        player.seek(to: Double(r) * player.duration)
                                    }
                                    scrubbingRatio = nil
                                }
                        )
                    }
                    .frame(height: 20)
                    .contentShape(Rectangle())

                    HStack {
                        Text(formatTime(player.progress))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                        Spacer()
                        Text(formatTime(player.duration))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .padding(.top, 32)
                .padding(.horizontal, 32)

                // Playback controls
                HStack(spacing: 36) {
                    Button { player.skipToPreviousEpisode() } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.textTertiary)
                    }

                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(Color.appPrimary, in: Circle())
                    }

                    Button { player.skipToNextEpisode() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .padding(.top, 24)

                // Speed picker bar
                if showSpeedPicker {
                    HStack(spacing: 0) {
                        ForEach(AudioPlayer.availableRates, id: \.self) { rate in
                            let isSelected = player.playbackRate == rate
                            Button {
                                player.setPlaybackRate(rate)
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showSpeedPicker = false
                                }
                            } label: {
                                Text(rate == Float(Int(rate)) ? String(format: "%.0fx", rate) : String(format: "%.2gx", rate))
                                    .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? .white : Color.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        isSelected ? Color.appPrimary : Color.clear,
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Color.divider, in: Capsule())
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Bottom actions
                HStack(spacing: 32) {
                    Button {
                        if subscriptionManager.isProUser {
                            player.showSubtitles.toggle()
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        VStack(spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "captions.bubble")
                                    .font(.system(size: 22))
                                    .foregroundStyle(player.showSubtitles ? Color.appPrimary : Color.textTertiary)
                                if !subscriptionManager.isProUser {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.white)
                                        .padding(2)
                                        .background(Color.warning, in: Circle())
                                        .offset(x: 4, y: -4)
                                }
                            }
                            Text("字幕")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(player.showSubtitles ? Color.appPrimary : Color.textTertiary)
                        }
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSpeedPicker.toggle()
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(rateLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(player.playbackRate != 1.0 ? Color.appPrimary : Color.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    player.playbackRate != 1.0 ? Color.primaryLight : Color.divider,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                            Text("速度")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(player.playbackRate != 1.0 ? Color.appPrimary : Color.textTertiary)
                        }
                    }

                    Button { toggleCurrentEpisodeStar() } label: {
                        VStack(spacing: 4) {
                            Image(systemName: isCurrentEpisodeStarred ? "star.fill" : "star")
                                .font(.system(size: 22))
                                .foregroundStyle(isCurrentEpisodeStarred ? Color.warning : Color.textTertiary)
                            Text("收藏")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isCurrentEpisodeStarred ? Color.warning : Color.textTertiary)
                        }
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            player.playOrder = player.playOrder.next
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: player.playOrder.icon)
                                .font(.system(size: 22))
                                .foregroundStyle(player.playOrder == .sequential ? Color.textTertiary : Color.appPrimary)
                            Text(player.playOrder.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(player.playOrder == .sequential ? Color.textTertiary : Color.appPrimary)
                        }
                    }
                }
                .padding(.top, 28)

                Spacer()
            }

            // Pattern subtitle — absolute bottom overlay; does NOT push layout.
            // Only Chinese text (narration), no English sample, no layout shift.
            if isPlayingPattern,
               player.showSubtitles,
               subscriptionManager.isProUser,
               case .pattern(let pattern, _) = player.currentPlayItem {
                VStack {
                    Spacer()
                    PatternSubtitleFloat(pattern: pattern, currentTime: player.progress)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            // Episode subtitle overlay (Pro only) — for episodes only.
            if player.showSubtitles, subscriptionManager.isProUser,
               !isPlayingPattern,
               let episode = player.currentEpisode {
                SubtitleOverlay(
                    script: episode.script,
                    currentTime: player.progress,
                    phase: player.phase,
                    showTranslation: true
                )
            }
        }
    }

    // MARK: - Helpers

    private var isPlayingPattern: Bool {
        if case .pattern = player.currentPlayItem { return true }
        return false
    }

    private var episodeMetaText: String {
        guard let episode = player.currentEpisode else { return "" }
        let level = episode.podcastLevel?.tabName ?? ""
        let idx = player.episodeQueue.firstIndex(where: { $0.id == episode.id }).map { $0 + 1 } ?? 1
        return "\(episode.dateDisplay) · \(level) · \(episode.durationDisplay)"
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard player.duration > 0 else { return 0 }
        return totalWidth * CGFloat(player.progress / player.duration)
    }

    /// Live playback ratio, clamped. Used as the progress bar fill when the
    /// user is NOT actively scrubbing.
    private var liveRatio: CGFloat {
        guard player.duration > 0 else { return 0 }
        return CGFloat(max(0, min(1, player.progress / player.duration)))
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private var isCurrentEpisodeStarred: Bool {
        guard let ep = player.currentEpisode else { return false }
        return dataStore.listenHistory.contains { $0.episodeId == ep.id && $0.isStarred }
    }

    private func toggleCurrentEpisodeStar() {
        guard let ep = player.currentEpisode else { return }
        if let record = dataStore.listenHistory.first(where: { $0.episodeId == ep.id }) {
            dataStore.toggleStar(record)
        } else {
            // Not in history yet — add and star it
            var record = ListenedEpisode(
                episodeId: ep.id, title: ep.title, level: ep.level,
                durationSeconds: ep.durationSeconds, listenedAt: Date()
            )
            record.isStarred = true
            dataStore.listenHistory.insert(record, at: 0)
            dataStore.saveListenHistoryPublic()
        }
    }

    private var rateLabel: String {
        let rate = player.playbackRate
        if rate == Float(Int(rate)) {
            return String(format: "%.0fx", rate)
        }
        return String(format: "%.2gx", rate)
    }
}

#Preview {
    PlayerView()
        .environment(AudioPlayer())
        .environment(DataStore())
        .environment(SubscriptionManager())
}
