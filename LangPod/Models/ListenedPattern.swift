import Foundation

/// A pattern-playback entry for the 播放历史 list. Separate from ListenedEpisode
/// so rendering / filtering can treat podcasts and patterns distinctly.
struct ListenedPattern: Codable, Identifiable {
    let patternId: String
    let episodeId: String
    let template: String
    let translationZh: String
    let scene: String
    let level: String
    let durationSeconds: Int
    let listenedAt: Date
    var isStarred: Bool = false

    var id: String { patternId + listenedAt.description }

    var dayString: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(listenedAt) { return "今天" }
        if calendar.isDateInYesterday(listenedAt) { return "昨天" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: listenedAt)
    }
}
