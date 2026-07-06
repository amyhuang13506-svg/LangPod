import UIKit
import AppTrackingTransparency

#if canImport(AdjustSdk)
import AdjustSdk
#endif

/// Adjust 归因封装（Facebook Ads 投放用）。接法照搬某派（MouPai）：
///   1. PushService.didFinishLaunching 里 `AdjustTracker.initialize()` —— 开 first-session-delay，
///      首包（安装归因）暂扣，等 ATT 决策后放行，保证审核看到"授权在前、采集在后"。
///   2. 主界面出现后调 `requestATTIfNeeded()` —— 弹 ATT 授权框；无论同意/拒绝都
///      `endFirstSessionDelay()` 放行首包（拒绝则回退 SKAdNetwork 归因，精度降一档但可用）。
///   3. `Analytics.track` 自动镜像到这里，只有在 `eventTokens` 里配了 token 的事件才上报 Adjust。
///
/// 后台：dash.adjust.com → Castlingo (yjnimmmpcjr4)。
/// DEBUG 走 sandbox（后台 Testing Console 可见），Release 走 production。
enum AdjustTracker {

    static let appToken = "yjnimmmpcjr4"

    /// Adjust 事件 Token —— 在 Adjust 后台（Castlingo）逐个建这 5 个事件后把 6 位 token 填进来。
    /// 没填（空字符串）的事件 = 只打友盟，不上报 Adjust，不会崩。
    ///
    /// 投放阶段切换优化目标：起量期 onboarding_complete → 提质期 trial_start → ROAS 期 purchase。
    private static let eventTokens: [Analytics.Event: String] = [
        .onboardingComplete:   "syr47n",   // 起量期优化目标（浅漏斗，量最大）→ FB CompleteRegistration
        .firstEpisodeComplete: "pkfpqp",   // 真·Aha，CPI 质量分层（幂等，首次完播）
        .paywallView:          "j6vl3g",   // 付费意向前兆 → FB InitiateCheckout
        .trialStart:           "p8bw19",   // 提质期主优化目标（强付费意向）→ FB StartTrial
        .purchaseSuccess:      "js1zzh",   // ROAS 期：订阅扣费，走 trackRevenue 带金额 → FB Subscribe
    ]

    private static var isTrackingGateResolved = false
    private static var isATTRequestInFlight = false
    private static var pendingEvents: [(event: Analytics.Event, params: [String: String])] = []

    // MARK: - 初始化（PushService.didFinishLaunching）

    static func initialize() {
        #if canImport(AdjustSdk)
        let environment: String = {
            #if DEBUG
            return ADJEnvironmentSandbox
            #else
            return ADJEnvironmentProduction
            #endif
        }()
        guard let config = ADJConfig(appToken: appToken, environment: environment) else { return }
        #if DEBUG
        config.logLevel = ADJLogLevel.verbose
        #else
        config.logLevel = ADJLogLevel.warn
        #endif
        // 首包暂扣，等 ATT 决策（requestATTIfNeeded → resolveTrackingGate）再放行
        config.enableFirstSessionDelay()
        Adjust.initSdk(config)
        #endif
    }

    // MARK: - ATT（App Tracking Transparency）

    /// 主界面出现后调用。已决策过（同意/拒绝）则直接放行首包，不再弹框。
    /// 必须在 App .active 状态下请求，否则 iOS 会静默回 .denied。
    static func requestATTIfNeeded() {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            resolveTrackingGate()
            return
        }
        guard UIApplication.shared.applicationState == .active else { return }
        guard !isATTRequestInFlight else { return }
        isATTRequestInFlight = true
        ATTrackingManager.requestTrackingAuthorization { status in
            DispatchQueue.main.async {
                isATTRequestInFlight = false
                resolveTrackingGate()
                #if DEBUG
                print("📊 [Adjust] ATT 状态：\(status.rawValue) (0=notDetermined 1=restricted 2=denied 3=authorized)")
                #endif
            }
        }
    }

    private static func resolveTrackingGate() {
        #if canImport(AdjustSdk)
        Adjust.endFirstSessionDelay()
        #endif
        guard !isTrackingGateResolved else { return }
        isTrackingGateResolved = true
        let events = pendingEvents
        pendingEvents.removeAll()
        for item in events {
            send(item.event, params: item.params)
        }
    }

    // MARK: - 事件镜像（由 Analytics.track 调用）

    static func mirror(_ event: Analytics.Event, params: [String: String]) {
        // 订阅成功走 trackRevenue（带金额）专用上报，这里跳过避免同一 token 重复计数
        guard event != .purchaseSuccess else { return }
        // 没配 token 的事件直接丢弃，连队列都不进
        guard let token = eventTokens[event], !token.isEmpty else { return }
        guard isTrackingGateResolved else {
            pendingEvents.append((event, params))
            return
        }
        send(event, params: params)
    }

    private static func send(_ event: Analytics.Event, params: [String: String]) {
        #if canImport(AdjustSdk)
        guard let token = eventTokens[event], !token.isEmpty,
              let adjEvent = ADJEvent(eventToken: token) else { return }
        for (k, v) in params {
            adjEvent.addCallbackParameter(k, value: v)
        }
        Adjust.trackEvent(adjEvent)
        #endif
    }

    /// 订阅成功专用：带 value + currency 上报收入，Adjust → FB 回传后才能按 ROAS 出价。
    static func trackRevenue(_ event: Analytics.Event, amount: Double, currency: String) {
        #if canImport(AdjustSdk)
        guard let token = eventTokens[event], !token.isEmpty,
              let adjEvent = ADJEvent(eventToken: token) else { return }
        adjEvent.setRevenue(amount, currency: currency)
        Adjust.trackEvent(adjEvent)
        #endif
    }
}
