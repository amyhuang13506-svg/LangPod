import Foundation

/// A pattern-playback entry for the 播放历史 list. Separate from ListenedEpisode
/// so rendering / filtering can treat podcasts and patterns distinctly.
struct ListenedPattern: Codable, Identifiable {
    let patternId: String
    let episodeId: String
    let template: String
    let translation: String
    let scene: String
    let level: String
    let durationSeconds: Int
    let listenedAt: Date
    var isStarred: Bool = false

    var id: String { patternId + listenedAt.description }

    init(patternId: String, episodeId: String, template: String, translation: String,
         scene: String, level: String, durationSeconds: Int, listenedAt: Date,
         isStarred: Bool = false) {
        self.patternId = patternId
        self.episodeId = episodeId
        self.template = template
        self.translation = translation
        self.scene = scene
        self.level = level
        self.durationSeconds = durationSeconds
        self.listenedAt = listenedAt
        self.isStarred = isStarred
    }

    /// 兼容 rename 前老数据（key 为 "translationZh"）。
    private enum LegacyKeys: String, CodingKey { case translationZh }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        patternId = try c.decode(String.self, forKey: .patternId)
        episodeId = try c.decode(String.self, forKey: .episodeId)
        template = try c.decode(String.self, forKey: .template)
        translation = try c.decodeIfPresent(String.self, forKey: .translation)
            ?? legacy.decode(String.self, forKey: .translationZh)
        scene = try c.decode(String.self, forKey: .scene)
        level = try c.decode(String.self, forKey: .level)
        durationSeconds = try c.decode(Int.self, forKey: .durationSeconds)
        listenedAt = try c.decode(Date.self, forKey: .listenedAt)
        isStarred = try c.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
    }

    var dayString: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(listenedAt) { return String(localized: "今天") }
        if calendar.isDateInYesterday(listenedAt) { return String(localized: "昨天") }
        return listenedAt.formatted(.dateTime.month().day())
    }
}
