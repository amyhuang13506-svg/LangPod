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
    /// When the pipeline ingested this video into our master list (UTC ISO).
    /// Used by the home "今日推荐" section to surface freshly-pulled videos
    /// at the top regardless of their original YouTube upload date — which is
    /// the field that anchors "newness" from the user's perspective on the app.
    /// Optional for backward compat with older master entries.
    let crawledAt: String?
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
        case crawledAt = "crawled_at"
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

    private static let iso8601 = ISO8601DateFormatter()

    /// 是否为今日上新 — 优先看 crawledAt（pipeline 入库时间），新流水可信。
    /// 老条目无 crawledAt 时回退到 publishedAt 比较。
    ///
    /// crawledAt 是 UTC（"…Z"），而 cron 在 04:00 CST = 前一天 20:00 UTC 入库，
    /// 裸截 prefix(10) 比本地日期会差一天 → 角标永远不亮。改为把 UTC 瞬间
    /// 换算到设备本地时区再按本地日历判断「是否今天」。
    var isNewToday: Bool {
        if let c = crawledAt, !c.isEmpty,
           let date = RawPodcast.iso8601.date(from: c) {
            return Calendar.current.isDateInToday(date)
        }
        return publishedAt == DateFormatter.episodeDate.string(from: Date())
    }

    /// "今日推荐"排序专用 key：crawledAt 比 publishedAt 更能反映"今天有没有新货"。
    /// 老数据回退到 publishedAt，保留后排出现的兜底秩序。
    var sortKey: String {
        if let c = crawledAt, !c.isEmpty { return c }
        return publishedAt
    }

    /// 时长显示，YouTube 风格：≥1h 用 H:MM:SS，否则 M:SS。
    var durationDisplay: String {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        let s = durationSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
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

    /// 探索区分类：根据 topic 关键词归到 6 大类之一。
    /// 用于首页「探索」分类横滑展示。
    var exploreCategory: ExploreCategory? {
        let t = topic
        if t.contains("娱乐") || t.contains("时尚") || t.contains("文化") { return .entertainment }
        if t.contains("两性") || t.contains("心理") || t.contains("关系") { return .relationship }
        if t.contains("科学") || t.contains("数学") || t.contains("科普") { return .science }
        if t.contains("创业") || t.contains("商业") || t.contains("投资") { return .business }
        if t.contains("评测") { return .tech }
        if t.contains("思想") || t.contains("演讲") || t.contains("学术") || t.contains("访谈") || t.contains("健康") { return .mind }
        return nil
    }
}

/// 「探索」区的 6 大分类。每个分类在首页占一个横滑 row，右上角"查看更多"。
enum ExploreCategory: String, CaseIterable, Identifiable, Hashable {
    case entertainment    // 娱乐 · 文化（Hot Ones / Vogue / Vanity Fair / WIRED）
    case relationship     // 两性 · 心理（Matthew Hussey / Jay Shetty / School of Life / Mark Manson / MedCircle）
    case mind             // 思想 · 访谈（TED / Huberman / Diary of CEO / Modern Wisdom / Tim Ferriss）
    case science          // 科普 · 科学（Veritasium / Kurzgesagt / 3Blue1Brown）
    case business         // 创业 · 商业（YC / Stanford / Acquired）
    case tech             // 科技 · 评测（MKBHD）

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .entertainment: return "娱乐 · 文化"
        case .relationship:  return "两性 · 心理"
        case .mind:          return "思想 · 访谈"
        case .science:       return "科普 · 科学"
        case .business:      return "创业 · 商业"
        case .tech:          return "科技 · 评测"
        }
    }

    /// 首页展示顺序（娱乐 / 两性优先 — 用户偏好大众传播性内容）
    static var displayOrder: [ExploreCategory] {
        [.entertainment, .relationship, .mind, .science, .business, .tech]
    }
}
