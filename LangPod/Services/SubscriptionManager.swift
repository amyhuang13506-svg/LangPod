import StoreKit
import SwiftUI

/// Trial availability for a given product — derived from App Store Connect's
/// introductory offer config + per-user eligibility check.
struct TrialInfo: Equatable {
    let productID: String
    /// e.g. "7 天", "1 个月"
    let durationDisplay: String
    /// Numeric days (used to render "第 X 天" in the timeline)
    let durationDays: Int
    let isEligible: Bool
}

@Observable
class SubscriptionManager {
    // MARK: - State

    var isPro: Bool = false
    var isPurchasing = false
    var products: [Product] = []

    // Trial info fetched from products (nil = backend didn't configure OR user not eligible)
    var yearlyTrialInfo: TrialInfo?
    var monthlyTrialInfo: TrialInfo?

    // Mock toggles for development
    var mockProEnabled: Bool {
        didSet { UserDefaults.standard.set(mockProEnabled, forKey: "mockProEnabled") }
    }
    var mockHasTrialEnabled: Bool {
        didSet { UserDefaults.standard.set(mockHasTrialEnabled, forKey: "mockHasTrialEnabled") }
    }

    // Computed: real subscription OR mock
    var isProUser: Bool {
        isPro || mockProEnabled
    }

    /// Yearly trial info preferring real data, falling back to dev mock (DEBUG only).
    var effectiveYearlyTrial: TrialInfo? {
        if let real = yearlyTrialInfo { return real }
        #if DEBUG
        if mockHasTrialEnabled {
            return TrialInfo(productID: Self.yearlyID, durationDisplay: "7 天", durationDays: 7, isEligible: true)
        }
        #endif
        return nil
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

    static let yearlyID = "com.amyhuang.castlingo.pro.yearly"
    static let monthlyID = "com.amyhuang.castlingo.pro.monthly"

    private var transactionListener: Task<Void, Error>?

    // MARK: - Free Tier Limits

    static let freeMaxDailyEpisodes = 2
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

        for product in products {
            guard let sub = product.subscription,
                  let offer = sub.introductoryOffer,
                  offer.paymentMode == .freeTrial else { continue }

            let eligible = await sub.isEligibleForIntroOffer
            let info = TrialInfo(
                productID: product.id,
                durationDisplay: Self.displayFromPeriod(offer.period),
                durationDays: Self.daysFromPeriod(offer.period),
                isEligible: eligible
            )

            // Only surface the trial if the user is actually eligible
            guard info.isEligible else { continue }

            if product.id == Self.yearlyID {
                yearly = info
            } else if product.id == Self.monthlyID {
                monthly = info
            }
        }

        yearlyTrialInfo = yearly
        monthlyTrialInfo = monthly
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
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if let transaction = try? checkVerified(verification) {
                    await transaction.finish()
                    isPro = true
                    return true
                }
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            // Purchase failed
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
