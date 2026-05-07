import SwiftUI

/// 通用 raw_podcast 横滑区块。
/// - title 默认 "今日推荐"，可传入分类名（"娱乐 · 文化" 等）做探索分类行
/// - compact=true 用 220pt 卡片宽度（多张并排），false 用 hero 全宽
/// - "查看更多" → RawPodcastFeedView，传入 allPodcasts
struct RawPodcastSection: View {
    let title: String
    let podcasts: [RawPodcast]
    /// "查看更多"页面用的完整列表（默认就是 podcasts；可传更大的池子，比如某分类全集）
    let allPodcasts: [RawPodcast]
    /// compact = 卡片宽度 ~220pt，一屏可见 2-3 张（用于探索分类多行并列）
    /// 非 compact = 卡片几乎全宽（"今日推荐"hero 样式）
    let compact: Bool
    /// 是否显示右上角"查看更多"
    let showSeeMore: Bool
    @State private var selectedPodcast: RawPodcast?
    @State private var showAllFeed: Bool = false

    init(
        title: String = "今日推荐",
        podcasts: [RawPodcast],
        allPodcasts: [RawPodcast]? = nil,
        compact: Bool = false,
        showSeeMore: Bool = true
    ) {
        self.title = title
        self.podcasts = podcasts
        self.allPodcasts = allPodcasts ?? podcasts
        self.compact = compact
        self.showSeeMore = showSeeMore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: compact ? 17 : 22, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .tracking(-0.3)
                Spacer()
                if showSeeMore {
                    Button { showAllFeed = true } label: {
                        HStack(spacing: 3) {
                            Text("查看更多")
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.appPrimary)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(podcasts) { podcast in
                        Button { selectedPodcast = podcast } label: {
                            podcastCard(podcast)
                        }
                        .buttonStyle(.plain)
                        .modifier(CardWidthModifier(compact: compact))
                    }
                }
                .scrollTargetLayout()
            }
            .scrollClipDisabled()
            .scrollTargetBehavior(.viewAligned)
        }
        .fullScreenCover(item: $selectedPodcast) { podcast in
            RawPodcastPlayerView(podcast: podcast)
        }
        .fullScreenCover(isPresented: $showAllFeed) {
            RawPodcastFeedView(title: title, podcasts: allPodcasts)
        }
    }

    @ViewBuilder
    private func podcastCard(_ podcast: RawPodcast) -> some View {
        if compact {
            compactCard(podcast)
        } else {
            switch podcast.mediaType {
            case .video: videoCard(podcast)
            case .audio: audioCard(podcast)
            }
        }
    }

    /// Compact 卡片：16:9 缩略图 + 标题/speaker 放在下方（YouTube/B站样式）
    private func compactCard(_ podcast: RawPodcast) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 缩略图：纯图（标题不再 overlay 在图上）+ 媒体类型徽章 + 时长徽章
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay(
                    Group {
                        if let thumb = podcast.displayThumbnailUrl {
                            CachedAsyncImage(url: thumb) {
                                Rectangle().fill(cardBgColor(podcast))
                            }
                            .scaledToFill()
                        } else {
                            Rectangle().fill(cardBgColor(podcast))
                        }
                    }
                )
                .overlay(alignment: .bottomTrailing) {
                    Text(podcast.durationDisplay)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                        .padding(8)
                }
                .overlay(alignment: .topTrailing) {
                    if podcast.isNewToday {
                        newBadge.padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // 文字信息：标题 + speaker
            VStack(alignment: .leading, spacing: 3) {
                Text(podcast.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 36, alignment: .topLeading)
                Text(podcast.speaker)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func videoCard(_ podcast: RawPodcast) -> some View {
        // 16:9 容器 + overlay 叠加，避免多层 aspectRatio 嵌套导致的尺寸/重叠 bug
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay(
                Group {
                    if let thumb = podcast.displayThumbnailUrl {
                        CachedAsyncImage(url: thumb) {
                            Rectangle().fill(cardBgColor(podcast))
                        }
                        .scaledToFill()
                    } else {
                        Rectangle().fill(cardBgColor(podcast))
                    }
                }
            )
            .overlay(
                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(0.4), Color.black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .topTrailing) {
                if podcast.isNewToday {
                    newBadge.padding(12)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(podcast.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 5) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 12))
                        Text(podcast.speaker)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text("·")
                            .font(.system(size: 12))
                        Text(podcast.durationDisplay)
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.white.opacity(0.92))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
    }

    private func audioCard(_ podcast: RawPodcast) -> some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay(
                Group {
                    if let thumb = podcast.displayThumbnailUrl {
                        // 播客封面虚化作为背景（音频节目通常有强视觉的封面）
                        CachedAsyncImage(url: thumb) {
                            LinearGradient(
                                colors: [cardBgColor(podcast), cardBgColor(podcast).opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                        .scaledToFill()
                        .blur(radius: 12)
                    } else {
                        LinearGradient(
                            colors: [cardBgColor(podcast), cardBgColor(podcast).opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            )
            .overlay(
                Image(systemName: "waveform")
                    .font(.system(size: 88, weight: .light))
                    .foregroundStyle(.white.opacity(0.18))
            )
            .overlay(alignment: .topTrailing) {
                if podcast.isNewToday {
                    newBadge.padding(12)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(podcast.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 5) {
                        Image(systemName: "headphones")
                            .font(.system(size: 12))
                        Text(podcast.speaker)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text("·")
                            .font(.system(size: 12))
                        Text(podcast.durationDisplay)
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.white.opacity(0.92))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
    }

    /// 今日上新角标 — 鲜红色 NEW 胶囊
    private var newBadge: some View {
        Text("NEW")
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(red: 1.0, green: 0.23, blue: 0.19), in: Capsule())
    }

    private func cardBgColor(_ podcast: RawPodcast) -> Color {
        if let hex = podcast.thumbnailColor, let c = colorFromHex(hex) {
            return c
        }
        return Color(hex: "1A2540")
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

/// 卡片宽度策略：hero（"今日推荐"）几乎全宽；compact（探索分类）固定 220pt
private struct CardWidthModifier: ViewModifier {
    let compact: Bool

    func body(content: Content) -> some View {
        if compact {
            content.frame(width: 220)
        } else {
            content.containerRelativeFrame(.horizontal) { length, _ in length - 36 }
        }
    }
}
