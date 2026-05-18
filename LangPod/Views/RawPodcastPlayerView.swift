import SwiftUI
import AVFoundation
import Combine
import MediaPlayer
import UIKit

/// 「硅谷原声」播放页。**统一走 AVPlayer 播 OSS 上的音频**（不管原源是 YouTube
/// 视频还是 RSS 播客），这样国内用户能直接播，且支持后台 + 锁屏。
/// 视频源原本的封面（YouTube 缩略图 → OSS 镜像）作为大图展示在顶部，
/// 形态像 Apple Podcasts —— 看封面 / 听音频。
struct RawPodcastPlayerView: View {
    let podcast: RawPodcast
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(AudioPlayer.self) private var audioPlayer
    @State private var controller: RawAudioController?
    @State private var transcript: RawTranscript?
    @State private var preloadedWords: RawPodcastWords?
    @State private var showPaywall: Bool = false
    @State private var addedWordToast: String?
    @State private var pendingWord: PendingWord?
    @State private var pendingLookup: WordLookup?
    @State private var isLookingUp: Bool = false
    @State private var subtitleVisible: Bool = true   // 折叠 = 隐藏整片字幕；展开 = 显示
    @State private var showChinese: Bool = true       // 中英 / 全英 切换
    @State private var showVideoControls: Bool = false  // 视频区点一下显示控件，3 秒自动隐藏
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var metadataExpanded: Bool = false   // 中间元数据区默认收起

    struct PendingWord: Identifiable {
        let word: String
        let segment: RawTranscriptSegment
        var id: String { word + "-" + segment.id }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部封面（视频画面 + 浮层控件）—— 用 overlay 而不是 ZStack，
                // overlay 严格继承 coverHeader 的尺寸（16:9），不会被控件撑高
                coverHeader
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .overlay {
                        if let c = controller {
                            videoOverlayControls(controller: c)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleVideoControls()
                    }

                // 进度条始终显示在视频下方（细条）
                if let c = controller {
                    ProgressOnlyBar(controller: c)
                        .padding(.top, 12)
                        .padding(.horizontal, 24)
                } else if podcast.audioUrl == nil {
                    audioFallback
                        .padding(24)
                }

                // 标题 + 元数据（可折叠，默认收起）
                metadataSection
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // 字幕区（带顶部小工具栏 + 三档显示模式）
                if let transcript, let c = controller {
                    subtitleArea(transcript: transcript, controller: c)
                } else if podcast.transcriptUrl != nil {
                    Spacer(minLength: 0)
                    transcriptLoading
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                } else {
                    Spacer(minLength: 0)
                }
            }

            Button {
                controller?.pause()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.55), in: Circle())
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // 进入油管播客播放页时，主播客（每日 AI 节目）若在播则中断
            if audioPlayer.isPlaying {
                audioPlayer.togglePlayPause()
            }
            // 走共享 session 拿 controller：同一条 podcast → 复用已有实例，
            // AVPlayer / 解码缓冲 / 视频帧全部保留，秒续播；不同条 → 内部 tear down 旧的建新的。
            let c = RawPlaybackSession.shared.controller(for: podcast)
            controller = c
            // 复用场景下用户期望继续播；旧实例被暂停过则恢复。
            if let c, c.player.timeControlStatus != .playing {
                c.play()
            }
            // 记一条「硅谷原声」播放历史 + 推 streak（当天同一条会去重）
            dataStore.recordRawPodcastPlayStart(podcast)
        }
        .onDisappear {
            // 只暂停，不销毁 —— controller 仍由 RawPlaybackSession 持有。
            // 下次再开同一条直接续播，画面无 reload。
            controller?.pause()
        }
        .task {
            await loadTranscriptIfNeeded()
        }
        // 本 View 自己是用 .fullScreenCover 弹出来的；在里面再叠系统 .sheet 配合
        // AVPlayer + .preferredColorScheme(.dark)，iOS 18 SwiftUI 会偶发 modal 冲突崩溃。
        // 解决：用 fullScreenCover 但套 PaywallSheetCover 模拟 sheet 视觉
        // （顶部圆角 + 留缝 + grabber + 拖拽下拉关闭 + 半透蒙层）。
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallSheetCover(isPresented: $showPaywall)
                .environment(subscriptionManager)
                .presentationBackground(.clear)
        }
        .overlay(alignment: .top) {
            if let toast = addedWordToast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.appPrimary.opacity(0.92), in: Capsule())
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            wordPreviewOverlay
        }
    }

    // MARK: - Video overlay controls (tap to show, auto-hide)

    private func toggleVideoControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showVideoControls.toggle()
        }
        scheduleHideControls()
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        guard showVideoControls else { return }
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showVideoControls = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func videoOverlayControls(controller: RawAudioController) -> some View {
        if showVideoControls {
            ZStack {
                Color.black.opacity(0.35)
                HStack(spacing: 48) {
                    Button {
                        controller.seek(to: max(0, controller.currentTime - 15))
                        scheduleHideControls()
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(.white)
                    }
                    Button {
                        controller.toggle()
                        scheduleHideControls()
                    } label: {
                        Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Color.black.opacity(0.4), in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                    }
                    Button {
                        controller.seek(to: min(controller.duration, controller.currentTime + 30))
                        scheduleHideControls()
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(.white)
                    }
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: - Metadata (collapsible, default collapsed)

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(podcast.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(metadataExpanded ? 3 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        metadataExpanded.toggle()
                    }
                } label: {
                    Image(systemName: metadataExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if metadataExpanded {
                HStack(spacing: 6) {
                    Text(podcast.speaker)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("·")
                        .foregroundStyle(.white.opacity(0.4))
                    Text(podcast.event)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    mediaTag
                    if !podcast.topic.isEmpty {
                        tag(podcast.topic)
                    }
                    tag(podcast.dateDisplay)
                    tag(podcast.durationDisplay)
                }
            }
        }
    }

    private func loadTranscriptIfNeeded() async {
        guard transcript == nil, let url = podcast.transcriptUrl, !url.isEmpty else { return }
        transcript = await APIService.shared.fetchTranscript(transcriptUrl: url, podcastId: podcast.id)
        // 并行拉预翻译词典：用户点词查询走本地查表，0 GPT 延迟
        if preloadedWords == nil {
            preloadedWords = await APIService.shared.fetchPodcastWords(transcriptUrl: url, podcastId: podcast.id)
        }
    }

    // MARK: - Subtitle area (toolbar + 3 modes)

    @ViewBuilder
    private func subtitleArea(transcript: RawTranscript, controller: RawAudioController) -> some View {
        VStack(spacing: 0) {
            subtitleToolbar
            if subtitleVisible {
                RawSubtitleSheet(
                    transcript: transcript,
                    currentTime: controller.currentTime,
                    isPro: subscriptionManager.isProUser,
                    showChinese: showChinese,
                    onUpgrade: { showPaywall = true },
                    onTapWord: { word, segment in
                        // Pro 才有 tap，免费用户拦截升级
                        if subscriptionManager.isProUser {
                            handleWordTap(word, segment: segment)
                        } else {
                            showPaywall = true
                        }
                    },
                    // 点字幕行 → 跳到该段开头，进度条同步
                    onSeek: { time in
                        controller.seek(to: time)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var subtitleToolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "captions.bubble.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
            Text("字幕")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
            if !subscriptionManager.isProUser {
                Text("Pro 解锁中文 + 单词")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color(hex: "FFD60A"))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(hex: "FFD60A").opacity(0.16), in: Capsule())
                    .onTapGesture { showPaywall = true }
            }
            Spacer()
            // 中英 / 全英 切换（只在字幕可见 + Pro 用户时显示，免费用户没中文可切）
            if subtitleVisible && subscriptionManager.isProUser {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showChinese.toggle() }
                } label: {
                    Text(showChinese ? "中英" : "全英")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            // 折叠 / 展开（整片字幕显隐）
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    subtitleVisible.toggle()
                }
            } label: {
                Image(systemName: subtitleVisible ? "chevron.down" : "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Word preview card (overlay)

    @ViewBuilder
    private var wordPreviewOverlay: some View {
        if let pending = pendingWord {
            ZStack(alignment: .bottom) {
                // 半透蒙层，点击空白处关闭
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation { pendingWord = nil }
                    }

                wordPreviewCard(pending)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func wordPreviewCard(_ p: PendingWord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // 单词 + 音标 + 关闭
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(p.word)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                if let phonetic = pendingLookup?.phonetic, !phonetic.isEmpty {
                    Text(phonetic)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                Button {
                    withAnimation { pendingWord = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Color.divider, in: Circle())
                }
            }

            // 释义
            if isLookingUp {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("查词中…")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if let lookup = pendingLookup {
                VStack(alignment: .leading, spacing: 6) {
                    if let pos = lookup.partOfSpeech, !pos.isEmpty {
                        Text(pos)
                            .font(.system(size: 12, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.appPrimary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.primaryLight, in: RoundedRectangle(cornerRadius: 4))
                    }
                    Text(lookup.translation)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("查词失败，请稍后重试")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textTertiary)
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation { pendingWord = nil }
                } label: {
                    Text("取消")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.divider, in: RoundedRectangle(cornerRadius: 12))
                }
                Button {
                    addWord(p.word, segment: p.segment, lookup: pendingLookup)
                    withAnimation { pendingWord = nil }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("加入生词本")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isLookingUp)
                .opacity(isLookingUp ? 0.5 : 1)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 8)
    }

    private func handleWordTap(_ word: String, segment: RawTranscriptSegment) {
        let pending = PendingWord(word: word, segment: segment)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            pendingWord = pending
        }

        // Fast path：服务端预翻译词典命中 → 即时返回
        let lower = word.lowercased()
        if let entry = preloadedWords?.words[lower] {
            pendingLookup = WordLookup(
                phonetic: entry.phonetic,
                partOfSpeech: entry.pos,
                translation: entry.zh,
                example: entry.example
            )
            isLookingUp = false
            return
        }

        // Fallback：词典里没有（比如生僻词 / stopword 被跳过 / 服务端尚未预译） → 走 GPT
        pendingLookup = nil
        isLookingUp = true
        Task {
            let result = await WordLookupService.shared.lookup(word: word, context: segment.en)
            await MainActor.run {
                guard self.pendingWord?.word == word else { return }
                self.pendingLookup = result
                self.isLookingUp = false
            }
        }
    }

    private var transcriptLoading: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
            Text("字幕加载中…")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }

    private func addWord(_ word: String, segment: RawTranscriptSegment, lookup: WordLookup? = nil) {
        // 优先用查词结果（精准翻译 + 音标），fallback 段级中文
        let vocab = VocabularyItem(
            word: word,
            phonetic: lookup?.phonetic ?? "",
            translationZh: lookup?.translation ?? (segment.zh ?? ""),
            example: segment.en,
            exampleZh: segment.zh,
            audio: ""
        )
        let added = vocabularyStore.addWord(vocab, sourceLabel: "raw_podcast")
        let toastText = added ? "「\(word)」已加入生词本" : "「\(word)」已在生词本"
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            addedWordToast = toastText
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation { addedWordToast = nil }
            }
        }
    }

    @ViewBuilder
    private var coverHeader: some View {
        if let c = controller, podcast.hasVideo == true {
            // 视频源：底铺缩略图（AVPlayer 缓冲首帧前防止黑屏），视频层叠在上面，
            // 首帧就绪后自然盖住缩略图。
            ZStack {
                if let thumb = podcast.displayThumbnailUrl {
                    CachedAsyncImage(url: thumb) {
                        bgGradient
                    }
                    .scaledToFill()
                    .clipped()
                } else {
                    bgGradient
                }
                VideoPlayerLayerView(player: c.player)
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
        } else if let thumb = podcast.displayThumbnailUrl {
            CachedAsyncImage(url: thumb) {
                bgGradient
            }
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipped()
        } else {
            bgGradient
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 96, weight: .light))
                        .foregroundStyle(.white.opacity(0.22))
                )
        }
    }

    private var bgGradient: some View {
        LinearGradient(
            colors: [coverColor, coverColor.opacity(0.65)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var coverColor: Color {
        if let hex = podcast.thumbnailColor {
            var s = hex
            if s.hasPrefix("#") { s.removeFirst() }
            if s.count == 6, let v = UInt64(s, radix: 16) {
                return Color(
                    red: Double((v >> 16) & 0xFF) / 255.0,
                    green: Double((v >> 8) & 0xFF) / 255.0,
                    blue: Double(v & 0xFF) / 255.0
                )
            }
        }
        return Color(hex: "252B3F")
    }

    private var audioFallback: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("音频源处理中，请稍后再试")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.12), in: Capsule())
    }

    private var mediaTag: some View {
        HStack(spacing: 3) {
            Image(systemName: podcast.mediaType == .video ? "video.fill" : "headphones")
                .font(.system(size: 9))
            Text(podcast.mediaType == .video ? "视频源" : "播客")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.appPrimary.opacity(0.7), in: Capsule())
    }

    /// 「本期延伸学习」—— 把这条原声生成的 Easy/Medium/Hard 解读集列出。
    @ViewBuilder
    private var relatedEpisodesSection: some View {
        let related = dataStore.episodes.filter {
            podcast.relatedEpisodeIds?.contains($0.id) == true
        }
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "FFD60A"))
                    Text("本期延伸学习")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 8)

                ForEach(related) { ep in
                    relatedEpisodeRow(ep)
                }
            }
        }
    }

    private func relatedEpisodeRow(_ ep: Episode) -> some View {
        HStack(spacing: 12) {
            EpisodeThumbnail(episode: ep, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(ep.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(ep.podcastLevel?.tabName ?? "")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                    Text(ep.durationDisplay)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(12)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Paywall sheet visual wrapper

/// 把 PaywallView 包成「sheet 视觉」的容器，但底层走 .fullScreenCover —— 避免
/// 「fullScreenCover 内嵌 .sheet」在 iOS 18 SwiftUI + AVPlayer + dark scheme 下
/// 偶发 modal 冲突崩溃的已知问题。
///
/// 视觉特征（贴近系统 sheet）：
/// - 顶部留 50pt 缝隙，露出底层 RawPodcastPlayerView
/// - 顶部圆角 28pt + grabber 拉手
/// - 黑色半透明 backdrop，淡入
/// - 拖拽下拉超过阈值关闭（仅响应 grabber 区域，避免和 PaywallView 内 ScrollView 冲突）
/// - 点击 backdrop 关闭（系统 fullScreenCover 自带从底滑下的 dismiss 动画）
private struct PaywallSheetCover: View {
    @Binding var isPresented: Bool
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var dragOffset: CGFloat = 0
    @State private var backdropOpacity: Double = 0

    private let topInset: CGFloat = 50
    private let dismissThreshold: CGFloat = 120
    private let cornerRadius: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // Backdrop —— 点击关闭
                Color.black
                    .opacity(backdropOpacity)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isPresented = false
                    }

                // Sheet 卡片（PaywallView + 顶部 grabber 叠层）
                ZStack(alignment: .top) {
                    // 底色层：圆角顶部 + 一直延伸到屏幕底（含 home indicator 安全区）。
                    // PaywallView 本体的 gradient 背景止于 safe area，下方 34pt 由这层白色补齐。
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: cornerRadius,
                            bottomLeading: 0,
                            bottomTrailing: 0,
                            topTrailing: cornerRadius
                        )
                    )
                    .fill(Color.white)
                    .ignoresSafeArea(edges: .bottom)

                    PaywallView()
                        .environment(subscriptionManager)
                        .clipShape(
                            .rect(
                                topLeadingRadius: cornerRadius,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: cornerRadius
                            )
                        )

                    // Grabber 拉手 + 拖拽热区（仅这块响应下拉关闭，不干扰 PaywallView 的 ScrollView）
                    VStack(spacing: 0) {
                        Capsule()
                            .fill(Color.black.opacity(0.22))
                            .frame(width: 38, height: 5)
                            .padding(.top, 8)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if value.translation.height >= 0 {
                                    dragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                if value.translation.height > dismissThreshold {
                                    // 下拉超过阈值：先把卡片继续滑出去，
                                    // 再 flip isPresented 让系统 dismiss（此时已不可见）
                                    withAnimation(.easeOut(duration: 0.22)) {
                                        dragOffset = geo.size.height
                                        backdropOpacity = 0
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                        isPresented = false
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
                }
                .padding(.top, topInset)
                .offset(y: dragOffset)
            }
        }
        .background(Color.clear)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                backdropOpacity = 0.45
            }
        }
    }
}

// MARK: - Playback session (shared across view lifecycle)

/// 持有当前活跃的 RawAudioController。SwiftUI 关掉 fullScreenCover 不会销毁
/// 这里的 controller —— 用户再打开同一条原声时，AVPlayer / 视频缓冲 / 解码器
/// 都还在，画面秒续，不会"明显重新加载"。
/// 切换到另一条原声 → tear down 旧的，建新的。
@Observable
final class RawPlaybackSession {
    static let shared = RawPlaybackSession()
    private init() {}

    var controller: RawAudioController?

    /// 返回当前 podcast 的 controller —— 同一条则复用（断点续播），不同条则换。
    /// 没有 audioUrl 的返回 nil。
    func controller(for podcast: RawPodcast) -> RawAudioController? {
        if let existing = controller, existing.podcast.id == podcast.id {
            return existing
        }
        controller?.tearDown()
        controller = nil
        guard let urlStr = podcast.audioUrl, let url = URL(string: urlStr) else { return nil }
        let c = RawAudioController(url: url, podcast: podcast)
        controller = c
        return c
    }

    func clear() {
        controller?.tearDown()
        controller = nil
    }
}

// MARK: - Audio/Video controls (AVPlayer-based, supports background play + lock screen)

/// 单个 AVPlayer 实例同时驱动视频画面（VideoPlayerLayerView）和控件 UI。
/// 用 KVO observe player.timeControlStatus，UI 显示「实际是否在播放」而不是
/// 「我们调用过 play()」—— 解决「tap 一次不响应、tap 第二次才播」的 bug。
@Observable
final class RawAudioController {
    let player: AVPlayer
    let podcast: RawPodcast
    var isPlaying: Bool = false
    var currentTime: Double = 0
    var duration: Double = 0
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var bgLifecycleObserver: NSObjectProtocol?
    private var fgLifecycleObserver: NSObjectProtocol?
    private var artwork: UIImage?

    /// 持久化进度的 UserDefaults key 前缀（按 podcast.id 隔离）
    private static let positionKeyPrefix = "raw_pos_"

    /// 上次写盘的时间，节流避免 0.5s 一次 IO
    private var lastSavedTime: Double = 0

    /// 启动时从 UserDefaults 拉的恢复位置；status ready 后 seek 一次
    private var resumePosition: Double = 0

    static func savedPosition(for podcastId: String) -> Double {
        UserDefaults.standard.double(forKey: positionKeyPrefix + podcastId)
    }

    static func savePosition(_ seconds: Double, for podcastId: String) {
        UserDefaults.standard.set(seconds, forKey: positionKeyPrefix + podcastId)
    }

    static func clearSavedPosition(for podcastId: String) {
        UserDefaults.standard.removeObject(forKey: positionKeyPrefix + podcastId)
    }

    init(url: URL, podcast: RawPodcast) {
        self.podcast = podcast
        // 必须先把 AVAudioSession 切到 playback，否则 AVPlayer 不会出声
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[RawAudio] AVAudioSession 设置失败: \(error)")
        }
        self.player = AVPlayer(url: url)
        // 视频内容首播时让 AVPlayer 等待足够缓冲再 start，避免出现"音频响但画面停在
        // 封面"的撕裂（首帧 keyframe 可能在视频开头 1-3s，缓冲未到时画面空）。
        // 纯音频时仍可走快速启动。
        self.player.automaticallyWaitsToMinimizeStalling = (podcast.hasVideo == true)
        // 预设 3s 前向缓冲，让 first frame 决策有充足数据。
        self.player.currentItem?.preferredForwardBufferDuration = 3.0
        // 读上次保存的进度（>1s 才算有意义；接近结尾也忽略，让用户从头听）
        self.resumePosition = Self.savedPosition(for: podcast.id)
        addPeriodicObserver()
        observeStatus()
        observeAppLifecycle()
        publishNowPlayingInfo()
        loadArtwork()
        // 不在这里直接 play()。observeStatus 里 readyToPlay 后做 seek + play，避免
        // 用户先听到 0s 一段再被拉回保存点的撕裂感。
    }

    /// 后台音频续播：保持 AVPlayer 不停，只是关掉视频轨解码（layer 也无须解绑）。
    /// 这样回前台时无重建、无重缓冲，画面立即恢复，丝滑无停顿。
    private func observeAppLifecycle() {
        bgLifecycleObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.setVideoTracksEnabled(false)
        }
        fgLifecycleObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.setVideoTracksEnabled(true)
        }
    }

    private func setVideoTracksEnabled(_ enabled: Bool) {
        guard let item = player.currentItem else { return }
        for track in item.tracks where track.assetTrack?.mediaType == .video {
            track.isEnabled = enabled
        }
    }

    private func addPeriodicObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds.isFinite ? time.seconds : 0
            self.currentTime = seconds
            // 每 0.5s 同步一次锁屏信息（进度条 + 播放状态）
            self.updateNowPlayingTime()
            // 进度持久化：节流为 5s 一次，避免频繁 IO
            if seconds > 0 && abs(seconds - self.lastSavedTime) >= 5.0 {
                Self.savePosition(seconds, for: self.podcast.id)
                self.lastSavedTime = seconds
            }
        }
    }

    private func observeStatus() {
        // 监听 item.status —— readyToPlay 时拿 duration + seek 到上次进度
        if let item = player.currentItem {
            statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard let self, item.status == .readyToPlay else { return }
                Task { @MainActor in
                    let d = item.duration.seconds
                    if d.isFinite && d > 0 { self.duration = d }
                    // 首次 ready 时根据 resumePosition 决定从哪开始
                    self.startPlaybackHonoringResume()
                }
            }
        }
        // 监听 timeControlStatus —— UI 反映「真的在播放」状态
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = (player.timeControlStatus == .playing)
            }
        }
    }

    /// 只在 ready 后做一次 seek+play；后续 ready 事件不再 seek（用户可能已 seek 过）
    private var didStartPlayback: Bool = false

    private func startPlaybackHonoringResume() {
        guard !didStartPlayback else { return }
        didStartPlayback = true

        let target = resumePosition
        let total = duration  // 可能此刻还没拿到（0），无所谓——0 会通过下面的「near end」判断

        // 太靠开头（<1s）或太靠结尾（剩 <5s）都从 0 开始；其余 seek 后再 play
        let isMeaningful = target > 1.0 && (total <= 0 || (total - target) > 5.0)
        if isMeaningful {
            let t = CMTime(seconds: target, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                self?.play()
            }
        } else {
            play()
        }
    }

    func play() {
        player.play()
        // 立刻声明自己是锁屏的控制目标 —— 主 AudioPlayer 之前可能 active 着，要顶掉。
        RemoteCommandRouter.shared.active = self
        publishNowPlayingInfo()
    }

    func pause() {
        player.pause()
    }

    func toggle() {
        // 看 player 真实状态，不依赖我们自己的 flag
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            play()
        }
    }

    func seek(to seconds: Double) {
        let t = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: t)
    }

    /// 主动清理资源（被 RawPlaybackSession 在切换 podcast 时调用）。
    /// deinit 也会做同样的事，但 ARC 析构时机不可控，显式 tearDown 更稳。
    func tearDown() {
        if currentTime > 1.0 {
            Self.savePosition(currentTime, for: podcast.id)
        }
        player.pause()
        if let obs = timeObserver { player.removeTimeObserver(obs); timeObserver = nil }
        statusObserver?.invalidate(); statusObserver = nil
        rateObserver?.invalidate(); rateObserver = nil
        timeControlObserver?.invalidate(); timeControlObserver = nil
        if let o = bgLifecycleObserver { NotificationCenter.default.removeObserver(o); bgLifecycleObserver = nil }
        if let o = fgLifecycleObserver { NotificationCenter.default.removeObserver(o); fgLifecycleObserver = nil }
        // 如果我是当前 active，让出去；不然会 dangling
        if RemoteCommandRouter.shared.active === self {
            RemoteCommandRouter.shared.active = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    deinit {
        // 控制器销毁前，保证最新进度被持久化（周期 saver 节流 5s，可能丢最后几秒）
        if currentTime > 1.0 {
            Self.savePosition(currentTime, for: podcast.id)
        }
        if let obs = timeObserver { player.removeTimeObserver(obs) }
        statusObserver?.invalidate()
        rateObserver?.invalidate()
        timeControlObserver?.invalidate()
        if let o = bgLifecycleObserver { NotificationCenter.default.removeObserver(o) }
        if let o = fgLifecycleObserver { NotificationCenter.default.removeObserver(o) }
        // 不再 removeTarget(nil) —— handler 全部归 RemoteCommandRouter 管理。
        // 如果我还是 active，让出去。
        if RemoteCommandRouter.shared.active === self {
            RemoteCommandRouter.shared.active = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    // MARK: - 锁屏 / 控制中心 (MPNowPlayingInfoCenter)
    //
    // MPRemoteCommand handler 全部归 RemoteCommandRouter.shared 统一管理；这里只
    // 负责发布 nowPlayingInfo（封面/标题/进度），让锁屏 widget 渲染。

    private func publishNowPlayingInfo() {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = podcast.title
        info[MPMediaItemPropertyArtist] = podcast.speaker
        info[MPMediaItemPropertyAlbumTitle] = podcast.event
        info[MPMediaItemPropertyPlaybackDuration] = duration > 0 ? duration : Double(podcast.durationSeconds)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = (player.timeControlStatus == .playing) ? 1.0 : 0.0
        if let art = artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
        }
        // hasVideo == true 时标记 video 类型，锁屏会显示「正在播放视频」icon
        info[MPNowPlayingInfoPropertyMediaType] = (podcast.hasVideo == true)
            ? MPNowPlayingInfoMediaType.video.rawValue
            : MPNowPlayingInfoMediaType.audio.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingTime() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            publishNowPlayingInfo()
            return
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = (player.timeControlStatus == .playing) ? 1.0 : 0.0
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork() {
        guard let urlStr = podcast.thumbnail, !urlStr.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            if let img = await ImageCache.shared.image(for: urlStr) {
                await MainActor.run {
                    self.artwork = img
                    self.publishNowPlayingInfo()
                }
            }
        }
    }
}

// MARK: - RemoteControllable

extension RawAudioController: RemoteControllable {
    func remoteTogglePlay() { toggle() }
    func remoteSkipForward() {
        seek(to: min(duration, currentTime + 30))
    }
    func remoteSkipBackward() {
        seek(to: max(0, currentTime - 15))
    }
    func remoteSeek(to seconds: Double) {
        seek(to: seconds)
    }
}

/// AVPlayerLayer 包装：在 SwiftUI 里展示视频画面。复用同一个 AVPlayer 实例，
/// 这样视频画面和音频控件天然同步。
/// 背景设为 `.clear`，AVPlayer 缓冲首帧前底层缩略图能透出来，避免黑屏。
/// 后台音频续播由 RawAudioController 通过禁用视频轨道实现，layer 始终保持 attached。
struct VideoPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerHostView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    final class PlayerLayerHostView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear   // 缩略图能透出来
            playerLayer.videoGravity = .resizeAspect
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    }
}

/// 视频下方的细进度条（不含三个按钮 —— 那三个移到了视频区域 overlay）
struct ProgressOnlyBar: View {
    let controller: RawAudioController
    @State private var isDragging: Bool = false
    /// 拖动期间的本地预览位置（秒）。nil 表示没在拖动，UI 跟随 controller.currentTime。
    /// 松手后保留，直到 controller.currentTime 真正赶上 seekTarget，避免 seek 异步导致的"先回弹再跳"。
    @State private var dragPreviewTime: Double? = nil
    @State private var seekTarget: Double? = nil

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let filled = progressWidth(in: geo.size.width)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 3)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: filled, height: 3)
                    Circle()
                        .fill(Color.white)
                        .frame(width: isDragging ? 16 : 10, height: isDragging ? 16 : 10)
                        .shadow(color: .black.opacity(0.35), radius: isDragging ? 4 : 2, y: 1)
                        .offset(x: filled - (isDragging ? 8 : 5))
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isDragging)
                }
                .frame(height: 22)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard controller.duration > 0 else { return }
                            if !isDragging { isDragging = true }
                            // 拖动时只更新本地 preview，UI 立刻跟手；不调 seek 避免 AVPlayer 反复加载 buffer
                            let ratio = max(0, min(1, value.location.x / geo.size.width))
                            dragPreviewTime = ratio * controller.duration
                        }
                        .onEnded { _ in
                            // 松手才真正 seek 一次。preview 保留，等 currentTime 赶上再清
                            if let t = dragPreviewTime {
                                seekTarget = t
                                controller.seek(to: t)
                            } else {
                                dragPreviewTime = nil
                            }
                            isDragging = false
                        }
                )
            }
            .frame(height: 22)
            .onChange(of: controller.currentTime) { _, newTime in
                // currentTime 追上 seek 目标（500ms 内）→ 切回真实进度
                if let target = seekTarget, abs(newTime - target) < 0.5 {
                    seekTarget = nil
                    dragPreviewTime = nil
                }
            }

            HStack {
                Text(formatTime(displayTime))
                Spacer()
                Text(formatTime(controller.duration))
            }
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var displayTime: Double {
        dragPreviewTime ?? controller.currentTime
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard controller.duration > 0 else { return 0 }
        return totalWidth * CGFloat(displayTime / controller.duration)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct AudioControls: View {
    let controller: RawAudioController
    @State private var isDragging: Bool = false
    @State private var dragPreviewTime: Double? = nil
    @State private var seekTarget: Double? = nil

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let filled = progressWidth(in: geo.size.width)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: filled, height: 4)
                    Circle()
                        .fill(Color.white)
                        .frame(width: isDragging ? 18 : 12, height: isDragging ? 18 : 12)
                        .shadow(color: .black.opacity(0.35), radius: isDragging ? 4 : 2, y: 1)
                        .offset(x: filled - (isDragging ? 9 : 6))
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isDragging)
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard controller.duration > 0 else { return }
                            if !isDragging { isDragging = true }
                            let ratio = max(0, min(1, value.location.x / geo.size.width))
                            dragPreviewTime = ratio * controller.duration
                        }
                        .onEnded { _ in
                            if let t = dragPreviewTime {
                                seekTarget = t
                                controller.seek(to: t)
                            } else {
                                dragPreviewTime = nil
                            }
                            isDragging = false
                        }
                )
            }
            .frame(height: 24)
            .onChange(of: controller.currentTime) { _, newTime in
                if let target = seekTarget, abs(newTime - target) < 0.5 {
                    seekTarget = nil
                    dragPreviewTime = nil
                }
            }

            HStack {
                Text(formatTime(displayTime))
                Spacer()
                Text(formatTime(controller.duration))
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.6))

            HStack(spacing: 36) {
                Button {
                    controller.seek(to: max(0, controller.currentTime - 15))
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Button {
                    controller.toggle()
                } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(.white, in: Circle())
                }
                Button {
                    controller.seek(to: min(controller.duration, controller.currentTime + 30))
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }

    private var displayTime: Double {
        dragPreviewTime ?? controller.currentTime
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard controller.duration > 0 else { return 0 }
        return totalWidth * CGFloat(displayTime / controller.duration)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
