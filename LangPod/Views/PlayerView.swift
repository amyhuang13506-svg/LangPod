import SwiftUI

struct PlayerView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(DataStore.self) private var dataStore
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(\.dismiss) private var dismiss
    @State private var showComplete = false
    @State private var showLevelUp = false
    @State private var showShareCard = false
    @State private var showSpeedPicker = false

    var body: some View {
        ZStack {
            Color(hex: "F7F8FC").ignoresSafeArea()

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
            } else if showComplete, let episode = player.currentEpisode {
                EpisodeCompleteView(
                    episode: episode,
                    onNextEpisode: {
                        showComplete = false
                        player.skipToNextEpisode()
                    },
                    onSaveVocabulary: {
                        vocabularyStore.saveWords(from: episode)
                        checkLevelUp()
                        if !showLevelUp {
                            showComplete = false
                            player.skipToNextEpisode()
                        }
                    }
                )
            } else {
                playerContent
            }
        }
        .onAppear {
            player.onEpisodeFinished = {
                dataStore.completeEpisode(totalWords: vocabularyStore.totalCount)
                withAnimation(.easeInOut(duration: 0.3)) {
                    showComplete = true
                }
            }
        }
        .fullScreenCover(isPresented: $showShareCard) {
            ShareCardView()
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
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color(hex: "94A3B8"))
                    }
                    Spacer()
                    Text("正在播放")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "64748B"))
                    Spacer()
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: "94A3B8"))
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer().frame(height: 40)

                // Cover art
                if let episode = player.currentEpisode {
                    EpisodeThumbnail(episode: episode, size: 260)
                }

                // Episode info
                VStack(spacing: 6) {
                    Text(player.currentEpisode?.title ?? "")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(hex: "1E293B"))
                        .tracking(-0.5)

                    Text(episodeMetaText)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "94A3B8"))

                    // Phase badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: "3B82F6"))
                            .frame(width: 8, height: 8)
                        Text(player.phase.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: "3B82F6"))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color(hex: "EFF6FF"), in: Capsule())
                }
                .padding(.top, 28)
                .padding(.horizontal, 24)

                // Progress bar (draggable)
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: "E2E8F0"))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: "3B82F6"))
                                .frame(width: progressWidth(in: geo.size.width), height: 6)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let ratio = max(0, min(1, value.location.x / geo.size.width))
                                    let time = Double(ratio) * player.duration
                                    player.seek(to: time)
                                }
                        )
                    }
                    .frame(height: 20)
                    .contentShape(Rectangle())

                    HStack {
                        Text(formatTime(player.progress))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: "94A3B8"))
                        Spacer()
                        Text(formatTime(player.duration))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: "94A3B8"))
                    }
                }
                .padding(.top, 32)
                .padding(.horizontal, 32)

                // Playback controls
                HStack(spacing: 36) {
                    Button { player.skipToPreviousEpisode() } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(hex: "94A3B8"))
                    }

                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(Color(hex: "3B82F6"), in: Circle())
                    }

                    Button { player.skipToNextEpisode() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(hex: "94A3B8"))
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
                                    .foregroundStyle(isSelected ? .white : Color(hex: "64748B"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        isSelected ? Color(hex: "3B82F6") : Color.clear,
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Color(hex: "F1F5F9"), in: Capsule())
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Bottom actions
                HStack(spacing: 32) {
                    Button {
                        player.showSubtitles.toggle()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "captions.bubble")
                                .font(.system(size: 22))
                                .foregroundStyle(player.showSubtitles ? Color(hex: "3B82F6") : Color(hex: "94A3B8"))
                            Text("字幕")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(player.showSubtitles ? Color(hex: "3B82F6") : Color(hex: "94A3B8"))
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
                                .foregroundStyle(player.playbackRate != 1.0 ? Color(hex: "3B82F6") : Color(hex: "64748B"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    player.playbackRate != 1.0 ? Color(hex: "EFF6FF") : Color(hex: "F1F5F9"),
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                            Text("速度")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(player.playbackRate != 1.0 ? Color(hex: "3B82F6") : Color(hex: "94A3B8"))
                        }
                    }

                    Button { toggleCurrentEpisodeStar() } label: {
                        VStack(spacing: 4) {
                            Image(systemName: isCurrentEpisodeStarred ? "star.fill" : "star")
                                .font(.system(size: 22))
                                .foregroundStyle(isCurrentEpisodeStarred ? Color(hex: "F59E0B") : Color(hex: "94A3B8"))
                            Text("收藏")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isCurrentEpisodeStarred ? Color(hex: "F59E0B") : Color(hex: "94A3B8"))
                        }
                    }
                }
                .padding(.top, 28)

                Spacer()
            }

            // Subtitle overlay
            if player.showSubtitles, let episode = player.currentEpisode {
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

    private var episodeMetaText: String {
        guard let episode = player.currentEpisode else { return "" }
        let level = episode.podcastLevel?.tabName ?? ""
        let min = episode.durationSeconds / 60
        let idx = player.episodeQueue.firstIndex(where: { $0.id == episode.id }).map { $0 + 1 } ?? 1
        return "第 \(idx) 集 · \(level) · \(min) 分钟"
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard player.duration > 0 else { return 0 }
        return totalWidth * CGFloat(player.progress / player.duration)
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
}
