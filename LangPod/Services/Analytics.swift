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
        case episodeComplete = "episode_complete"
        case vocabularySave = "vocabulary_save"
        case wordMatchComplete = "word_match_complete"
        case feynmanComplete = "feynman_complete"
        case paywallView = "paywall_view"
        case purchaseAttempt = "purchase_attempt"
        case purchaseSuccess = "purchase_success"
        case purchaseFail = "purchase_fail"
        case shareCard = "share_card"
        case pushOpened = "push_opened"
        case patternOpen = "pattern_open"
        case patternListenComplete = "pattern_listen_complete"
        case patternPaywallView = "pattern_paywall_view"
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
    }

    /// Attach a stable user identifier so Umeng can thread events together
    /// across installs (useful once we have accounts; no-op for now).
    static func setUserID(_ id: String) {
        #if canImport(UMCommon)
        MobClick.profileSignIn(withPUID: id)
        #endif
    }
}
