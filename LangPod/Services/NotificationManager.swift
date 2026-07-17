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

    // 晚间 20:00 内容推送（句型 / 单词按天交替）的数据源。缺内容时该类不发、回退另一类。
    let todayPatternTemplate: String?   // 今日第一个句型的模板文字
    let todayPatternTranslationZh: String?
    let todayPatternScene: String?
    let todayLessonTitle: String?       // 今日新场景课标题（titleZh）
    let todayLessonCountryZh: String?
    let todayLessonFlag: String?
    let todayLessonWordCount: Int?
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

        // 晚间内容推送（今日句型 / 今日单词）：deeplink 携带 DailyTaskType.rawValue，
        // 复用 ContentView 已有的任务深链管道（listen_pattern 播今日句型 / learn_lesson 开今日场景课）。
        if let deeplink = userInfo["deeplink"] as? String, !deeplink.isEmpty {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .dailyTaskDeepLink,
                    object: nil,
                    userInfo: ["type": deeplink]
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
        // 截图/调试用：simctl launch 传 -debug_screenshot_mode YES 跳过授权弹框
        if UserDefaults.standard.bool(forKey: "debug_screenshot_mode") { return }
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
        var info: [String: Any] = ["intent": intent.type]
        if let dl = intent.deeplink { info["deeplink"] = dl }
        content.userInfo = info

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
        var deeplink: String? = nil   // DailyTaskType.rawValue，点击时深链到对应页面
        var fireTomorrow = false       // true = 排到明天 reminderHour（streak_risk 预排 / 内容跨天场景）
    }

    /// 晚间 20:00 单条推送的仲裁：
    ///   1. streak 快断 → 救火（最高优先，保留原逻辑）
    ///   2. 否则按日期奇偶交替：单数日今日句型 / 双数日今日单词场景课（缺内容回退另一类）
    ///   3. 都没有 → 朴素提醒
    /// 内容新鲜度：排「今天」嵌真实标题；排「明天」（当天 reminder 时间已过）用常青文案，
    /// 因为设备还不知道明天凌晨 cron 产的新内容。点击深链在点击那一刻实时解析最新内容。
    private func pickIntent(context c: NotificationContext) -> Intent? {
        let firesTomorrow = reminderPassedToday(hour: c.reminderHour, minute: c.reminderMinute)
        let targetDate = firesTomorrow
            ? (Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
            : Date()

        // 1. Streak about to break — 最高优先（留存）。
        if firesTomorrow {
            // 「今天听了、明天没开 app」是最该救的场景：排程只在 app 活跃时发生，
            // 所以趁现在把明天 20:00 的 streak_risk 排上（fire 时 days 恰为 1）。
            if c.listenedToday && c.streakDays >= 1 {
                return streakIntent(streakDays: c.streakDays, fireTomorrow: true)
            }
        } else if let last = c.lastListenDate {
            // days == 1 才是「今晚不听就断」的准确时点（DataStore 断连即置 1）。
            let days = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: last),
                to: Calendar.current.startOfDay(for: Date())
            ).day ?? 0
            if days == 1 && c.streakDays >= 2 {
                return streakIntent(streakDays: c.streakDays, fireTomorrow: false)
            }
        }

        // 2. 内容推送：句型 / 单词按天自动交替（无需用户选择，默认常驻）。
        //    奇偶交替：用 era 内的绝对天序号，跨月/跨年边界也严格交替。
        let dayNumber = Calendar.current.ordinality(of: .day, in: .era, for: targetDate) ?? 0
        let preferPattern = dayNumber % 2 == 1

        let pattern = patternIntent(c, evergreen: firesTomorrow)
        let word = wordIntent(c, evergreen: firesTomorrow)
        let ordered = preferPattern ? [pattern, word] : [word, pattern]
        for candidate in ordered {
            if var intent = candidate {
                intent.fireTomorrow = firesTomorrow
                return intent
            }
        }

        // 3. 兜底：还没听 → 朴素提醒。
        if !c.listenedToday {
            return Intent(
                type: "daily_reminder",
                title: "今日的 3 分钟",
                body: "打开 Castlingo，继续你的听力训练",
                fireTomorrow: firesTomorrow
            )
        }

        return nil
    }

    private func streakIntent(streakDays: Int, fireTomorrow: Bool) -> Intent {
        Intent(
            type: "streak_risk",
            title: "再不听就要清零了",
            body: "\(streakDays) 天的连续记录就快断了，3 分钟就能续上",
            fireTomorrow: fireTomorrow
        )
    }

    /// 今日句型 intent。evergreen=true（排明天）时用常青文案；否则需有今日句型才返回。
    private func patternIntent(_ c: NotificationContext, evergreen: Bool) -> Intent? {
        if evergreen {
            return Intent(
                type: "daily_pattern",
                title: "今日句型讲解已更新",
                body: "跟读三遍，把一个地道句型变成条件反射",
                deeplink: DailyTaskType.listenPattern.rawValue
            )
        }
        guard let template = c.todayPatternTemplate else { return nil }
        let scene = c.todayPatternScene ?? ""
        let body: String = {
            guard let zh = c.todayPatternTranslationZh, !zh.isEmpty else {
                return "点开学一个地道句型"
            }
            return scene.isEmpty ? zh : "\(zh)｜\(scene)"
        }()
        return Intent(
            type: "daily_pattern",
            title: "今日句型 · \(template)",
            body: body,
            deeplink: DailyTaskType.listenPattern.rawValue
        )
    }

    /// 今日单词（新场景课）intent。evergreen=true（排明天）时用常青文案。
    private func wordIntent(_ c: NotificationContext, evergreen: Bool) -> Intent? {
        if evergreen {
            return Intent(
                type: "daily_word",
                title: "今日新场景已上线",
                body: "几个地道说法 + 真实场景，3 分钟学会",
                deeplink: DailyTaskType.learnLesson.rawValue
            )
        }
        guard let title = c.todayLessonTitle else { return nil }
        let flag = c.todayLessonFlag ?? ""
        let country = c.todayLessonCountryZh ?? ""
        let body: String = {
            if let wc = c.todayLessonWordCount {
                return "\(flag)\(country)｜\(wc) 个地道说法，3 分钟学会"
            }
            return "\(flag)\(country) 场景对话，学几个地道说法"
        }()
        return Intent(
            type: "daily_word",
            title: "今日新场景 · \(title)",
            body: body,
            deeplink: DailyTaskType.learnLesson.rawValue
        )
    }

    /// 当前时刻是否已过今天的 reminder 时间（是 → 下一次 fire 落在明天）。
    private func reminderPassedToday(hour: Int, minute: Int) -> Bool {
        let now = Date()
        guard let fire = Calendar.current.date(
            bySettingHour: hour, minute: minute, second: 0, of: now
        ) else { return false }
        return now >= fire
    }
}
