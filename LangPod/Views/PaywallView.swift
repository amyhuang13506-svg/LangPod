import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptionManager

    @State private var selectedPlan: PricePlan = .yearly
    @State private var breathePhase = false
    @State private var headerAppeared = false
    @State private var iconFloat = false
    @State private var featuresAppeared: [Bool] = Array(repeating: false, count: 6)
    @State private var planRowsAppeared: [Bool] = [false, false]
    @State private var trialRowsAppeared: [Bool] = [false, false, false]
    @State private var topBarHeight: CGFloat = 44
    @State private var fixedBottomHeight: CGFloat = 160

    enum PricePlan { case monthly, yearly }

    // MARK: - Body

    var body: some View {
        GeometryReader { outerGeo in
            ZStack(alignment: .top) {
                background
                #if DEBUG
                trialDebugOverlay
                    .zIndex(1000)
                #endif
                VStack(spacing: 0) {
                    topBar
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: TopBarHeightKey.self, value: geo.size.height)
                            }
                        )

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            // Above-fold: hero flexes to fill the space that features + yearly + timeline don't use.
                            // Sized to exactly the visible area so monthly row sits just below the fold.
                            VStack(spacing: 16) {
                                heroSection
                                    .frame(maxHeight: .infinity, alignment: .center)

                                featureCard

                                // Yearly row + trial timeline (always above-fold)
                                VStack(spacing: 12) {
                                    subscriptionRow(
                                        title: "年付",
                                        price: subscriptionManager.yearlyPriceDisplay,
                                        isSelected: selectedPlan == .yearly,
                                        onTap: { selectedPlan = .yearly }
                                    )
                                    .opacity(planRowsAppeared[0] ? 1 : 0)
                                    .offset(x: planRowsAppeared[0] ? 0 : -20)

                                    trialDetails()
                                }
                            }
                            .frame(
                                minHeight: max(480, outerGeo.size.height - topBarHeight - fixedBottomHeight - 14),
                                alignment: .top
                            )

                            // Below-fold: monthly row — off-screen by default, scroll down to reach
                            subscriptionRow(
                                title: "月付",
                                price: subscriptionManager.monthlyPriceDisplay,
                                isSelected: selectedPlan == .monthly,
                                onTap: { selectedPlan = .monthly }
                            )
                            .opacity(planRowsAppeared[1] ? 1 : 0)
                            .offset(x: planRowsAppeared[1] ? 0 : -20)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                        .animation(.easeInOut(duration: 0.25), value: selectedPlan)
                    }

                    fixedBottom
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: FixedBottomHeightKey.self, value: geo.size.height)
                            }
                        )
                }
            }
            .onPreferenceChange(TopBarHeightKey.self) { if $0 > 0 { topBarHeight = $0 } }
            .onPreferenceChange(FixedBottomHeightKey.self) { if $0 > 0 { fixedBottomHeight = $0 } }
        }
        .onAppear {
            startAnimations()
            Analytics.track(.paywallView)
        }
        .alert(
            "购买未完成",
            isPresented: Binding(
                get: { subscriptionManager.lastPurchaseError != nil },
                set: { if !$0 { subscriptionManager.lastPurchaseError = nil } }
            ),
            presenting: subscriptionManager.lastPurchaseError
        ) { _ in
            Button("好") { subscriptionManager.lastPurchaseError = nil }
        } message: { msg in
            Text(msg)
        }
    }

    #if DEBUG
    // MARK: - Trial Debug Overlay (DEBUG only)
    @State private var showDebugOverlay = false

    private var trialDebugOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    withAnimation { showDebugOverlay.toggle() }
                } label: {
                    Text(showDebugOverlay ? "隐藏诊断" : "🔍 诊断")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6), in: Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 60)
            .padding(.top, 50)

            if showDebugOverlay {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(subscriptionManager.trialDebugLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        }
    }
    #endif

    // MARK: - Background

    private var background: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "DBEAFE"), location: 0),
                    .init(color: Color(hex: "E0E7FF"), location: 0.15),
                    .init(color: Color(hex: "EEF2FF"), location: 0.35),
                    .init(color: Color(hex: "F7F8FC"), location: 0.55),
                    .init(color: Color(hex: "FFFFFF"), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(hex: "93C5FD").opacity(0.3), Color(hex: "A5B4FC").opacity(0.15), .clear],
                center: .init(x: 0.5, y: 0.12), startRadius: 10, endRadius: 250
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 32, height: 32)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - Animations

    private func startAnimations() {
        withAnimation(.easeOut(duration: 0.6)) { headerAppeared = true }
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { iconFloat = true }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { breathePhase = true }

        // Stage 1: feature card rows (8 features, 0.18s interval)
        let featureInterval = 0.18
        let featureStart = 0.5
        for i in 0..<featuresAppeared.count {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.5, blendDuration: 0.5).delay(Double(i) * featureInterval + featureStart)) {
                featuresAppeared[i] = true
            }
        }

        // Stage 2: yearly row → trial timeline 1-3 → monthly row (sequential slide-in)
        let featureEnd = featureStart + Double(featuresAppeared.count - 1) * featureInterval
        let planInterval = 0.15
        let stage2Start = featureEnd + 0.4

        // Yearly row
        withAnimation(.spring(response: 0.8, dampingFraction: 0.5, blendDuration: 0.5).delay(stage2Start)) {
            planRowsAppeared[0] = true
        }
        // Trial timeline rows (3)
        for i in 0..<trialRowsAppeared.count {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.5, blendDuration: 0.5).delay(stage2Start + planInterval * Double(i + 1))) {
                trialRowsAppeared[i] = true
            }
        }
        // Monthly row (after all trial rows)
        withAnimation(.spring(response: 0.8, dampingFraction: 0.5, blendDuration: 0.5).delay(stage2Start + planInterval * Double(trialRowsAppeared.count + 1))) {
            planRowsAppeared[1] = true
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "headphones")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.appPrimary, Color(hex: "6366F1")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.appPrimary.opacity(0.15), radius: 20, y: iconFloat ? 10 : 4)
                .offset(y: iconFloat ? -8 : 8)
                .padding(.top, 6)

            (
                Text("Castlingo ")
                    .font(.system(size: 22, weight: .semibold))
                + Text("Pro")
                    .font(.system(size: 28, weight: .bold))
            )
            .foregroundStyle(Color(hex: "1E3A5F"))

            Text("坚持一整年，流利说英语")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(hex: "1E3A5F"))
                .multilineTextAlignment(.center)

            Text("每天 6 分钟，随时随地")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.bodyText)

            Text("轻松提升英语听力")
                .font(.system(size: 14))
                .foregroundStyle(Color.textTertiary)
        }
        .opacity(headerAppeared ? 1 : 0)
        .offset(y: headerAppeared ? 0 : 12)
    }

    // MARK: - Feature Card

    private struct ComparisonRow {
        let freeText: String  // shown in free column; empty = show ✗
        let proText: String
    }

    private let comparisons: [ComparisonRow] = [
        ComparisonRow(freeText: "每日 2 集",  proText: "每日无限集数"),
        ComparisonRow(freeText: "仅前 4 遍",  proText: "完整 5 遍循环播放法"),
        ComparisonRow(freeText: "❌ 不可用",  proText: "实时双语字幕"),
        ComparisonRow(freeText: "每集 3 个",  proText: "每集全部生词卡片"),
        ComparisonRow(freeText: "每日 1 轮",  proText: "词义配对无限练习"),
        ComparisonRow(freeText: "每日 1 轮",  proText: "连词成句无限练习"),
    ]

    private var featureCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Castlingo Pro")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .padding(.bottom, 12)

            // Column headers
            HStack(spacing: 0) {
                Text("免费版")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 88, alignment: .leading)

                // Short dashed divider in the header row
                DashedVerticalLine()
                    .stroke(Color.textTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: 1, height: 16)

                Text("Pro 版")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
            }
            .padding(.bottom, 8)

            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
                .padding(.bottom, 8)

            // Comparison rows — each row has its own dashed divider that animates with the row
            ForEach(Array(comparisons.enumerated()), id: \.offset) { i, row in
                HStack(spacing: 0) {
                    // Free column — left-aligned, fixed width
                    Text(row.freeText)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(width: 88, alignment: .leading)

                    // Per-row dashed divider — animates with the row
                    DashedVerticalLine()
                        .stroke(Color.textTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .frame(width: 1, height: 18)

                    // Pro column — left-aligned, flexible
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.appPrimary)
                        Text(row.proText)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.bodyText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
                }
                .padding(.vertical, 6)
                .opacity(featuresAppeared[i] ? 1 : 0)
                .offset(x: featuresAppeared[i] ? 0 : -20)
            }
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.border, lineWidth: 1))
    }

    // MARK: - Plan Selection

    private func subscriptionRow(title: String, price: String, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { onTap() }
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: isSelected ? 16 : 15, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(Color(hex: isSelected ? "1E293B" : "94A3B8"))
                Spacer()
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(Color.appPrimary)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                } else {
                    Text(price)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.appPrimary : Color.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }


    // MARK: - Trial Details (shared)

    private var renewalPriceText: String {
        selectedPlan == .yearly ? subscriptionManager.yearlyPriceDisplay : subscriptionManager.monthlyPriceDisplay
    }

    /// Inline-styled renewal summary above the CTA. Only the price is orange-bolded
    /// so App Review sees an unambiguous, conspicuous disclosure.
    @ViewBuilder
    private var renewalSummaryText: some View {
        if let trial = currentTrial {
            Text("\(trial.durationDisplay)免费试用，之后按 ")
                .foregroundStyle(Color.textTertiary)
            + Text(renewalPriceText)
                .foregroundStyle(Color.warning)
                .fontWeight(.semibold)
            + Text(" 自动续费")
                .foregroundStyle(Color.textTertiary)
        } else {
            Text("按 ")
                .foregroundStyle(Color.textTertiary)
            + Text(renewalPriceText)
                .foregroundStyle(Color.warning)
                .fontWeight(.semibold)
            + Text(" 自动续费，可随时取消")
                .foregroundStyle(Color.textTertiary)
        }
    }

    /// Active trial info for the currently selected plan — nil means no trial available.
    private var currentTrial: TrialInfo? {
        selectedPlan == .yearly ? subscriptionManager.effectiveYearlyTrial : subscriptionManager.effectiveMonthlyTrial
    }

    private var hasActiveTrial: Bool {
        currentTrial != nil
    }

    /// "Day 5" notification row is shown when the trial is long enough (≥ 5 days).
    private var reminderDay: Int? {
        guard let days = currentTrial?.durationDays, days >= 5 else { return nil }
        return max(3, days - 2)  // remind 2 days before trial ends, minimum day 3
    }

    @ViewBuilder
    private func trialDetails() -> some View {
        if let trial = currentTrial {
            trialTimeline(trial: trial)
        } else {
            noTrialDetails()
        }
    }

    /// Full 3-row timeline for an active trial: today / reminder / last day.
    private func trialTimeline(trial: TrialInfo) -> some View {
        let renewalPrice = renewalPriceText

        return VStack(spacing: 10) {
            // Row 1: Today — unlock everything, ¥0
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.success)
                    .frame(width: 9, height: 9)
                Text("今天 · 解锁全部 Pro 功能")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.bodyText)
                Spacer()
                Text("¥0")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
            }
            .opacity(trialRowsAppeared[0] ? 1 : 0)
            .offset(x: trialRowsAppeared[0] ? 0 : -20)

            // Row 2: Reminder before trial ends
            HStack(spacing: 10) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.warning)
                    .frame(width: 9, height: 9)
                Text("第 \(reminderDay ?? 5) 天 · 提醒你试用到期")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.warning)
                Spacer()
            }
            .opacity(trialRowsAppeared[1] ? 1 : 0)
            .offset(x: trialRowsAppeared[1] ? 0 : -20)

            // Row 3: Last day — cancel or auto-renew
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.textTertiary)
                    .frame(width: 9, height: 9)
                Text("第 \(trial.durationDays) 天 · 满意续费，不满意取消")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.bodyText)
                Spacer()
                Text(renewalPrice)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
            }
            .opacity(trialRowsAppeared[2] ? 1 : 0)
            .offset(x: trialRowsAppeared[2] ? 0 : -20)
        }
        .padding(.horizontal, 4)
    }

    /// Simpler 2-row layout for users without an active trial.
    private func noTrialDetails() -> some View {
        let renewalPrice = renewalPriceText

        return VStack(spacing: 10) {
            // Row 1: Today — subscribe + full price
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.success)
                    .frame(width: 9, height: 9)
                Text("今天 · 解锁全部 Pro 功能")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.bodyText)
                Spacer()
                Text(renewalPrice)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
            }
            .opacity(trialRowsAppeared[0] ? 1 : 0)
            .offset(x: trialRowsAppeared[0] ? 0 : -20)

            // Row 2: Cancel anytime
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.success)
                    .frame(width: 9, height: 9)
                Text("可在 App Store 设置中随时取消")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.bodyText)
                Spacer()
            }
            .opacity(trialRowsAppeared[1] ? 1 : 0)
            .offset(x: trialRowsAppeared[1] ? 0 : -20)
        }
        .padding(.horizontal, 4)
    }


    // MARK: - Fixed Bottom

    private var fixedBottom: some View {
        VStack(spacing: 8) {
            // Line above CTA: trial / renewal summary (single line).
            // Only the price portion is orange-bolded for clear disclosure (App Review compliance).
            renewalSummaryText
                .font(.system(size: 11))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 24)

            // CTA button
            Button {
                let productID = selectedPlan == .yearly
                    ? SubscriptionManager.yearlyID
                    : SubscriptionManager.monthlyID
                Analytics.track(.purchaseAttempt, params: ["product": productID])
                Task {
                    let success = await subscriptionManager.purchase(productID)
                    Analytics.track(success ? .purchaseSuccess : .purchaseFail, params: ["product": productID])
                    if success { dismiss() }
                }
            } label: {
                Group {
                    if subscriptionManager.isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(hasActiveTrial ? "开始免费试用" : "立即订阅")
                            .font(.system(size: 17, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
                .shadow(
                    color: Color.appPrimary.opacity(breathePhase ? 0.35 : 0.1),
                    radius: breathePhase ? 10 : 3,
                    y: breathePhase ? 4 : 2
                )
                .scaleEffect(breathePhase ? 1.01 : 1.0)
            }
            .disabled(subscriptionManager.isPurchasing)
            .padding(.horizontal, 24)

            // Line below CTA: "随时取消" on left, links on right (single line)
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.success)
                    Text("随时取消")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer()

                if let termsURL = URL(string: "https://amyhuang13506-svg.github.io/LangPod/docs/terms.html") {
                    Link("使用条款", destination: termsURL)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textQuaternary)
                if let privacyURL = URL(string: "https://amyhuang13506-svg.github.io/LangPod/docs/privacy.html") {
                    Link("隐私政策", destination: privacyURL)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textQuaternary)
                Button {
                    Task { await subscriptionManager.restore() }
                } label: {
                    Text("恢复购买")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}

/// Preference keys for measuring the fixed top bar and bottom CTA heights.
private struct TopBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FixedBottomHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Vertical dashed line shape used as the column divider in the Free vs Pro comparison table.
private struct DashedVerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

#Preview {
    PaywallView()
        .environment(SubscriptionManager())
}
