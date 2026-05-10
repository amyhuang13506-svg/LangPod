import Foundation

/// 「硅谷原声」(YouTube / RSS 油管播客) 的播放历史条目。和 ListenedEpisode /
/// ListenedPattern 同级，记录页用同一个 unified history 列表展示。
struct ListenedRawPodcast: Codable, Identifiable {
    let podcastId: String
    let title: String
    let speaker: String
    /// "video" 或 "audio"，用于历史 row 上展示「视频源 / 播客」标签
    let mediaType: String
    let thumbnail: String?
    let durationSeconds: Int
    let listenedAt: Date
    var isStarred: Bool = false

    var id: String { podcastId + listenedAt.description }

    var dayString: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(listenedAt) { return "今天" }
        if calendar.isDateInYesterday(listenedAt) { return "昨天" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: listenedAt)
    }
}
