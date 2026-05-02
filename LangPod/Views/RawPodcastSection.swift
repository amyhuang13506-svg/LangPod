import SwiftUI

/// 首页「硅谷原声」横滑区块。展示真实大佬演讲/keynote/访谈，点击进入对应播放器：
/// - video → YouTube IFrame 全屏
/// - audio → 原生 AVPlayer（后台播 + 锁屏控制）
/// MVP 不做解读层 / 字幕 / 词汇抽取，先验证用户对原声本身的反应。
struct RawPodcastSection: View {
    let podcasts: [RawPodcast]
    @State private var selectedPodcast: RawPodcast?
    @State private var showAllFeed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("硅谷原声")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .tracking(-0.3)
                Spacer()
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

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(podcasts) { podcast in
                        Button { selectedPodcast = podcast } label: {
                            podcastCard(podcast)
                        }
                        .buttonStyle(.plain)
                        // 卡片宽度 = 容器宽度 - 36，让下一张卡左侧露出 ~24pt 提示可滑动
                        .containerRelativeFrame(.horizontal) { length, _ in
                            length - 36
                        }
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
            RawPodcastFeedView(podcasts: podcasts)
        }
    }

    @ViewBuilder
    private func podcastCard(_ podcast: RawPodcast) -> some View {
        switch podcast.mediaType {
        case .video: videoCard(podcast)
        case .audio: audioCard(podcast)
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
            .overlay(alignment: .topLeading) {
                mediaTypeBadge(podcast.mediaType)
                    .padding(12)
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
            .overlay(alignment: .topLeading) {
                mediaTypeBadge(.audio)
                    .padding(12)
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

    private func mediaTypeBadge(_ type: RawPodcast.MediaType) -> some View {
        HStack(spacing: 3) {
            Image(systemName: type == .video ? "video.fill" : "headphones")
                .font(.system(size: 8, weight: .bold))
            Text(type == .video ? "视频" : "音频")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.55), in: Capsule())
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
