import Foundation
import UserNotifications

extension Notification.Name {
    /// Posted when the user saves a new reminder time in ProfileView.
    /// LangPodApp listens and triggers `refreshDailyNotification()`.
    static let reminderTimeChanged = Notification.Name("castlingo.reminderTimeChanged")
}

/// Snapshot of the data the arbiter needs to pick the right push. Built fresh
/// at every refresh so scheduled content reflects current state.
struct NotificationContext {
    let streakDays: Int
    let lastListenDate: Date?
    let listenedToday: Bool
    let newestEpisodeTitle: String?
    let hasNewEpisodeToday: Bool
    let forgottenWordsCount: Int       // matchCorrect < 3 AND lastPractice > 30 days
    let recentEncounteredWords: [String] // saved words that reappeared within 2 days
    let reminderHour: Int
    let reminderMinute: Int
}

@Observable
class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    var isAuthorized = false

    /// Single stable identifier — rescheduling replaces the previous pending one.
    private let dailyID = "castlingo.daily"

    override init() {
        super.init()
        checkAuthorization()
        // Receive taps on notifications (both while app is backgrounded and
        // when the notification launches the app cold).
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// User tapped the notification → log the funnel event with the intent type,
    /// so the Umeng dashboard can tell us which copy converts best.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let intent = response.notification.request.content.userInfo["intent"] as? String ?? "unknown"
        Analytics.track(.pushOpened, params: ["intent": intent])
        completionHandler()
    }

    /// If the app is in foreground when the scheduled time hits, still show the
    /// banner (by default iOS suppresses it). Minor UX win, zero funnel impact.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Permission

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
            }
        }
    }

    private func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Priority Arbitration

    /// Re-schedule the one daily notification. Cancels any previous pending ones
    /// first so the user always gets at most ONE per day — the most relevant
    /// message given current state. Call at app start, return to foreground,
    /// background, episode complete, and vocabulary change.
    func refreshDailyNotification(context c: NotificationContext) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyID])

        guard isAuthorized else { return }
        guard let intent = pickIntent(context: c) else { return }

        let content = UNMutableNotificationContent()
        content.title = intent.title
        content.body = intent.body
        content.sound = .default
        content.userInfo = ["intent": intent.type]

        var components = DateComponents()
        components.hour = c.reminderHour
        components.minute = c.reminderMinute

        // Non-repeating: we re-schedule on every app session, so each scheduling
        // reflects the freshest state. A `repeats: true` trigger would fire stale
        // content if the user's situation changes between runs.
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: dailyID,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    /// Cancel everything (used on permission revoke / debug reset).
    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Intent Picker

    private struct Intent {
        let type: String
        let title: String
        let body: String
    }

    private func pickIntent(context c: NotificationContext) -> Intent? {
        // 1. Streak about to break (≥2 days since last listen, and streak was non-trivial)
        if let last = c.lastListenDate {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: last), to: Calendar.current.startOfDay(for: Date())).day ?? 0
            if days >= 2 && c.streakDays >= 2 {
                return Intent(
                    type: "streak_risk",
                    title: "再不听就要清零了",
                    body: "\(c.streakDays) 天的连续记录就快断了，3 分钟就能续上"
                )
            }
        }

        // 2. Haven't listened today + new episode exists
        if !c.listenedToday, c.hasNewEpisodeToday, let title = c.newestEpisodeTitle {
            return Intent(
                type: "new_episode",
                title: "今天的新集",
                body: title
            )
        }

        // 3. Old words reappeared in recently played content
        if let word = c.recentEncounteredWords.first {
            return Intent(
                type: "encountered_words",
                title: "你的旧词又出现了",
                body: "「\(word)」在新一集里又出现，多听几遍就记住了"
            )
        }

        // 4. Words that are fading (≥3 items stale)
        if c.forgottenWordsCount >= 3 {
            return Intent(
                type: "forgotten_words",
                title: "几个词快忘了",
                body: "有 \(c.forgottenWordsCount) 个词超过 30 天没练，30 秒救回来"
            )
        }

        // 5. Fallback: plain nudge if user hasn't listened today
        if !c.listenedToday {
            return Intent(
                type: "daily_reminder",
                title: "今日的 3 分钟",
                body: "打开 Castlingo，继续你的听力训练"
            )
        }

        // Already listened today and nothing urgent — skip.
        return nil
    }
}
