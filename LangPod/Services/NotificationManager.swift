import Foundation
import UserNotifications

@Observable
class NotificationManager {
    var isAuthorized = false

    init() {
        checkAuthorization()
    }

    // MARK: - Permission

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                self.isAuthorized = granted
            }
        }
    }

    private func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Schedule Encounter Notification

    /// Schedule a local notification about encountered words for tomorrow
    func scheduleEncounterReminder(words: [String]) {
        guard isAuthorized, !words.isEmpty else { return }

        // Rate limit: max 1 notification per day
        let lastKey = "lastEncounterNotificationDate"
        if let lastDate = UserDefaults.standard.object(forKey: lastKey) as? Date,
           Calendar.current.isDateInToday(lastDate) {
            return
        }
        UserDefaults.standard.set(Date(), forKey: lastKey)

        let content = UNMutableNotificationContent()
        if words.count == 1 {
            content.title = "你的旧词又出现了"
            content.body = "'\(words[0])' 在新一集里又出现了，你不知不觉已经记住它了！"
        } else {
            let wordList = words.prefix(3).joined(separator: "、")
            content.title = "你的旧词又出现了"
            content.body = "\(wordList) 在新内容里再次出现，继续听就能记住！"
        }
        content.sound = .default

        // Schedule for tomorrow morning 9:00
        var dateComponents = DateComponents()
        dateComponents.hour = 9
        dateComponents.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        let request = UNNotificationRequest(
            identifier: "encounter-\(UUID().uuidString.prefix(8))",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }
}
