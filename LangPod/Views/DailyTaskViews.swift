import SwiftUI

// MARK: - Toast Data

struct TaskToastData: Equatable {
    let completedTitle: String
    let nextType: DailyTaskType?
}

// MARK: - 本周 7 格进度条（弹窗 + 「我的」页战绩区共用）

struct TaskWeekProgressView: View {
    @Environment(DataStore.self) private var dataStore

    struct WeekDay {
        let date: Date
        let label: String
        let count: Int
        let isToday: Bool
        let isFuture: Bool

        var color: Color {
            if count > 0 { return Color.success }
            if isToday { return Color.warning }
            if isFuture { return Color.border }
            return Color.textQuaternary
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.date) { day in
                VStack(spacing: 6) {
                    Text(day.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(day.isToday ? Color.textPrimary : Color.textTertiary)

                    Circle()
                        .fill(day.color)
                        .frame(width: 26, height: 26)
                        .overlay(
                            day.count > 0 ?
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                : nil
                        )
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var weekDays: [WeekDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let mondayOffset = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -mondayOffset, to: today) else { return [] }

        let labels = ["一", "二", "三", "四", "五", "六", "日"]

        return (0..<7).compactMap { i in
            guard let date = calendar.date(byAdding: .day, value: i, to: monday) else { return nil }
            let isToday = calendar.isDate(date, inSameDayAs: today)
            let isFuture = date > today
            let count = dataStore.listenHistory.filter {
                calendar.isDate($0.listenedAt, inSameDayAs: date)
            }.count

            return WeekDay(date: date, label: labels[i], count: count, isToday: isToday, isFuture: isFuture)
        }
    }
}

// MARK: - 今日任务清单弹窗

struct DailyTaskPopupView: View {
    @Environment(DataStore.self) private var dataStore
    var onClose: () -> Void
    var onTapTask: (DailyTaskType) -> Void

    @State private var cardScale: CGFloat = 0.92
    @State private var cardOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                header
                    .padding(.top, 22)
                    .padding(.horizontal, 22)

                TaskWeekProgressView()
                    .padding(.horizontal, 18)
                    .padding(.top, 18)

                taskList
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 20)
            }
            .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 24))
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white))
                }
                .padding(12)
            }
            .padding(.horizontal, 28)
            .scaleEffect(cardScale)
            .opacity(cardOpacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                cardScale = 1.0
                cardOpacity = 1.0
            }
        }
    }

    private var header: some View {
        let engine = TaskEngine.shared
        let litToday = dataStore.lastListenDate.map { Calendar.current.isDateInToday($0) } ?? false

        return HStack(spacing: 12) {
            Text("🔥")
                .font(.system(size: 34))
                .opacity(litToday ? 1 : 0.35)

            VStack(alignment: .leading, spacing: 3) {
                Text("连续 \(dataStore.streakDays) 天")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle(litToday: litToday, engine: engine))
                    .font(.system(size: 12.5))
                    .foregroundStyle(litToday ? Color.success : Color.textTertiary)
            }
            Spacer()
        }
    }

    private func subtitle(litToday: Bool, engine: TaskEngine) -> String {
        let done = engine.completedCount
        let total = engine.totalCount
        if done >= total && total > 0 { return "完美一天！\(total) 个任务全部完成" }
        if litToday { return "今日已点亮 · 完成 \(total)/\(total) 解锁完美一天" }
        return "完成任意 1 个任务点亮今日火苗"
    }

    private var taskList: some View {
        VStack(spacing: 8) {
            ForEach(TaskEngine.shared.todayTasks, id: \.type) { item in
                Button {
                    onTapTask(item.type)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.type.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(item.done ? Color.success : Color.appPrimary)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle().fill(item.done ? Color.successLight : Color.primaryLight)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.type.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(item.done ? Color.textTertiary : Color.textPrimary)
                                .strikethrough(item.done, color: Color.textQuaternary)
                            Text("约 \(item.type.estimatedMinutes) 分钟")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textQuaternary)
                        }

                        Spacer()

                        if item.done {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Color.success)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.textQuaternary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(item.done)
            }
        }
    }
}

// MARK: - 中途横条（照抄 EpisodeToast 模式，顶部滑入）

struct TaskToastBar: View {
    let data: TaskToastData
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.success)

                Group {
                    if let next = data.nextType {
                        Text("已完成：\(data.completedTitle) · 下一个：\(next.title)")
                    } else {
                        Text("已完成：\(data.completedTitle)")
                    }
                }
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                if data.nextType != nil {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.appPrimary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }
}

// MARK: - 点火大庆祝（4/4 完美一天）

struct TaskCelebrationView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(VocabularyStore.self) private var vocabularyStore
    var onShare: () -> Void
    var onContinue: () -> Void

    @State private var flameScale: CGFloat = 0
    @State private var contentOpacity: Double = 0
    @State private var confettiVisible = false
    @State private var confettiOffsets: [(CGFloat, CGFloat)] = (0..<14).map { _ in
        (CGFloat.random(in: -160...160), CGFloat.random(in: -240...(-60)))
    }

    /// 7/30/100 里程碑日与分享海报合并展示（当天出「炫耀一下」，不出第二个庆祝）
    private var isMilestoneDay: Bool {
        [7, 30, 100].contains(dataStore.streakDays)
    }

    private var nextMilestoneText: String? {
        let milestones = [7, 30, 100]
        guard let next = milestones.first(where: { $0 > dataStore.streakDays }) else { return nil }
        return "再坚持 \(next - dataStore.streakDays) 天点亮 \(next) 天徽章"
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            // 彩色粒子散射
            if confettiVisible {
                ForEach(0..<14, id: \.self) { i in
                    Circle()
                        .fill([Color.appPrimary, Color.warning, Color.success, Color.danger][i % 4])
                        .frame(width: CGFloat.random(in: 6...10), height: CGFloat.random(in: 6...10))
                        .offset(x: confettiOffsets[i].0, y: confettiOffsets[i].1)
                        .opacity(confettiVisible ? 0 : 1)
                        .animation(.easeOut(duration: 1.5).delay(Double(i) * 0.05), value: confettiVisible)
                }
            }

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.warningLight, Color.warningLight.opacity(0.3)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 70
                            )
                        )
                        .frame(width: 140, height: 140)

                    Text("🔥")
                        .font(.system(size: 64))
                }
                .scaleEffect(flameScale)

                Text("完美一天！")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .opacity(contentOpacity)

                Text("今日任务 \(TaskEngine.shared.totalCount)/\(TaskEngine.shared.totalCount) 全部完成")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.warning)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.warningLight, in: Capsule())
                    .opacity(contentOpacity)

                // 真实数字文案
                Text("🔥 连续 \(dataStore.streakDays) 天 · 累计听 \(dataStore.totalListeningTimeDisplay) · 掌握 \(vocabularyStore.strongWords.count) 个词")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(contentOpacity)

                if let teaser = nextMilestoneText {
                    Text(teaser)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .opacity(contentOpacity)
                }

                Spacer()

                VStack(spacing: 10) {
                    if isMilestoneDay {
                        Button(action: onShare) {
                            Text("炫耀一下")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    Button(action: onContinue) {
                        Text("继续学习")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isMilestoneDay ? Color.appPrimary : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                isMilestoneDay ? Color.clear : Color.appPrimary,
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
                .opacity(contentOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.15)) {
                flameScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                contentOpacity = 1.0
            }
            confettiVisible = true
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }
}
