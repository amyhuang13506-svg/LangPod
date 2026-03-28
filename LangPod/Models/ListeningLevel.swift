import Foundation

enum ListeningLevel: Int, Codable, CaseIterable {
    case lv1 = 1
    case lv2 = 2
    case lv3 = 3
    case lv4 = 4
    case lv5 = 5

    var name: String {
        switch self {
        case .lv1: "新手听众"
        case .lv2: "入门听众"
        case .lv3: "进阶听众"
        case .lv4: "流利听众"
        case .lv5: "母语级"
        }
    }

    var requiredEpisodes: Int {
        switch self {
        case .lv1: 0
        case .lv2: 5
        case .lv3: 15
        case .lv4: 30
        case .lv5: 60
        }
    }

    var requiredWords: Int {
        switch self {
        case .lv1: 0
        case .lv2: 20
        case .lv3: 60
        case .lv4: 120
        case .lv5: 250
        }
    }

    var unlockedChannels: [PodcastLevel] {
        switch self {
        case .lv1: [.easy]
        case .lv2: [.easy, .medium]
        case .lv3, .lv4, .lv5: PodcastLevel.allCases
        }
    }

    var unlockDescription: String? {
        switch self {
        case .lv1: nil
        case .lv2: "Medium 频道 · 生活和文化话题"
        case .lv3: "Hard 频道 · 新闻和深度话题"
        case .lv4: "双人深度对话系列"
        case .lv5: "\"纯英语解释\"模式"
        }
    }

    var next: ListeningLevel? {
        ListeningLevel(rawValue: rawValue + 1)
    }

    /// Episodes needed to reach next level
    func episodesUntilNext(current: Int) -> Int? {
        guard let next else { return nil }
        return max(0, next.requiredEpisodes - current)
    }

    /// Check if eligible for upgrade
    static func checkLevel(episodes: Int, words: Int) -> ListeningLevel {
        for level in allCases.reversed() {
            if episodes >= level.requiredEpisodes && words >= level.requiredWords {
                return level
            }
        }
        return .lv1
    }
}
