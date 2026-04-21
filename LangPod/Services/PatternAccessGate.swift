import Foundation

/// Gates pattern playback per the free/pro tier rules:
/// - Today's patterns (parentEpisode.date == today): free for everyone
/// - Historical patterns (parentEpisode.date < today): Pro only
enum PatternAccessGate {
    /// Returns true if the user can play this pattern.
    static func canAccess(pattern: Pattern, parentEpisode: Episode, isPro: Bool) -> Bool {
        if isPro { return true }
        return isToday(parentEpisode.date)
    }

    /// True if the given episode date string matches today's date.
    static func isToday(_ episodeDate: String) -> Bool {
        let today = DateFormatter.episodeDate.string(from: Date())
        return episodeDate == today
    }
}
