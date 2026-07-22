import SwiftUI
#if canImport(RevenueCatUI)
import RevenueCat
import RevenueCatUI
#endif

// 付费墙统一入口：所有调用点继续用 PaywallView()。
// 默认走本地手写付费墙（RC 模板视觉 + 动效 + 试用时间线）；
// DEBUG 可切到 RevenueCat 后台远程模板对比效果。
struct PaywallView: View {
    var body: some View {
        #if canImport(RevenueCatUI) && DEBUG
        if UserDefaults.standard.bool(forKey: "useRemotePaywall") {
            RemotePaywallView()
        } else {
            LegacyPaywallView()
        }
        #else
        LegacyPaywallView()
        #endif
    }
}

#if canImport(RevenueCatUI)
struct RemotePaywallView: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var pendingProductID = ""

    var body: some View {
        RevenueCatUI.PaywallView(displayCloseButton: true)
            .onPurchaseStarted { (package: Package) in
                pendingProductID = package.storeProduct.productIdentifier
                Analytics.track(.purchaseAttempt, params: ["product": pendingProductID])
            }
            .onPurchaseCompleted { (customerInfo: CustomerInfo) in
                Analytics.track(.purchaseSuccess, params: ["product": pendingProductID])
                if customerInfo.entitlements[RevenueCatConfig.entitlementID]?.periodType == .trial {
                    Analytics.track(.trialStart, params: ["product": pendingProductID])
                } else {
                    let price = subscriptionManager.priceInfo(for: pendingProductID)
                    AdjustTracker.trackRevenue(.purchaseSuccess, amount: price.value, currency: price.currency)
                }
                dismiss()
            }
            .onPurchaseFailure { _ in
                Analytics.track(.purchaseFail, params: ["product": pendingProductID])
            }
            .onPurchaseCancelled {
                Analytics.track(.purchaseFail, params: ["product": pendingProductID, "reason": "cancelled"])
            }
            .onRestoreCompleted { (customerInfo: CustomerInfo) in
                if customerInfo.entitlements[RevenueCatConfig.entitlementID]?.isActive == true {
                    dismiss()
                }
            }
            .onAppear {
                Analytics.track(.paywallView)
            }
            // Paywalls v2 模板忽略 displayCloseButton，自己叠一个关闭按钮保证能退出
            .overlay(alignment: .topTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.top, 10)
                .padding(.trailing, 16)
            }
    }
}
#endif
