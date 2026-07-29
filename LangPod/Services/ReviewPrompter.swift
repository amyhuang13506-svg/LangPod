import Foundation

/// App Store 评分请求的节流闸门。
/// 系统弹窗由 Apple 控制（每用户 365 天最多 3 次，且可能被系统抑制），
/// 这里只负责把请求时机控制在"值得花配额"的点上。
enum ReviewPrompter {
    static let appStoreID = "6762072277"

    private static let lastAskKey = "reviewPromptLastAskDate"
    private static let minEpisodesCompleted = 3
    private static let cooldownDays = 60

    /// 完播进入完成页时调用：第 3 次完播起、每 60 天最多请求一次
    static func shouldAsk(episodesCompleted: Int) -> Bool {
        guard episodesCompleted >= minEpisodesCompleted else { return false }
        if let last = UserDefaults.standard.object(forKey: lastAskKey) as? Date {
            let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            guard days >= cooldownDays else { return false }
        }
        return true
    }

    static func recordAsked() {
        UserDefaults.standard.set(Date(), forKey: lastAskKey)
        Analytics.track(.reviewPromptRequest)
    }

    /// App Store 写评论页（不受系统抑制，100% 打开）
    static var writeReviewURL: URL? {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }
}
