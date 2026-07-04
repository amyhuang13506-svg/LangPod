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
    let tasksCompletedToday: Int       // 每日任务已完成格数（TaskEngine）
    let tasksTotalToday: Int           // 每日任务总格数（3-4）
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
    /// Also: if the payload carries an `episode_id` (remote push from new-content
    /// pipeline), broadcast it so HomeView can deep-link into that episode.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let intent = userInfo["intent"] as? String ?? "unknown"
        Analytics.track(.pushOpened, params: ["intent": intent])

        if let episodeId = userInfo["episode_id"] as? String, !episodeId.isEmpty {
            let level = userInfo["level"] as? String
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .openEpisodeFromPush,
                    object: nil,
                    userInfo: [
                        "episode_id": episodeId,
                        "level": level ?? ""
                    ]
                )
            }
        }
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
        if intent.fireTomorrow,
           let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) {
            // 预排「明天」的推送（streak_risk 救火场景）：带完整年月日，
            // 只给 hour/minute 会匹配「下一次出现」，可能是今天。
            let d = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
            components.year = d.year
            components.month = d.month
            components.day = d.day
        }
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
        var fireTomorrow = false   // true = 排到明天 reminderHour（streak_risk 预排场景）
    }

    private func pickIntent(context c: NotificationContext) -> Intent? {
        // 1. Streak about to break — days == 1 才是「今晚不听就断」的准确时点。
        //    旧条件 days >= 2 有 bug：火苗隔 1 天就重置（DataStore 断连置 1），发出时火苗已死。
        if let last = c.lastListenDate {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: last), to: Calendar.current.startOfDay(for: Date())).day ?? 0
            if days == 1 && c.streakDays >= 2 {
                return Intent(
                    type: "streak_risk",
                    title: "再不听就要清零了",
                    body: "\(c.streakDays) 天的连续记录就快断了，3 分钟就能续上"
                )
            }
        }

        // 2. 今日任务只差 1 个（进 push_opened 的 intent 漏斗，无需改埋点）
        if c.tasksTotalToday > 0 && c.tasksCompletedToday == c.tasksTotalToday - 1 {
            return Intent(
                type: "task_almost_done",
                title: "今日任务只差 1 个",
                body: "已完成 \(c.tasksCompletedToday)/\(c.tasksTotalToday)，再做 1 个点亮完美一天"
            )
        }

        // 3. Haven't listened today + new episode exists
        if !c.listenedToday, c.hasNewEpisodeToday, let title = c.newestEpisodeTitle {
            return Intent(
                type: "new_episode",
                title: "今天的新集",
                body: title
            )
        }

        // 4. Old words reappeared in recently played content
        if let word = c.recentEncounteredWords.first {
            return Intent(
                type: "encountered_words",
                title: "你的旧词又出现了",
                body: "「\(word)」在新一集里又出现，多听几遍就记住了"
            )
        }

        // 5. Words that are fading (≥3 items stale)
        if c.forgottenWordsCount >= 3 {
            return Intent(
                type: "forgotten_words",
                title: "几个词快忘了",
                body: "有 \(c.forgottenWordsCount) 个词超过 30 天没练，30 秒救回来"
            )
        }

        // 6. Fallback: plain nudge if user hasn't listened today
        if !c.listenedToday {
            return Intent(
                type: "daily_reminder",
                title: "今日的 3 分钟",
                body: "打开 Castlingo，继续你的听力训练"
            )
        }

        // 7. 今天听过、火苗存活 → 预排「明天」的 streak_risk。
        //    「昨天听了今天没开 app」是最该救的场景，但排程只在 app 活跃时发生——
        //    所以趁现在把明天的排上（fire 时 days 恰为 1）。明天若打开 app 会被重排覆盖。
        if c.listenedToday && c.streakDays >= 1 {
            return Intent(
                type: "streak_risk",
                title: "再不听就要清零了",
                body: "\(c.streakDays) 天的连续记录就快断了，3 分钟就能续上",
                fireTomorrow: true
            )
        }

        return nil
    }
}
