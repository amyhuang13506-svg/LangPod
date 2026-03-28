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
        case .medium: "🟡"
        case .hard: "🔴"
        }
    }

    var description: String {
        switch self {
        case .easy: "1000词以内 · 慢速 · 3-5分钟"
        case .medium: "3000词以内 · 中速 · 5-8分钟"
        case .hard: "无限制 · 自然语速 · 8-12分钟"
        }
    }

    var tabName: String {
        switch self {
        case .easy: "初级"
        case .medium: "中级"
        case .hard: "高级"
        }
    }
}
