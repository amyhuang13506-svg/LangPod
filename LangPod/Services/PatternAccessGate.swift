import Foundation

/// Gates pattern playback per the free/pro tier rules:
/// - Pro users: unlimited access to today's and historical patterns.
/// - Free users: no historical access; for today's patterns, up to
///   `SubscriptionManager.freeMaxDailyPatterns` unique pattern IDs per day.
///   Replaying a pattern already counted today stays accessible (no extra
///   quota consumed).
enum PatternAccessGate {
    /// Full gate: combines historical check + daily quota for free users.
    static func canAccess(
        pattern: Pattern,
        parentEpisode: Episode,
        isPro: Bool,
        playedTodayIds: Set<String>
    ) -> Bool {
        if isPro { return true }
        guard isToday(parentEpisode.date) else { return false }
        if playedTodayIds.contains(pattern.id) { return true }
        return playedTodayIds.count < SubscriptionManager.freeMaxDailyPatterns
    }

    /// Whether a whole date group is "today". Used by list UI to decide group-level lock icons.
    static func isToday(_ episodeDate: String) -> Bool {
        let today = DateFormatter.episodeDate.string(from: Date())
        return episodeDate == today
    }

    /// Whether the free user has exhausted today's pattern quota. Today's
    /// patterns already played still remain accessible via `canAccess`.
    static func freeQuotaExhausted(playedTodayIds: Set<String>) -> Bool {
        playedTodayIds.count >= SubscriptionManager.freeMaxDailyPatterns
    }
}
