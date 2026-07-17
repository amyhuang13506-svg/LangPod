import Foundation

#if canImport(UMCommon)
import UMCommon
// MobClick (event tracking) ships inside UMCommon in v7.5+.
// No separate UMAnalytics module exists — don't try to import it.
#endif

/// Umeng-backed analytics wrapper. Also logs to console in DEBUG so the funnel
/// is visible during development even before the SDK is linked.
///
/// Setup (one-time, outside this file):
///   1. Register at developer.umeng.com → create iOS app → copy AppKey
///   2. Paste AppKey into Info.plist under key `UMAppKey`
///   3. Xcode → Package Dependencies → add:
///        https://github.com/umeng/umeng-common-swift-package
///        https://github.com/umeng/umeng-analytics-swift-package
///   4. Rebuild. The `canImport` gates light up automatically.
enum Analytics {

    // MARK: - Events

    enum Event: String {
        case appLaunch = "app_launch"
        case onboardingComplete = "onboarding_complete"
        case episodePlayStart = "episode_play_start"
        case listen30s = "listen_30s"
        case episodeRound1Complete = "episode_round1_complete"
        case episodeAbandon = "episode_abandon"
        case episodeComplete = "episode_complete"
        case firstEpisodeComplete = "first_episode_complete"
        case rawPlayStart = "raw_play_start"
        case rawListen30s = "raw_listen_30s"
        case rawListenEnd = "raw_listen_end"
        case vocabularySave = "vocabulary_save"
        case wordMatchComplete = "word_match_complete"
        case feynmanComplete = "feynman_complete"
        case paywallView = "paywall_view"
        case trialStart = "trial_start"
        case purchaseAttempt = "purchase_attempt"
        case purchaseSuccess = "purchase_success"
        case purchaseFail = "purchase_fail"
        case shareCard = "share_card"
        case pushOpened = "push_opened"
        case patternOpen = "pattern_open"
        case patternListenComplete = "pattern_listen_complete"
        case patternPaywallView = "pattern_paywall_view"
        case lessonOpen = "lesson_open"
        case lessonWordAdd = "lesson_word_add"
        case lessonAddAll = "lesson_add_all"
        case lessonPaywallView = "lesson_paywall_view"
        case lessonCountrySwitch = "lesson_country_switch"
        case vocabSectionSwitch = "vocab_section_switch"
        case themeLessonOpen = "theme_lesson_open"
        case themeCategoryFilter = "theme_category_filter"
        case sentenceSave = "sentence_save"
        case sentencePracticeComplete = "sentence_practice_complete"
        case sentenceQuizComplete = "sentence_quiz_complete"
        case dailyTaskPopupView = "daily_task_popup_view"
        case dailyTaskPopupDismiss = "daily_task_popup_dismiss"
        case dailyTaskComplete = "daily_task_complete"
        case dailyTaskAllComplete = "daily_task_all_complete"
        case dailyTaskEntryTap = "daily_task_entry_tap"
    }

    // MARK: - Setup

    static func setup() {
        #if canImport(UMCommon)
        guard let key = Bundle.main.object(forInfoDictionaryKey: "UMAppKey") as? String,
              !key.isEmpty,
              key != "YOUR_UMENG_APP_KEY"
        else {
            #if DEBUG
            print("⚠️ Umeng: UMAppKey not set in Info.plist — running in console-only mode")
            #endif
            return
        }

        let channel: String
        #if DEBUG
        channel = "Dev"
        UMConfigure.setLogEnabled(true)
        #else
        channel = "AppStore"
        UMConfigure.setLogEnabled(false)
        #endif

        UMConfigure.initWithAppkey(key, channel: channel)
        #endif
    }

    // MARK: - Tracking

    static func track(_ event: Event, params: [String: String] = [:]) {
        #if DEBUG
        let paramStr = params.isEmpty ? "" : " " + params.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print("📊 \(event.rawValue)\(paramStr)")
        #endif

        #if canImport(UMCommon)
        if params.isEmpty {
            MobClick.event(event.rawValue)
        } else {
            MobClick.event(event.rawValue, attributes: params)
        }
        #endif

        // 镜像到 Adjust（FB 投放归因用；只有 AdjustTracker.eventTokens 配了 token 的事件才上报）
        AdjustTracker.mirror(event, params: params)
    }

    /// Attach a stable user identifier so Umeng can thread events together
    /// across installs (useful once we have accounts; no-op for now).
    static func setUserID(_ id: String) {
        #if canImport(UMCommon)
        MobClick.profileSignIn(withPUID: id)
        #endif
    }
}
