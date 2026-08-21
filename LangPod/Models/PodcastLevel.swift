import Foundation

enum PodcastLevel: String, CaseIterable, Codable {
    case easy
    case medium
    case hard

    var displayName: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        }
    }

    var icon: String {
        switch self {
        case .easy: "🟢"
        case .medium: "🔵"
        case .hard: "🟣"
        }
    }

    var description: String {
        switch self {
        case .easy: String(localized: "1000词以内 · 慢速 · 3-5分钟")
        case .medium: String(localized: "3000词以内 · 中速 · 5-8分钟")
        case .hard: String(localized: "无限制 · 自然语速 · 8-12分钟")
        }
    }

    var tabName: String {
        switch self {
        case .easy: String(localized: "初级")
        case .medium: String(localized: "中级")
        case .hard: String(localized: "高级")
        }
    }
}
