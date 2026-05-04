import UIKit
import UserNotifications

extension Notification.Name {
    /// Posted when a remote push is tapped and contains a target episode_id.
    /// HomeView observes this and asks the player to play that episode.
    static let openEpisodeFromPush = Notification.Name("castlingo.openEpisodeFromPush")
}

/// AppDelegate adapter for remote-push registration.
///
/// SwiftUI's App lifecycle doesn't expose `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`,
/// so we bridge via `UIApplicationDelegateAdaptor` in `LangPodApp`.
///
/// Flow:
/// 1. App launch → `requestPushAuthorization()` (called from LangPodApp once onboarding done)
/// 2. iOS calls `didRegisterForRemoteNotificationsWithDeviceToken` → upload to server
/// 3. Push arrives → routed by `NotificationManager` (the UNUserNotificationCenterDelegate)
class PushService: NSObject, UIApplicationDelegate {
    static let shared = PushService()

    private static let apiBaseURL: String = {
        Bundle.main.object(forInfoDictionaryKey: "CastlingoAPIBaseURL") as? String
            ?? "https://api.myblackhole.pro"
    }()

    /// Last token uploaded — guard against re-uploading on every cold start
    /// when nothing changed (token is stable until the user reinstalls/restores).
    private static let lastUploadedKey = "castlingo.push.lastUploadedSignature"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }

    /// Ask iOS for permission, then register for remote pushes if granted.
    /// Idempotent — safe to call repeatedly (system caches the answer).
    func requestPushAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// If the user already granted permission in a previous session, just
    /// register — no prompt is shown.
    func registerIfAuthorized() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - APNs callbacks

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        uploadToken(token)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("[Push] APNs registration failed: \(error.localizedDescription)")
        #endif
    }

    // MARK: - Server registration

    /// Push the token + current user level to our server. Re-uploads only when
    /// the (token, level, language) tuple changes, so changing reading level in
    /// Profile triggers a fresh upload but no-op cold starts don't spam.
    func uploadToken(_ token: String, level: String? = nil, language: String? = nil) {
        let resolvedLevel = level
            ?? UserDefaults.standard.string(forKey: "selectedLevel")
            ?? "easy"
        let resolvedLanguage = language
            ?? Locale.current.language.languageCode?.identifier
            ?? "zh"

        #if DEBUG
        let envTag = "sandbox"
        #else
        let envTag = "prod"
        #endif
        let signature = "\(token)|\(resolvedLevel)|\(resolvedLanguage)|\(envTag)"
        if UserDefaults.standard.string(forKey: Self.lastUploadedKey) == signature {
            return
        }

        guard let url = URL(string: "\(Self.apiBaseURL)/castlingo/devices/register") else { return }

        // Debug builds embed the development APS entitlement → device token is
        // for APNs sandbox. Production builds (Archive / TestFlight / App Store)
        // get the production entitlement → token is for APNs production. The
        // server uses this flag to pick the right endpoint per-device, so dev
        // and prod users can coexist on the same tokens.json.
        #if DEBUG
        let isSandbox = true
        #else
        let isSandbox = false
        #endif

        let body: [String: Any] = [
            "token": token,
            "level": resolvedLevel,
            "language": resolvedLanguage,
            "bundle_id": Bundle.main.bundleIdentifier ?? "com.amyhuang.castlingo",
            "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "platform": "ios",
            "is_sandbox": isSandbox
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 10

        URLSession.shared.dataTask(with: req) { _, response, error in
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                UserDefaults.standard.set(signature, forKey: Self.lastUploadedKey)
                #if DEBUG
                print("[Push] Token uploaded (level=\(resolvedLevel))")
                #endif
            } else {
                #if DEBUG
                print("[Push] Token upload failed: \(error?.localizedDescription ?? "non-2xx")")
                #endif
            }
        }.resume()
    }

    /// Re-upload using the last-known token but a fresh level. Called when the
    /// user changes reading level in Profile so server-side filtering stays
    /// accurate without waiting for the next cold start.
    func reuploadForLevelChange(newLevel: String) {
        // Force the signature to mismatch so the next system-supplied token will
        // upload. Safer than caching the raw token in UserDefaults.
        UserDefaults.standard.removeObject(forKey: Self.lastUploadedKey)
        UIApplication.shared.registerForRemoteNotifications()
        _ = newLevel  // unused — registerForRemoteNotifications triggers callback with current token
    }
}
