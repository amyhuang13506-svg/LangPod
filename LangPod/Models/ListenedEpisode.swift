import Foundation

struct ListenedEpisode: Codable, Identifiable {
    let episodeId: String
    let title: String
    let level: String
    let durationSeconds: Int
    let listenedAt: Date
    var isStarred: Bool = false

    var id: String { episodeId + listenedAt.description }

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: listenedAt)
    }

    var dayString: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(listenedAt) { return "今天" }
        if calendar.isDateInYesterday(listenedAt) { return "昨天" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: listenedAt)
    }
}
