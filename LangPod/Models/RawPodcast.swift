import Foundation

/// 真实演讲 / keynote / 访谈的元数据。原音通过 YouTube IFrame 嵌入流式播放，
/// app 不托管音频本身，规避版权风险（YouTube 官方支持的嵌入用法）。
///
/// 学习内容（Easy / Medium / Hard episodes）会通过 `relatedEpisodeIds` 关联回
/// 这条原声，UI 上展示「本期延伸学习」入口；反向 Episode 通过 `sourcePodcastId`
/// 显示「源自硅谷原声」backlink badge。
struct RawPodcast: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let speaker: String
    let event: String
    let mediaType: MediaType            // 原源类型：video (keynote) / audio (podcast)
    let youtubeId: String?              // 原始 YouTube ID（保留用于「在 YouTube 打开」link）
    let audioUrl: String?               // 实际播放 URL（一律走 OSS，国内可访问；可能是 mp4 含视频轨）
    let thumbnail: String?              // OSS 上的缩略图 URL
    let hasVideo: Bool?                 // 真值：audio_url 指向的文件含视频画面，App 用 VideoPlayerLayerView 展示
    let transcriptUrl: String?          // 字幕 JSON URL（OSS 上的，{segments: [{start,end,en,zh}]}）
    let category: String?               // tech_keynote = 硅谷原声 / explore = 探索
    let publishedAt: String
    let durationSeconds: Int
    let topic: String
    let thumbnailColor: String?
    let summaryZh: String?
    let relatedEpisodeIds: [String]?

    enum CodingKeys: String, CodingKey {
        case id, title, speaker, event, topic, thumbnail, category
        case mediaType = "media_type"
        case youtubeId = "youtube_id"
        case audioUrl = "audio_url"
        case hasVideo = "has_video"
        case transcriptUrl = "transcript_url"
        case publishedAt = "published_at"
        case durationSeconds = "duration_seconds"
        case thumbnailColor = "thumbnail_color"
        case summaryZh = "summary_zh"
        case relatedEpisodeIds = "related_episode_ids"
    }

    enum MediaType: String, Codable {
        case video
        case audio
    }

    var dateDisplay: String {
        if let d = DateFormatter.episodeDate.date(from: publishedAt) {
            let f = DateFormatter()
            f.dateFormat = "M月d日"
            return f.string(from: d)
        }
        return publishedAt
    }

    var durationDisplay: String {
        if durationSeconds >= 3600 {
            let h = durationSeconds / 3600
            let m = (durationSeconds % 3600) / 60
            return m > 0 ? "\(h)时\(m)分" : "\(h)小时"
        }
        if durationSeconds >= 60 {
            return "\(durationSeconds / 60)分钟"
        }
        return "\(durationSeconds)秒"
    }

    var watchUrl: URL? {
        if mediaType == .video, let id = youtubeId {
            return URL(string: "https://www.youtube.com/watch?v=\(id)")
        }
        if let s = audioUrl { return URL(string: s) }
        return nil
    }

    /// 缩略图优先级：OSS 自家镜像 → YouTube CDN（备用，国内可能屏蔽）→ nil 走纯色 fallback。
    var displayThumbnailUrl: String? {
        if let t = thumbnail, !t.isEmpty { return t }
        if mediaType == .video, let id = youtubeId {
            return "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg"
        }
        return nil
    }
}
