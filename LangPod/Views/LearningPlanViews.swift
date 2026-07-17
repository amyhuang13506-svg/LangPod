import SwiftUI

// MARK: - LearningPlan 颜色桥接
// Models/ 全层不 import SwiftUI，颜色以 hex String 存在模型里。
// 视图层在这里把 hex 还原成 Color，onboarding 的 goal.color / goal.bgColor
// 调用点因此一行不用改。

extension LearningGoal {
    var color: Color { Color(hex: colorHex) }
    var bgColor: Color { Color(hex: bgColorHex) }
}

extension LearningPlan.Item {
    var color: Color { Color(hex: colorHex) }
}

// MARK: - 共享行组件（onboarding 计划页 + 「我的」计划详情页 同源）

/// 计划摘要 chip：级别 / 每天 N 分钟 / 目标
struct PlanChip: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.appPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primaryLight, in: Capsule())
    }
}

/// 「每天做什么」一行
struct PlanItemRow: View {
    let item: LearningPlan.Item

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(item.color.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: item.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(item.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(item.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// 里程碑一行。`isAchieved` 纯附加：默认 false 时与 onboarding 逐像素一致，
/// 达成时在标题行右侧补一个 ✓。
struct PlanMilestoneRow: View {
    let milestone: LearningPlan.Milestone
    var isAchieved: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(milestone.dayLabel)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.appPrimary)
                .frame(width: 52, alignment: .leading)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(milestone.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    if isAchieved {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.success)
                    }
                }
                Text(milestone.desc)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 累计活跃进度条（当前 → 90 天）
struct PlanProgressBar: View {
    let activeDays: Int

    var body: some View {
        ProgressView(value: Double(min(activeDays, 90)), total: 90)
            .tint(Color.appPrimary)
    }
}

// MARK: - 「我的」学习计划详情页

struct LearningPlanPage: View {
    @Environment(DataStore.self) private var dataStore

    private var plan: LearningPlan {
        LearningPlan.persisted(level: dataStore.selectedLevel)
    }

    private var activeDays: Int { dataStore.activeDays }

    /// 距离下一个里程碑的提示文案
    private var progressCaption: String {
        if let next = plan.nextMilestone(activeDays: activeDays) {
            let remain = next.day - activeDays
            return "累计活跃 \(activeDays) 天 · 还有 \(remain) 天到「\(next.title)」"
        }
        return "累计活跃 \(activeDays) 天 · 90 天里程碑全部达成 🎉"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // chips
                HStack(spacing: 8) {
                    ForEach(plan.chips, id: \.self) { PlanChip($0) }
                }

                // 进度块（onboarding 没有的部分）
                VStack(alignment: .leading, spacing: 10) {
                    Text(progressCaption)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                    PlanProgressBar(activeDays: activeDays)
                }
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.border, lineWidth: 1))

                // 每天做什么
                VStack(alignment: .leading, spacing: 10) {
                    Text("每天做什么")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    VStack(spacing: 0) {
                        ForEach(Array(plan.items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider().padding(.leading, 70) }
                            PlanItemRow(item: item)
                        }
                    }
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.border, lineWidth: 1))
                }

                // 效果预期时间线（达成的打 ✓）
                VStack(alignment: .leading, spacing: 16) {
                    Text("坚持下去，你会听到变化")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    ForEach(plan.milestones) { milestone in
                        PlanMilestoneRow(milestone: milestone, isAchieved: activeDays >= milestone.day)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color.primaryLight, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .navigationTitle("我的学习计划")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)   // 进详情页隐藏底部 tab bar
    }
}
