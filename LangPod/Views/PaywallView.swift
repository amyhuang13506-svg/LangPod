import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: PricePlan = .yearly

    enum PricePlan: String, CaseIterable {
        case monthly, yearly, lifetime

        var title: String {
            switch self {
            case .monthly: "月付"
            case .yearly: "年付"
            case .lifetime: "终身"
            }
        }

        var price: String {
            switch self {
            case .monthly: "¥28/月"
            case .yearly: "¥168/年"
            case .lifetime: "¥298"
            }
        }

        var perDay: String? {
            switch self {
            case .monthly: "¥0.93/天"
            case .yearly: "¥0.46/天"
            case .lifetime: "一次买断"
            }
        }

        var badge: String? {
            switch self {
            case .yearly: "最受欢迎"
            case .lifetime: "限时"
            default: nil
            }
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "F7F8FC").ignoresSafeArea()

            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color(hex: "94A3B8"))
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Text("🎧")
                                .font(.system(size: 48))
                            Text("升级 LangPod Pro")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color(hex: "1E293B"))
                            Text("解锁全部功能，让英语学习更高效")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "94A3B8"))
                        }

                        // Features
                        featuresCard

                        // Price plans
                        VStack(spacing: 12) {
                            ForEach(PricePlan.allCases, id: \.rawValue) { plan in
                                pricePlanCard(plan)
                            }
                        }

                        // Subscribe button
                        Button {
                            // TODO: StoreKit 2 purchase
                        } label: {
                            Text("立即订阅")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color(hex: "3B82F6"), in: RoundedRectangle(cornerRadius: 16))
                        }

                        // Legal links
                        HStack(spacing: 16) {
                            Text("自动续费，可随时取消")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: "94A3B8"))
                        }

                        HStack(spacing: 16) {
                            Button {
                                // TODO: StoreKit 2 restore
                            } label: {
                                Text("恢复购买")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(hex: "3B82F6"))
                            }
                            Text("·")
                                .foregroundStyle(Color(hex: "CBD5E1"))
                            Link("隐私政策", destination: URL(string: "https://langpod.com/privacy")!)
                                .font(.system(size: 12))
                                .foregroundStyle(Color(hex: "94A3B8"))
                            Text("·")
                                .foregroundStyle(Color(hex: "CBD5E1"))
                            Link("用户协议", destination: URL(string: "https://langpod.com/terms")!)
                                .font(.system(size: 12))
                                .foregroundStyle(Color(hex: "94A3B8"))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: - Features Card

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow(icon: "infinity", text: "无限集数，每天想听多少听多少")
            featureRow(icon: "captions.bubble", text: "双语字幕，边听边看")
            featureRow(icon: "book.closed", text: "完整词汇本 + 记忆曲线追踪")
            featureRow(icon: "gamecontroller", text: "词义配对 + 费曼挑战")
            featureRow(icon: "arrow.down.circle", text: "离线缓存，无网也能听")
            featureRow(icon: "snowflake", text: "Streak 冻结卡，每月 2 次")
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
        )
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: "3B82F6"))
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "1E293B"))
        }
    }

    // MARK: - Price Plan Card

    private func pricePlanCard(_ plan: PricePlan) -> some View {
        let isSelected = selectedPlan == plan

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedPlan = plan }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(hex: "1E293B"))
                        if let badge = plan.badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color(hex: plan == .yearly ? "3B82F6" : "F59E0B"), in: Capsule())
                        }
                    }
                    if let perDay = plan.perDay {
                        Text(perDay)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "94A3B8"))
                    }
                }

                Spacer()

                Text(plan.price)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: isSelected ? "3B82F6" : "1E293B"))
            }
            .padding(18)
            .background(
                isSelected ? Color(hex: "EFF6FF") : Color.white,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color(hex: "3B82F6") : Color(hex: "E2E8F0"),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PaywallView()
}
