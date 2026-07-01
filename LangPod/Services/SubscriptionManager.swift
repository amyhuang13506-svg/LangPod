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

    // Trial info fetched from offerings (nil = no intro offer OR user not eligible)
    var yearlyTrialInfo: TrialInfo?
    var monthlyTrialInfo: TrialInfo?

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
        return TrialInfo(productID: Self.yearlyID, durationDisplay: "7 天", durationDays: 7, isEligible: true)
        #else
        return yearlyTrialInfo
        #endif
    }

    var effectiveMonthlyTrial: TrialInfo? {
        // Product policy: monthly never offers a free trial.
        nil
    }

    // MARK: - Localized Price Display

    private var yearlyPackage: Package?
    private var monthlyPackage: Package?

    var yearlyPriceDisplay: String {
        if let pkg = yearlyPackage {
            return Self.formatPriceWithPeriod(pkg.storeProduct)
        }
        return "¥298/年"
    }

    var monthlyPriceDisplay: String {
        if let pkg = monthlyPackage {
            return Self.formatPriceWithPeriod(pkg.storeProduct)
        }
        return "¥48/月"
    }

    private static func formatPriceWithPeriod(_ product: StoreProduct) -> String {
        guard let period = product.subscriptionPeriod else { return product.localizedPriceString }
        return "\(product.localizedPriceString)/\(periodUnitDisplay(period))"
    }

    private static func periodUnitDisplay(_ period: RevenueCat.SubscriptionPeriod) -> String {
        let value = period.value
        switch period.unit {
        case .day:   return value == 1 ? "天" : "\(value)天"
        case .week:  return value == 1 ? "周" : "\(value)周"
        case .month: return value == 1 ? "月" : "\(value)个月"
        case .year:  return value == 1 ? "年" : "\(value)年"
        @unknown default: return ""
        }
    }

    // MARK: - Product / Entitlement IDs

    static let yearlyID = "com.amyhuang.castlingo.pro.yearly.v2"
    static let monthlyID = "com.amyhuang.castlingo.pro.monthly.v2"

    private var customerInfoListener: Task<Void, Never>?

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
        Task { await loadProducts() }
        Task { await checkStatus() }
    }

    deinit {
        customerInfoListener?.cancel()
    }

    // MARK: - RevenueCat

    @MainActor
    func loadProducts() async {
        guard Purchases.isConfigured else { return }
        do {
            let offerings = try await Purchases.shared.offerings()
            let offering = offerings.current
            yearlyPackage = offering?.annual
                ?? offering?.availablePackages.first { $0.storeProduct.productIdentifier == Self.yearlyID }
            monthlyPackage = offering?.monthly
                ?? offering?.availablePackages.first { $0.storeProduct.productIdentifier == Self.monthlyID }
            await refreshTrialInfo()
        } catch {
            // Offerings not available yet (dashboard not configured / offline)
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

        lines.append("final: yearly=\(yearly != nil ? "Y" : "nil")")
        yearlyTrialInfo = yearly
        monthlyTrialInfo = nil
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
        case .day:   return "\(value) 天"
        case .week:  return value == 1 ? "7 天" : "\(value * 7) 天"
        case .month: return "\(value) 个月"
        case .year:  return "\(value) 年"
        @unknown default: return ""
        }
    }

    @MainActor
    func purchase(_ productID: String) async -> Bool {
        guard Purchases.isConfigured else {
            lastPurchaseError = "RevenueCat 未配置（appl_ API key 未填），暂时无法购买。"
            return false
        }

        let package: Package?
        switch productID {
        case Self.yearlyID:  package = yearlyPackage
        case Self.monthlyID: package = monthlyPackage
        default:             package = nil
        }

        guard let pkg = package else {
            lastPurchaseError = "商品未加载（offering 空），请稍后重试。ID: \(productID)"
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: pkg)
            if result.userCancelled { return false }  // user closed the sheet
            let active = result.customerInfo.entitlements[RevenueCatConfig.entitlementID]?.isActive == true
            isPro = active
            if !active {
                lastPurchaseError = "购买已完成，但未获得 Pro 权益，请稍后重试或联系客服。"
            }
            return active
        } catch {
            lastPurchaseError = "购买失败：\(error.localizedDescription)"
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

    // Trial info fetched from products (nil = backend didn't configure OR user not eligible)
    var yearlyTrialInfo: TrialInfo?
    var monthlyTrialInfo: TrialInfo?

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
        return TrialInfo(productID: Self.yearlyID, durationDisplay: "7 天", durationDays: 7, isEligible: true)
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
        return "¥298/年"
    }

    /// Monthly price with localized currency + period.
    var monthlyPriceDisplay: String {
        if let product = products.first(where: { $0.id == Self.monthlyID }) {
            return Self.formatPriceWithPeriod(product)
        }
        return "¥48/月"
    }

    private static func formatPriceWithPeriod(_ product: Product) -> String {
        guard let sub = product.subscription else { return product.displayPrice }
        let unit = periodUnitDisplay(sub.subscriptionPeriod)
        return "\(product.displayPrice)/\(unit)"
    }

    private static func periodUnitDisplay(_ period: Product.SubscriptionPeriod) -> String {
        let value = period.value
        switch period.unit {
        case .day:   return value == 1 ? "天" : "\(value)天"
        case .week:  return value == 1 ? "周" : "\(value)周"
        case .month: return value == 1 ? "月" : "\(value)个月"
        case .year:  return value == 1 ? "年" : "\(value)年"
        @unknown default: return ""
        }
    }

    // MARK: - Product IDs

    static let yearlyID = "com.amyhuang.castlingo.pro.yearly.v2"
    static let monthlyID = "com.amyhuang.castlingo.pro.monthly.v2"

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

    @MainActor
    func loadProducts() async {
        do {
            let ids = [Self.yearlyID, Self.monthlyID]
            products = try await Product.products(for: ids)
            await refreshTrialInfo()
        } catch {
            // Products not available yet (App Store Connect not configured)
        }
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
        case .day:   return "\(value) 天"
        case .week:  return value == 1 ? "7 天" : "\(value * 7) 天"
        case .month: return "\(value) 个月"
        case .year:  return "\(value) 年"
        @unknown default: return ""
        }
    }

    @MainActor
    func purchase(_ productID: String) async -> Bool {
        guard let product = products.first(where: { $0.id == productID }) else {
            lastPurchaseError = "商品未加载（products 空），请稍后重试。ID: \(productID)"
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

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
                    lastPurchaseError = "交易验证失败：\(error.localizedDescription)"
                }
            case .userCancelled:
                break  // user intentionally closed the sheet — no error
            case .pending:
                lastPurchaseError = "购买待处理：可能需要家长批准或账号验证，请去 设置 → Apple ID 完成验证后重试。"
            @unknown default:
                lastPurchaseError = "未知购买结果类型。"
            }
        } catch {
            lastPurchaseError = "购买失败：\(error.localizedDescription)"
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
