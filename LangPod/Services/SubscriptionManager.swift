import StoreKit
import SwiftUI
#if canImport(RevenueCat)
import RevenueCat
#endif

/// Trial availability for a given product — derived from the store's
/// introductory offer config + per-user eligibility check.
/// Shared by both the StoreKit and RevenueCat backends (always compiled).
struct TrialInfo: Equatable {
    let productID: String
    /// e.g. "7 天", "1 个月"
    let durationDisplay: String
    /// Numeric days (used to render "第 X 天" in the timeline)
    let durationDays: Int
    let isEligible: Bool
}

/// RevenueCat SDK configuration. Plain strings, always compiled (no SDK needed).
enum RevenueCatConfig {
    /// Castlingo's RevenueCat **public SDK key** for the App Store app.
    /// Starts with `appl_`. Get it from RevenueCat → Project → API Keys →
    /// the App Store app's public key.
    ///
    /// TODO: paste the real `appl_...` key here. Until then, RevenueCat is
    /// left unconfigured and the paywall reports "未配置" instead of crashing.
    static let apiKey = "appl_iaEuHxxagtwCjPrKmfwKOKoQGby"

    /// RevenueCat entitlement identifier that grants Pro. Must match the
    /// entitlement created in the RevenueCat dashboard.
    static let entitlementID = "pro"

    /// True once a real key has been pasted — gates `Purchases.configure`.
    static var isReady: Bool {
        apiKey.hasPrefix("appl_") && !apiKey.contains("REPLACE")
    }
}

#if canImport(RevenueCat)

// ============================================================================
// MARK: - RevenueCat backend
// Active when the RevenueCat SPM package is present. Wraps RevenueCat while
// keeping the exact same public surface as the StoreKit version below, so no
// call site (PaywallView + 45 others) needs to change.
// ============================================================================

@Observable
class SubscriptionManager {
    // MARK: - State

    var isPro: Bool = false
    var isPurchasing = false

    /// Last user-visible error from purchase flow. nil when no error / after dismiss.
    var lastPurchaseError: String?

    /// 上一次购买失败的机器可读原因，用于埋点区分「商品没加载出来」和「用户主动取消」。
    /// nil = 上一次没失败（或失败后已消费）。
    var lastFailureReason: String?

    // Trial info fetched from offerings (nil = no intro offer OR user not eligible)
    var yearlyTrialInfo: TrialInfo?
    var monthlyTrialInfo: TrialInfo?

    /// 周付介绍性优惠价展示串（如 "¥0.99"）。nil = 无优惠或商店未加载。
    var weeklyIntroPriceDisplay: String?

    /// DEBUG 预览：launch 参数 -mockWeeklyIntro YES 可在商店未配置优惠时看完整版式
    var effectiveWeeklyIntro: String? {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "mockWeeklyIntro") { return "¥0.99" }
        #endif
        return weeklyIntroPriceDisplay
    }

    /// 周付商品是否可购买（SKU 未创建/未过审时付费墙隐藏周付行）
    var weeklyAvailable: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "mockWeeklyIntro") { return true }
        #endif
        return storeProduct(for: Self.weeklyID) != nil
    }

    /// Raw debug snapshot for the DEBUG overlay on PaywallView. Diagnostic only.
    var trialDebugLines: [String] = []

    // Mock toggles for development (DEBUG only — see isProUser gate).
    var mockProEnabled: Bool {
        didSet { UserDefaults.standard.set(mockProEnabled, forKey: "mockProEnabled") }
    }
    var mockHasTrialEnabled: Bool {
        didSet { UserDefaults.standard.set(mockHasTrialEnabled, forKey: "mockHasTrialEnabled") }
    }

    /// Real subscription OR mock (DEBUG only). The DEBUG gate stops the
    /// UserDefaults-backed `mockProEnabled` from leaking Pro into Release.
    var isProUser: Bool {
        #if DEBUG
        return isPro || mockProEnabled
        #else
        return isPro
        #endif
    }

    var effectiveYearlyTrial: TrialInfo? {
        #if DEBUG
        guard mockHasTrialEnabled else { return nil }
        if let real = yearlyTrialInfo { return real }
        return TrialInfo(productID: Self.yearlyID, durationDisplay: String(localized: "3 天"), durationDays: 3, isEligible: true)
        #else
        return yearlyTrialInfo
        #endif
    }

    var effectiveMonthlyTrial: TrialInfo? {
        // Product policy: monthly never offers a free trial.
        nil
    }

    // MARK: - Localized Price Display

    /// Offering 里的 package —— 走 RevenueCat 服务器（api.revenuecat.com）。
    private var yearlyPackage: Package?
    private var monthlyPackage: Package?
    private var weeklyPackage: Package?

    /// StoreKit 直拉的商品兜底 —— 走 Apple 服务器，与 RC 服务器的死活无关。
    /// 三档都留兜底：RC offerings 超时（国内网络常见）时，付费墙仍能显示真实价格
    /// 并通过 `purchase(product:)` 正常成交。
    private var yearlyProduct: StoreProduct?
    private var monthlyProduct: StoreProduct?
    private var weeklyProduct: StoreProduct?

    /// 某一档当前可用的商品信息：package 优先，StoreKit 直拉兜底。
    private func storeProduct(for productID: String) -> StoreProduct? {
        switch productID {
        case Self.yearlyID:  return yearlyPackage?.storeProduct ?? yearlyProduct
        case Self.monthlyID: return monthlyPackage?.storeProduct ?? monthlyProduct
        case Self.weeklyID:  return weeklyPackage?.storeProduct ?? weeklyProduct
        default:             return nil
        }
    }

    private func package(for productID: String) -> Package? {
        switch productID {
        case Self.yearlyID:  return yearlyPackage
        case Self.monthlyID: return monthlyPackage
        case Self.weeklyID:  return weeklyPackage
        default:             return nil
        }
    }

    /// 三档里至少有一档拿到了真实商品。false = 付费墙显示的是写死兜底价，
    /// 此时点购买必然失败，所以付费墙出现 / App 回前台时要重拉。
    var productsLoaded: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "mockWeeklyIntro") { return true }
        #endif
        return storeProduct(for: Self.weeklyID) != nil
            || storeProduct(for: Self.monthlyID) != nil
            || storeProduct(for: Self.yearlyID) != nil
    }

    var weeklyPriceDisplay: String {
        if let product = storeProduct(for: Self.weeklyID) {
            return Self.formatPriceWithPeriod(product)
        }
        return String(localized: "¥16.8/周")
    }

    var yearlyPriceDisplay: String {
        if let product = storeProduct(for: Self.yearlyID) {
            return Self.formatPriceWithPeriod(product)
        }
        return String(localized: "¥298/年")
    }

    var monthlyPriceDisplay: String {
        if let product = storeProduct(for: Self.monthlyID) {
            return Self.formatPriceWithPeriod(product)
        }
        return String(localized: "¥48/月")
    }

    /// 订阅成功后给 Adjust 回传收入用（ROAS 出价）。商店未加载时回退写死 CNY 定价。
    func priceInfo(for productID: String) -> (value: Double, currency: String) {
        let product: StoreProduct? = storeProduct(for: productID)
        if let product {
            return ((product.price as NSDecimalNumber).doubleValue, product.currencyCode ?? "CNY")
        }
        switch productID {
        case Self.yearlyID: return (298, "CNY")
        case Self.weeklyID: return (16.8, "CNY")
        default:            return (48, "CNY")
        }
    }

    private static func formatPriceWithPeriod(_ product: StoreProduct) -> String {
        guard let period = product.subscriptionPeriod else { return product.localizedPriceString }
        return "\(product.localizedPriceString)/\(periodUnitDisplay(period))"
    }

    private static func periodUnitDisplay(_ period: RevenueCat.SubscriptionPeriod) -> String {
        let value = period.value
        switch period.unit {
        case .day:   return value == 1 ? String(localized: "天") : String(localized: "\(value)天")
        case .week:  return value == 1 ? String(localized: "周") : String(localized: "\(value)周")
        case .month: return value == 1 ? String(localized: "月") : String(localized: "\(value)个月")
        case .year:  return value == 1 ? String(localized: "年") : String(localized: "\(value)年")
        @unknown default: return ""
        }
    }

    // MARK: - Product / Entitlement IDs

    static let yearlyID = "com.amyhuang.castlingo.pro.yearly.v2"
    static let monthlyID = "com.amyhuang.castlingo.pro.monthly.v2"
    static let weeklyID = "com.amyhuang.castlingo.pro.weekly.v1"

    private var customerInfoListener: Task<Void, Never>?
    private var productLoadTask: Task<Void, Never>?
    private var isLoadingProducts = false

    // MARK: - Free Tier Limits

    static let freeMaxDailyEpisodes = 2
    static let freeMaxDailyPatterns = 2
    static let freeMaxVocabPerEpisode = 3
    // Free users: 3 English + 1 Translation = 4 rounds (skip 5th)
    // Pro users: full 5 rounds

    // MARK: - Init

    init() {
        self.mockProEnabled = UserDefaults.standard.bool(forKey: "mockProEnabled")
        #if DEBUG
        let savedMockTrial = UserDefaults.standard.object(forKey: "mockHasTrialEnabled") as? Bool
        self.mockHasTrialEnabled = savedMockTrial ?? true
        #else
        self.mockHasTrialEnabled = false
        #endif
        // All Purchases.shared access is deferred into Tasks, so it runs after
        // LangPodApp.init() has called Purchases.configure() synchronously.
        customerInfoListener = listenForCustomerInfo()
        productLoadTask = startProductLoading()
        Task { await checkStatus() }
    }

    deinit {
        customerInfoListener?.cancel()
        productLoadTask?.cancel()
    }

    // MARK: - RevenueCat

    /// 商品加载。两条链路**必须分开 try**：
    /// - `offerings()` 走 RevenueCat 服务器（api.revenuecat.com）——国内网络下会超时
    /// - `products(_:)` 走 StoreKit（Apple 服务器）——国内是通的
    ///
    /// 这两句原先放在同一个 do 块里：offerings 一抛错，后面的 StoreKit 直拉整段被跳过，
    /// 三档商品全部为 nil，付费墙只能显示写死的兜底价、点购买必报「商品未加载」。
    /// 而首次安装的用户没有 offerings 磁盘缓存，正是最容易踩中的人群。
    @MainActor
    func loadProducts() async {
        guard Purchases.isConfigured else { return }
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        // 1) Offerings（RC 服务器）。失败时保留上一次拿到的 package，不清空。
        do {
            let offerings = try await Purchases.shared.offerings()
            let offering = offerings.current
            yearlyPackage = offering?.annual
                ?? offering?.availablePackages.first { $0.storeProduct.productIdentifier == Self.yearlyID }
                ?? yearlyPackage
            monthlyPackage = offering?.monthly
                ?? offering?.availablePackages.first { $0.storeProduct.productIdentifier == Self.monthlyID }
                ?? monthlyPackage
            weeklyPackage = offering?.weekly
                ?? offering?.availablePackages.first { $0.storeProduct.productIdentifier == Self.weeklyID }
                ?? weeklyPackage
        } catch {
            // RC 不可达（超时 / 后台没配 offering）——下面的 StoreKit 直拉照常进行。
        }

        // 2) StoreKit 直拉补齐 offering 没覆盖的档位。周付本来就不在 default offering 里，
        //    月付/年付则是在 RC 超时的情况下靠这一步兜底，保证付费墙仍可成交。
        let missing = [Self.weeklyID, Self.monthlyID, Self.yearlyID]
            .filter { storeProduct(for: $0) == nil }
        if !missing.isEmpty {
            for product in await Purchases.shared.products(missing) {
                switch product.productIdentifier {
                case Self.yearlyID:  yearlyProduct = product
                case Self.monthlyID: monthlyProduct = product
                case Self.weeklyID:  weeklyProduct = product
                default: break
                }
            }
        }

        await refreshTrialInfo()
    }

    /// 付费墙出现 / App 回前台时调用：商品还没拿到就再拉一次。
    /// 原先只在 init 里拉一次且失败静默，用户整个 session 都买不了。
    @MainActor
    func refreshProductsIfNeeded() async {
        guard !productsLoaded else { return }
        await loadProducts()
    }

    /// 冷启动首拉 + 弱网退避重试。首次安装的用户必须成功连通一次才有缓存，
    /// 一次失败就放弃太脆。
    private func startProductLoading() -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            for delaySeconds in [0, 2, 5, 15] {
                if delaySeconds > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
                }
                guard let self, !Task.isCancelled else { return }
                await self.loadProducts()
                if self.productsLoaded { return }
            }
        }
    }

    /// Reads the yearly package's introductory offer and populates yearlyTrialInfo.
    /// Monthly is deliberately never given a trial (product policy).
    @MainActor
    func refreshTrialInfo() async {
        guard Purchases.isConfigured else { return }
        var yearly: TrialInfo? = nil
        var lines: [String] = []
        lines.append("yearlyPkg=\(yearlyPackage != nil) monthlyPkg=\(monthlyPackage != nil)")

        if let product = yearlyPackage?.storeProduct {
            if let intro = product.introductoryDiscount {
                lines.append("intro.paymentMode=\(intro.paymentMode)")
                lines.append("intro.period=\(intro.subscriptionPeriod.value) \(intro.subscriptionPeriod.unit)")
                if intro.paymentMode == .freeTrial {
                    // NOTE: we surface the trial whenever a free-trial intro offer
                    // exists. Per-user eligibility can be refined later via
                    // Purchases.shared.checkTrialOrIntroDiscountEligibility(...).
                    yearly = TrialInfo(
                        productID: Self.yearlyID,
                        durationDisplay: Self.displayFromPeriod(intro.subscriptionPeriod),
                        durationDays: Self.daysFromPeriod(intro.subscriptionPeriod),
                        isEligible: true
                    )
                    lines.append("  ✅ yearly trial")
                } else {
                    lines.append("  × not .freeTrial")
                }
            } else {
                lines.append("× no introductoryDiscount")
            }
        } else {
            lines.append("× no yearly package")
        }

        // 周付介绍性优惠（付费型，如首周 ¥0.99；免费试用型不算）
        var weeklyIntro: String? = nil
        if let product = weeklyProduct,
           let intro = product.introductoryDiscount,
           intro.paymentMode != .freeTrial {
            weeklyIntro = intro.localizedPriceString
            lines.append("  ✅ weekly intro \(intro.localizedPriceString)")
        }

        lines.append("final: yearly=\(yearly != nil ? "Y" : "nil") weeklyIntro=\(weeklyIntro ?? "nil")")
        yearlyTrialInfo = yearly
        monthlyTrialInfo = nil
        weeklyIntroPriceDisplay = weeklyIntro
        trialDebugLines = lines
        for line in lines { print("🔍 [TrialDebug/RC] \(line)") }
    }

    private static func daysFromPeriod(_ period: RevenueCat.SubscriptionPeriod) -> Int {
        let value = period.value
        switch period.unit {
        case .day:   return value
        case .week:  return value * 7
        case .month: return value * 30
        case .year:  return value * 365
        @unknown default: return 0
        }
    }

    private static func displayFromPeriod(_ period: RevenueCat.SubscriptionPeriod) -> String {
        let value = period.value
        switch period.unit {
        case .day:   return String(localized: "\(value) 天")
        case .week:  return value == 1 ? String(localized: "7 天") : String(localized: "\(value * 7) 天")
        case .month: return String(localized: "\(value) 个月")
        case .year:  return String(localized: "\(value) 年")
        @unknown default: return ""
        }
    }

    @MainActor
    func purchase(_ productID: String) async -> Bool {
        lastFailureReason = nil
        guard Purchases.isConfigured else {
            lastFailureReason = "not_configured"
            lastPurchaseError = String(localized: "暂时无法购买，请稍后重试。")
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        // 商品没加载出来（冷启动时弱网 / RC 超时）：当场重拉一次再买。
        // 转圈已经在转了，用户感知就是「点了要等一下」，而不是直接被甩一句"请稍后重试"。
        if package(for: productID) == nil && storeProduct(for: productID) == nil {
            await loadProducts()
        }

        let package = self.package(for: productID)
        // 无 package（offering 未配 / RC 不可达）时直接按 StoreProduct 购买
        let directProduct: StoreProduct? = package == nil ? storeProduct(for: productID) : nil

        guard package != nil || directProduct != nil else {
            lastFailureReason = "product_not_loaded"
            lastPurchaseError = String(localized: "商品未加载，请稍后重试。")
            return false
        }

        do {
            let result: PurchaseResultData
            if let pkg = package {
                result = try await Purchases.shared.purchase(package: pkg)
            } else {
                result = try await Purchases.shared.purchase(product: directProduct!)
            }
            if result.userCancelled {
                lastFailureReason = "cancelled"
                return false  // user closed the sheet
            }
            let active = result.customerInfo.entitlements[RevenueCatConfig.entitlementID]?.isActive == true
            isPro = active
            if !active {
                lastFailureReason = "no_entitlement"
                lastPurchaseError = String(localized: "购买已完成，但未获得 Pro 权益，请稍后重试或联系客服。")
            }
            return active
        } catch {
            lastFailureReason = "store_error"
            lastPurchaseError = String(localized: "购买失败：\(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    func restore() async {
        guard Purchases.isConfigured else { return }
        do {
            let info = try await Purchases.shared.restorePurchases()
            isPro = info.entitlements[RevenueCatConfig.entitlementID]?.isActive == true
        } catch {
            // Restore failed
        }
    }

    @MainActor
    func checkStatus() async {
        guard Purchases.isConfigured else { return }
        do {
            let info = try await Purchases.shared.customerInfo()
            isPro = info.entitlements[RevenueCatConfig.entitlementID]?.isActive == true
        } catch {
            // Couldn't fetch customer info
        }
    }

    /// Live subscription updates (renewals, expirations, purchases on other
    /// devices) pushed by RevenueCat. Replaces StoreKit's Transaction.updates.
    private func listenForCustomerInfo() -> Task<Void, Never> {
        Task { [weak self] in
            guard Purchases.isConfigured else { return }
            for await info in Purchases.shared.customerInfoStream {
                let active = info.entitlements[RevenueCatConfig.entitlementID]?.isActive == true
                await MainActor.run {
                    self?.isPro = active
                }
            }
        }
    }
}

#else

// ============================================================================
// MARK: - StoreKit 2 backend (fallback)
// Active until the RevenueCat SPM package is added. Original native StoreKit 2
// implementation — keeps the app fully functional before the migration lands.
// ============================================================================

@Observable
class SubscriptionManager {
    // MARK: - State

    var isPro: Bool = false
    var isPurchasing = false
    var products: [Product] = []

    /// Last user-visible error from purchase flow. nil when no error / after dismiss.
    /// PaywallView binds to this to surface silent StoreKit failures as an alert.
    var lastPurchaseError: String?

    /// 上一次购买失败的机器可读原因（埋点用）。与 RC 分支保持一致。
    var lastFailureReason: String?

    // Trial info fetched from products (nil = backend didn't configure OR user not eligible)
    var yearlyTrialInfo: TrialInfo?
    var monthlyTrialInfo: TrialInfo?

    /// 周付介绍性优惠价展示串（SK2 后备实现暂不解析，保持 nil；接口与 RC 分支对齐）
    var weeklyIntroPriceDisplay: String?

    var effectiveWeeklyIntro: String? {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "mockWeeklyIntro") { return "¥0.99" }
        #endif
        return weeklyIntroPriceDisplay
    }

    var weeklyAvailable: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "mockWeeklyIntro") { return true }
        #endif
        return products.contains { $0.id == Self.weeklyID }
    }

    var weeklyPriceDisplay: String {
        if let product = products.first(where: { $0.id == Self.weeklyID }) {
            return Self.formatPriceWithPeriod(product)
        }
        return String(localized: "¥16.8/周")
    }

    /// Raw debug snapshot of what refreshTrialInfo() saw — for DEBUG overlay on PaywallView.
    /// Not used in release logic, purely diagnostic.
    var trialDebugLines: [String] = []

    // Mock toggles for development
    var mockProEnabled: Bool {
        didSet { UserDefaults.standard.set(mockProEnabled, forKey: "mockProEnabled") }
    }
    var mockHasTrialEnabled: Bool {
        didSet { UserDefaults.standard.set(mockHasTrialEnabled, forKey: "mockHasTrialEnabled") }
    }

    // Computed: real subscription OR mock (DEBUG only).
    // CRITICAL: the DEBUG gate here prevents `mockProEnabled` — which lives in
    // UserDefaults — from leaking Pro access into Release builds. Without the
    // gate, any device that had [DEV] Mock Pro toggled on during testing
    // would retain that flag after app updates and get Pro for free.
    var isProUser: Bool {
        #if DEBUG
        return isPro || mockProEnabled
        #else
        return isPro
        #endif
    }

    /// Yearly trial info. In RELEASE: returns real App Store Connect data as-is.
    /// In DEBUG: the `mockHasTrialEnabled` toggle is the single source of truth —
    /// OFF forces the no-trial UI even when ASC has an introductory offer, so you
    /// can visually verify both paywall branches without touching App Store Connect.
    var effectiveYearlyTrial: TrialInfo? {
        #if DEBUG
        guard mockHasTrialEnabled else { return nil }
        if let real = yearlyTrialInfo { return real }
        return TrialInfo(productID: Self.yearlyID, durationDisplay: String(localized: "3 天"), durationDays: 3, isEligible: true)
        #else
        return yearlyTrialInfo
        #endif
    }

    var effectiveMonthlyTrial: TrialInfo? {
        // Product policy: monthly subscription never offers a free trial.
        // Only yearly gets the introductory offer. Even if App Store Connect
        // has a monthly trial configured, we deliberately don't surface it.
        nil
    }

    // MARK: - Localized Price Display

    /// Yearly price with localized currency + period, e.g. "¥298/年" or "$29.99/year".
    /// Falls back to hardcoded CNY when the product isn't loaded (dev mode / no store config).
    var yearlyPriceDisplay: String {
        if let product = products.first(where: { $0.id == Self.yearlyID }) {
            return Self.formatPriceWithPeriod(product)
        }
        return String(localized: "¥298/年")
    }

    /// Monthly price with localized currency + period.
    var monthlyPriceDisplay: String {
        if let product = products.first(where: { $0.id == Self.monthlyID }) {
            return Self.formatPriceWithPeriod(product)
        }
        return String(localized: "¥48/月")
    }

    /// 订阅成功后给 Adjust 回传收入用（ROAS 出价）。商店未加载时回退写死 CNY 定价。
    func priceInfo(for productID: String) -> (value: Double, currency: String) {
        if let product = products.first(where: { $0.id == productID }) {
            let currency = product.priceFormatStyle.currencyCode
            return ((product.price as NSDecimalNumber).doubleValue, currency)
        }
        return (productID == Self.yearlyID ? 298 : 48, "CNY")
    }

    private static func formatPriceWithPeriod(_ product: Product) -> String {
        guard let sub = product.subscription else { return product.displayPrice }
        let unit = periodUnitDisplay(sub.subscriptionPeriod)
        return "\(product.displayPrice)/\(unit)"
    }

    private static func periodUnitDisplay(_ period: Product.SubscriptionPeriod) -> String {
        let value = period.value
        switch period.unit {
        case .day:   return value == 1 ? String(localized: "天") : String(localized: "\(value)天")
        case .week:  return value == 1 ? String(localized: "周") : String(localized: "\(value)周")
        case .month: return value == 1 ? String(localized: "月") : String(localized: "\(value)个月")
        case .year:  return value == 1 ? String(localized: "年") : String(localized: "\(value)年")
        @unknown default: return ""
        }
    }

    // MARK: - Product IDs

    static let yearlyID = "com.amyhuang.castlingo.pro.yearly.v2"
    static let monthlyID = "com.amyhuang.castlingo.pro.monthly.v2"
    static let weeklyID = "com.amyhuang.castlingo.pro.weekly.v1"

    private var transactionListener: Task<Void, Error>?

    // MARK: - Free Tier Limits

    static let freeMaxDailyEpisodes = 2
    static let freeMaxDailyPatterns = 2
    static let freeMaxVocabPerEpisode = 3
    // Free users: 3 English + 1 Translation = 4 rounds (skip 5th)
    // Pro users: full 5 rounds

    // MARK: - Init

    init() {
        self.mockProEnabled = UserDefaults.standard.bool(forKey: "mockProEnabled")
        // Default mock trial on in debug so the trial UI is testable without
        // real App Store products. Production users start with nil (no trial)
        // until real product data loads.
        #if DEBUG
        let savedMockTrial = UserDefaults.standard.object(forKey: "mockHasTrialEnabled") as? Bool
        self.mockHasTrialEnabled = savedMockTrial ?? true
        #else
        self.mockHasTrialEnabled = false
        #endif
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
        Task { await checkStatus() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - StoreKit 2

    /// 三档里至少有一档拿到了真实商品（与 RC 分支同义）。
    var productsLoaded: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "mockWeeklyIntro") { return true }
        #endif
        return !products.isEmpty
    }

    @MainActor
    func loadProducts() async {
        do {
            let ids = [Self.yearlyID, Self.monthlyID, Self.weeklyID]
            products = try await Product.products(for: ids)
            await refreshTrialInfo()
        } catch {
            // Products not available yet (App Store Connect not configured)
        }
    }

    /// 付费墙出现 / App 回前台时调用：商品还没拿到就再拉一次。
    @MainActor
    func refreshProductsIfNeeded() async {
        guard !productsLoaded else { return }
        await loadProducts()
    }

    /// Reads `introductoryOffer` + eligibility for each loaded product and
    /// populates yearlyTrialInfo / monthlyTrialInfo. Called after loadProducts().
    @MainActor
    func refreshTrialInfo() async {
        var yearly: TrialInfo? = nil
        var monthly: TrialInfo? = nil

        var lines: [String] = []
        lines.append("products=\(products.count)")

        for product in products {
            lines.append("─ \(product.id)")
            guard let sub = product.subscription else {
                lines.append("  × no .subscription")
                continue
            }
            guard let offer = sub.introductoryOffer else {
                lines.append("  × no introductoryOffer")
                continue
            }
            lines.append("  offer.paymentMode=\(offer.paymentMode)")
            lines.append("  offer.period=\(offer.period.value) \(offer.period.unit)")
            guard offer.paymentMode == .freeTrial else {
                lines.append("  × skipped: not .freeTrial")
                continue
            }

            let eligible = await sub.isEligibleForIntroOffer
            lines.append("  isEligible=\(eligible)")
            let info = TrialInfo(
                productID: product.id,
                durationDisplay: Self.displayFromPeriod(offer.period),
                durationDays: Self.daysFromPeriod(offer.period),
                isEligible: eligible
            )

            guard info.isEligible else {
                lines.append("  × skipped: not eligible")
                continue
            }

            if product.id == Self.yearlyID {
                yearly = info
                lines.append("  ✅ yearly trial")
            } else if product.id == Self.monthlyID {
                monthly = info
                lines.append("  ✅ monthly trial")
            }
        }

        lines.append("final: yearly=\(yearly != nil ? "Y" : "nil") monthly=\(monthly != nil ? "Y" : "nil")")

        yearlyTrialInfo = yearly
        monthlyTrialInfo = monthly
        trialDebugLines = lines
        for line in lines { print("🔍 [TrialDebug] \(line)") }
    }

    private static func daysFromPeriod(_ period: Product.SubscriptionPeriod) -> Int {
        let value = period.value
        switch period.unit {
        case .day:   return value
        case .week:  return value * 7
        case .month: return value * 30
        case .year:  return value * 365
        @unknown default: return 0
        }
    }

    private static func displayFromPeriod(_ period: Product.SubscriptionPeriod) -> String {
        let value = period.value
        switch period.unit {
        case .day:   return String(localized: "\(value) 天")
        case .week:  return value == 1 ? String(localized: "7 天") : String(localized: "\(value * 7) 天")
        case .month: return String(localized: "\(value) 个月")
        case .year:  return String(localized: "\(value) 年")
        @unknown default: return ""
        }
    }

    @MainActor
    func purchase(_ productID: String) async -> Bool {
        lastFailureReason = nil
        isPurchasing = true
        defer { isPurchasing = false }

        // 商品没加载出来就当场重拉一次再买（与 RC 分支同策略）
        if !products.contains(where: { $0.id == productID }) {
            await loadProducts()
        }

        guard let product = products.first(where: { $0.id == productID }) else {
            lastFailureReason = "product_not_loaded"
            lastPurchaseError = String(localized: "商品未加载，请稍后重试。")
            return false
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    isPro = true
                    return true
                case .unverified(_, let error):
                    lastFailureReason = "unverified"
                    lastPurchaseError = String(localized: "交易验证失败：\(error.localizedDescription)")
                }
            case .userCancelled:
                lastFailureReason = "cancelled"
            case .pending:
                lastFailureReason = "pending"
                lastPurchaseError = String(localized: "购买待处理：可能需要家长批准或账号验证，请去 设置 → Apple ID 完成验证后重试。")
            @unknown default:
                lastFailureReason = "unknown"
                lastPurchaseError = String(localized: "未知购买结果类型。")
            }
        } catch {
            lastFailureReason = "store_error"
            lastPurchaseError = String(localized: "购买失败：\(error.localizedDescription)")
        }
        return false
    }

    @MainActor
    func restore() async {
        do {
            try await AppStore.sync()
            await checkStatus()
        } catch {
            // Restore failed
        }
    }

    @MainActor
    func checkStatus() async {
        var hasPro = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if transaction.productID == Self.yearlyID ||
                   transaction.productID == Self.monthlyID {
                    hasPro = true
                }
            }
        }
        isPro = hasPro
    }

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                if let transaction = try? self.checkVerified(result) {
                    await transaction.finish()
                    await MainActor.run {
                        self.isPro = true
                    }
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: Error {
        case failedVerification
    }
}

#endif
