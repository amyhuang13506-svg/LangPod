import Foundation

/// Unified queue item — episodes and patterns coexist in the same playback queue.
/// AudioPlayer drives 5-round logic for `.episode` and single-pass playback for `.pattern`.
enum PlayItem: Identifiable, Equatable {
    case episode(Episode)
    case pattern(Pattern, parentEpisode: Episode)

    var id: String {
        switch self {
        case .episode(let ep): "ep:\(ep.id)"
        case .pattern(let p, _): "pat:\(p.id)"
        }
    }

    var parentEpisode: Episode {
        switch self {
        case .episode(let ep): ep
        case .pattern(_, let parent): parent
        }
    }

    var displayTitle: String {
        switch self {
        case .episode(let ep): ep.title
        case .pattern(let p, _): p.template
        }
    }

    var isPattern: Bool {
        if case .pattern = self { return true }
        return false
    }

    static func == (lhs: PlayItem, rhs: PlayItem) -> Bool {
        lhs.id == rhs.id
    }
}

extension Array where Element == PlayItem {
    /// Build a play queue from episodes, optionally interleaving each episode's patterns.
    /// Result shape: [ep_A, pat_A1, pat_A2, ep_B, pat_B1, pat_B2, ...]
    /// When `includePatterns: false`, returns a pure episode queue.
    static func build(from episodes: [Episode], includePatterns: Bool) -> [PlayItem] {
        var queue: [PlayItem] = []
        for ep in episodes {
            queue.append(.episode(ep))
            if includePatterns, let patterns = ep.patterns {
                for p in patterns {
                    queue.append(.pattern(p, parentEpisode: ep))
                }
            }
        }
        return queue
    }
}
