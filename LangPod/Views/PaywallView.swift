import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: PricePlan = .yearly
    @State private var breathePhase = false
    @State private var headerAppeared = false
    @State private var iconFloat = false
    @State private var featuresAppeared: [Bool] = Array(repeating: false, count: 5)

    enum PricePlan { case monthly, yearly }

    // MARK: - Body

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        heroSection
                        featureCard
                        planSelection
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .animation(.easeInOut(duration: 0.25), value: selectedPlan)
                }
                fixedBottom
            }
        }
        .onAppear { startAnimations() }
    }

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
            Button {} label: {
                Text("恢复购买")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.6), in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - Animations

    private func startAnimations() {
        withAnimation(.easeOut(duration: 0.6)) { headerAppeared = true }
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { iconFloat = true }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { breathePhase = true }
        for i in 0..<featuresAppeared.count {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.5, blendDuration: 0.5).delay(Double(i) * 0.25 + 0.5)) {
                featuresAppeared[i] = true
            }
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

    private let featureTexts = [
        "无限播客集数，想听多少听多少",
        "词义配对 + 连词成句练习",
        "完整词汇本，无限保存",
        "离线缓存 + 倍速播放",
        "Streak 冻结卡，每月 2 次",
    ]

    private var featureCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Castlingo Pro")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .padding(.bottom, 12)

            ForEach(Array(featureTexts.enumerated()), id: \.offset) { i, text in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.appPrimary)
                        .frame(width: 18)
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.bodyText)
                }
                .padding(.vertical, 5)
                .opacity(featuresAppeared[i] ? 1 : 0)
                .offset(x: featuresAppeared[i] ? 0 : -20)
            }

            Rectangle().fill(Color.divider).frame(height: 1).padding(.vertical, 12)

            HStack(spacing: 6) {
                Text("3天免费试用")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.success)
                Text("·")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textQuaternary)
                Text("年付平均 ¥0.8/天")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.appPrimary)
            }
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.border, lineWidth: 1))
    }

    // MARK: - Plan Selection

    private var planSelection: some View {
        VStack(spacing: 16) {
            // Yearly slot — always first position
            subscriptionRow(
                title: "年付",
                price: "¥298/年",
                trialPrice: "¥298/年",
                isSelected: selectedPlan == .yearly,
                onTap: { selectedPlan = .yearly }
            )

            // Monthly slot — always second position
            subscriptionRow(
                title: "月付",
                price: "¥48/月",
                trialPrice: "¥48/月",
                isSelected: selectedPlan == .monthly,
                onTap: { selectedPlan = .monthly }
            )
        }
    }

    private func subscriptionRow(title: String, price: String, trialPrice: String, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { onTap() }
            } label: {
                HStack {
                    Text(isSelected ? "开启免费试用" : title)
                        .font(.system(size: isSelected ? 16 : 15, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(Color(hex: isSelected ? "1E293B" : "94A3B8"))
                    Spacer()
                    if isSelected {
                        Toggle("", isOn: .constant(true))
                            .labelsHidden()
                            .tint(Color.appPrimary)
                            .allowsHitTesting(false)
                    } else {
                        Text(price)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    isSelected ? Color.white : Color.white,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isSelected ? Color.appPrimary : Color.border, lineWidth: isSelected ? 2 : 1)
                )
            }
            .buttonStyle(.plain)

            if isSelected {
                trialDetails(price: trialPrice)
            }
        }
    }


    // MARK: - Trial Details (shared)

    private var trialEndDate: String {
        let date = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }

    private func trialDetails(price: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(Color.appPrimary).frame(width: 7, height: 7)
                    Text("今日应付")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.bodyText)
                }
                Spacer()
                HStack(spacing: 8) {
                    Text("3天免费试用")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.success)
                    Text("¥0")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                }
            }
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(Color.warning).frame(width: 7, height: 7)
                    Text(trialEndDate)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.bodyText)
                }
                Spacer()
                Text(price)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.warning)
            }
        }
        .padding(.horizontal, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }


    // MARK: - Fixed Bottom

    private var fixedBottom: some View {
        VStack(spacing: 8) {
            Button {} label: {
                Text("开始免费试用")
                    .font(.system(size: 17, weight: .bold))
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
            .padding(.horizontal, 24)

            Text("试用结束后自动续费，可随时取消")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)

            HStack(spacing: 8) {
                if let privacyURL = URL(string: "https://amyhuang13506-svg.github.io/Castlingo/docs/privacy.html") {
                    Link("隐私政策", destination: privacyURL)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }
                Text("|")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textQuaternary)
                if let termsURL = URL(string: "https://amyhuang13506-svg.github.io/Castlingo/docs/terms.html") {
                    Link("用户协议", destination: termsURL)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}

#Preview {
    PaywallView()
}
