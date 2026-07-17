import SwiftUI

struct ProfileView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(SentenceStore.self) private var sentenceStore
    @Environment(AudioPlayer.self) private var audioPlayer
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(AppState.self) private var appState
    @State private var showPaywall = false
    @State private var showShareCard = false
    @State private var showClearAlert = false
    @State private var reminderTime = {
        let saved = UserDefaults.standard.integer(forKey: "reminderHour")
        var components = DateComponents()
        components.hour = saved > 0 ? saved : 8
        components.minute = UserDefaults.standard.integer(forKey: "reminderMinute")
        return Calendar.current.date(from: components) ?? Date()
    }()

    private var appVersionDisplay: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Title
                    Text("我的")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .tracking(-0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Profile card
                    profileCard

                    // 学习计划卡：onboarding 生成的专属计划常驻入口 + 累计活跃进度
                    planCard

                    // 战绩区：Streak 卡（带今日任务进度环，点击重开任务弹窗）+ 本周进度 + 三格统计
                    streakCard
                    weekProgress
                    statsRow

                    // 设置 · 功能 · 法律（合并为一个大框）
                    settingsSection

                    // 清除数据（+ 开发者选项）
                    legalSection

                    #if DEBUG
                    debugTaskSection
                    #endif

                    // Version
                    Text("Castlingo v\(appVersionDisplay)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textQuaternary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
                .environment(subscriptionManager)
        }
        .fullScreenCover(isPresented: $showShareCard) {
            ShareCardView()
        }
        .alert("清除所有数据", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) { clearAllData() }
        } message: {
            Text("这将清除所有学习记录、词汇和设置。此操作不可撤销。")
        }
        .navigationBarHidden(true)
        } // NavigationStack
    }

    // MARK: - Profile Card

    // MARK: - 学习计划卡

    /// 计划来自 onboarding 落盘答案；级别跟随 dataStore.selectedLevel（用户改级别自动变）。
    private var plan: LearningPlan {
        LearningPlan.persisted(level: dataStore.selectedLevel)
    }

    /// 进度提示：距离下一个里程碑还有几天；全部达成 → 完成态。
    private var planProgressCaption: String {
        let days = dataStore.activeDays
        if let next = plan.nextMilestone(activeDays: days) {
            return "累计活跃 \(days) 天 · 还有 \(next.day - days) 天到「\(next.title)」"
        }
        return "累计活跃 \(days) 天 · 90 天里程碑全部达成 🎉"
    }

    /// 「我的学习计划」卡：整卡可点，进计划详情页。累计活跃 ≠ streakCard 的连续天数。
    private var planCard: some View {
        NavigationLink {
            LearningPlanPage()
                .environment(dataStore)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("我的学习计划")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textQuaternary)
                }

                HStack(spacing: 8) {
                    ForEach(plan.chips, id: \.self) { PlanChip($0) }
                }

                PlanProgressBar(activeDays: dataStore.activeDays)

                Text(planProgressCaption)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            Analytics.track(.planCardTap, params: [
                "active_days": "\(dataStore.activeDays)",
                "goal": plan.goal?.rawValue ?? "none"
            ])
        })
    }

    // MARK: - 战绩区（从旧 StatsView 恢复：streakCard + statsRow + weekProgress）

    /// Streak 卡：🔥 + 连续天数 + 状态文案 + 今日任务进度环。点击 → 重开任务清单弹窗（二次入口）。
    private var streakCard: some View {
        Button {
            Analytics.track(.dailyTaskEntryTap, params: ["source": "profile_card"])
            Analytics.track(.dailyTaskPopupView)
            TaskEngine.shared.ensureTodayRecord()
            withAnimation(.easeOut(duration: 0.25)) { appState.showDailyTasks = true }
        } label: {
            VStack(spacing: 8) {
                HStack {
                    Text("🔥")
                        .font(.system(size: 28))
                        .opacity(listenedToday ? 1 : 0.4)
                    Text("连续 \(dataStore.streakDays) 天")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    // 全部完成后进度环整个隐藏；只在还有未完成任务时显示
                    if TaskEngine.shared.completedCount < TaskEngine.shared.totalCount {
                        taskProgressRing
                    }
                }

                HStack {
                    Text(streakMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(streakColor)
                    Spacer()
                }

                // Degradation warning
                if daysSinceLastListen >= 5 {
                    HStack {
                        Text("再不回来等级要降了")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.danger)
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
            .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(streakBorderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// 今日任务进度环（仅在还有未完成任务时显示；全部完成后调用处会整个隐藏）
    private var taskProgressRing: some View {
        let done = TaskEngine.shared.completedCount
        let total = max(TaskEngine.shared.totalCount, 1)
        return ZStack {
            Circle()
                .stroke(Color.border, lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(done) / CGFloat(total))
                .stroke(Color.appPrimary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(done)/\(total)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.appPrimary)
        }
        .frame(width: 40, height: 40)
    }

    private var daysSinceLastListen: Int {
        guard let last = dataStore.lastListenDate else { return 999 }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 999
    }

    private var listenedToday: Bool {
        guard let last = dataStore.lastListenDate else { return false }
        return Calendar.current.isDateInToday(last)
    }

    private var hoursUntilReset: Int {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) else { return 0 }
        return max(0, Int(tomorrow.timeIntervalSinceNow / 3600))
    }

    private var streakMessage: String {
        if listenedToday {
            let done = TaskEngine.shared.completedCount
            let total = TaskEngine.shared.totalCount
            if total > 0 && done >= total { return "完美一天！\(total) 个任务全部完成" }
            return "今日已点亮！完成 \(done)/\(total) 任务解锁完美一天"
        }
        if hoursUntilReset <= 3 {
            return "即将清零！还有 \(hoursUntilReset)h"
        }
        return "今天还没听！\(hoursUntilReset)h 后记录清零"
    }

    private var streakColor: Color {
        if listenedToday { return Color.success }
        if hoursUntilReset <= 3 { return Color.danger }
        return Color.warning
    }

    private var streakBorderColor: Color {
        if listenedToday { return Color.success.opacity(0.3) }
        if hoursUntilReset <= 3 { return Color.danger.opacity(0.3) }
        return Color.border
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(value: dataStore.totalListeningTimeDisplay, label: "学习时长")
            statCard(value: "\(vocabularyStore.strongWords.count)", label: "掌握词汇")
            statCard(value: "\(sentenceStore.strongSentences.count)", label: "掌握句型")
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    // MARK: - Week Progress（组件与任务清单弹窗共用）

    private var weekProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本周进度")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            TaskWeekProgressView()
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    #if DEBUG
    // MARK: - Debug · 每日任务（仅开发版，release 包里不出现）

    private var debugTaskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🐛 Debug · 每日任务")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.textSecondary)

            Text("今日 \(TaskEngine.shared.completedCount)/\(TaskEngine.shared.totalCount)：\(taskDebugSummary)")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            debugButton("完成下一格（测横条 / 火苗）") {
                TaskEngine.shared.debugCompleteNext()
            }
            debugButton("完成全部（测 4/4 庆祝）") {
                TaskEngine.shared.debugCompleteAll()
            }
            debugButton("重置今日任务（清弹窗标记）") {
                TaskEngine.shared.debugResetToday()
            }
            debugButton("打开任务弹窗") {
                appState.showDailyTasks = true
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.warningLight.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.warning.opacity(0.4), lineWidth: 1)
        )
    }

    private var taskDebugSummary: String {
        TaskEngine.shared.todayTasks
            .map { "\($0.type.title)\($0.done ? "✓" : "")" }
            .joined(separator: " · ")
    }

    private func debugButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
    #endif

    private var profileCard: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.primaryLighter, Color.primaryLight],
                            center: .center,
                            startRadius: 0,
                            endRadius: 26
                        )
                    )
                    .frame(width: 52, height: 52)
                Image(systemName: "headphones")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.appPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Explorer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                HStack(spacing: 6) {
                    Text("Lv.\(dataStore.listeningLevel.rawValue) \(dataStore.listeningLevel.name)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.appPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.primaryLight, in: RoundedRectangle(cornerRadius: 6))

                    if subscriptionManager.isProUser {
                        Text("Pro")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.gold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.warningLight, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            Spacer()
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    // MARK: - Learning Settings

    private var reminderTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: reminderTime)
    }

    private var sleepTimerDisplayValue: String {
        if let minutes = audioPlayer.sleepTimerMinutes {
            return "\(minutes)分钟"
        }
        return "关闭"
    }

    private var settingsSection: some View {
        VStack(spacing: 0) {
            // 升级 Pro（放最前）
            if subscriptionManager.isProUser {
                menuRow(icon: "crown.fill", iconColor: "F59E0B", title: "已订阅 Pro")
            } else {
                Button { showPaywall = true } label: {
                    menuRow(icon: "crown", iconColor: "F59E0B", title: "升级 Pro")
                }
            }
            divider
            NavigationLink {
                LevelSelectPage(dataStore: dataStore)
            } label: {
                settingsRow(icon: "antenna.radiowaves.left.and.right", iconColor: "3B82F6",
                            title: "当前级别", value: dataStore.selectedLevel.tabName)
            }
            divider
            NavigationLink {
                SleepTimerPage(audioPlayer: audioPlayer)
            } label: {
                settingsRow(icon: "moon.zzz", iconColor: "8B5CF6",
                            title: "定时播放", value: sleepTimerDisplayValue)
            }
            divider
            NavigationLink {
                AchievementsPage()
                    .environment(dataStore)
                    .environment(vocabularyStore)
            } label: {
                menuRow(icon: "trophy", iconColor: "94A3B8", title: "成就徽章")
            }
            divider
            Button { showShareCard = true } label: {
                menuRow(icon: "square.and.arrow.up", iconColor: "94A3B8", title: "分享给朋友")
            }
            divider
            if let privacyURL = URL(string: "https://amyhuang13506-svg.github.io/LangPod/docs/privacy.html") {
                Link(destination: privacyURL) {
                    menuRow(icon: "shield", iconColor: "94A3B8", title: "隐私政策")
                }
            }
            divider
            if let termsURL = URL(string: "https://amyhuang13506-svg.github.io/LangPod/docs/terms.html") {
                Link(destination: termsURL) {
                    menuRow(icon: "doc.text", iconColor: "94A3B8", title: "用户协议")
                }
            }
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    // MARK: - Legal Section

    private var legalSection: some View {
        VStack(spacing: 20) {
            VStack(spacing: 0) {
                Button { showClearAlert = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.danger)
                        Text("清除所有数据")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.danger)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.border, lineWidth: 1)
            )

            #if DEBUG
            // Dev toggles for Paywall state testing
            VStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { subscriptionManager.mockProEnabled },
                    set: { subscriptionManager.mockProEnabled = $0 }
                )) {
                    HStack(spacing: 10) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(hex: "8B5CF6"))
                        Text("[DEV] Mock Pro")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: "8B5CF6"))
                    }
                }
                .tint(Color(hex: "8B5CF6"))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                divider

                Toggle(isOn: Binding(
                    get: { subscriptionManager.mockHasTrialEnabled },
                    set: { subscriptionManager.mockHasTrialEnabled = $0 }
                )) {
                    HStack(spacing: 10) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(hex: "8B5CF6"))
                        Text("[DEV] Mock Trial (Paywall)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: "8B5CF6"))
                    }
                }
                .tint(Color(hex: "8B5CF6"))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "8B5CF6").opacity(0.3), lineWidth: 1)
            )
            #endif
        }
    }

    // MARK: - Row Helpers

    private func settingsRow(icon: String, iconColor: String, title: String, value: String) -> some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: iconColor))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
            }
            Spacer()
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textQuaternary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func menuRow(icon: String, iconColor: String, title: String) -> some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: iconColor))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Color.textQuaternary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(height: 1)
    }

    // MARK: - Actions

    private func clearAllData() {
        guard let domain = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: domain)
        // domain 已清盘，但内存里的 @Observable 值还在、下次写入会重新落盘。
        // 显式归零累计活跃天数，避免清数据后新账号继承旧进度（seed 只在 init 跑，不重启不会重种）。
        dataStore.activeDays = 0
        dataStore.hasCompletedOnboarding = false
    }
}

// MARK: - Level Select Page

struct LevelSelectPage: View {
    @Environment(\.dismiss) private var dismiss
    var dataStore: DataStore

    var body: some View {
        List {
            ForEach([PodcastLevel.easy, .medium, .hard], id: \.self) { level in
                Button {
                    dataStore.selectedLevel = level
                    dataStore.loadEpisodes()
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: level == .easy ? "22C55E" : level == .medium ? "3B82F6" : "EF4444"))
                            .frame(width: 10, height: 10)
                        Text(level.tabName)
                            .font(.system(size: 16))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        if dataStore.selectedLevel == level {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.appPrimary)
                        }
                    }
                }
            }
        }
        .navigationTitle("选择级别")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Language Select Page

struct LanguageSelectPage: View {
    var body: some View {
        List {
            HStack(spacing: 12) {
                Text("中文")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
            }
        }
        .navigationTitle("翻译语言")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Reminder Time Page

struct ReminderTimePage: View {
    @Binding var reminderTime: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            DatePicker("", selection: $reminderTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()

            Button {
                let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                UserDefaults.standard.set(components.hour ?? 8, forKey: "reminderHour")
                UserDefaults.standard.set(components.minute ?? 30, forKey: "reminderMinute")
                // Triggers LangPodApp to re-arbitrate tomorrow's notification at the new time.
                NotificationCenter.default.post(name: .reminderTimeChanged, object: nil)
                dismiss()
            } label: {
                Text("保存")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .navigationTitle("每日提醒")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SleepTimerPage: View {
    var audioPlayer: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    private let options: [(label: String, minutes: Int?)] = [
        ("15 分钟", 15),
        ("30 分钟", 30),
        ("60 分钟", 60),
        ("关闭", nil),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(options, id: \.label) { option in
                let isSelected = audioPlayer.sleepTimerMinutes == option.minutes
                Button {
                    if let minutes = option.minutes {
                        audioPlayer.setSleepTimer(minutes)
                    } else {
                        audioPlayer.cancelSleepTimer()
                    }
                } label: {
                    HStack {
                        Text(option.label)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.appPrimary)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if option.label != options.last?.label {
                    Divider().padding(.leading, 24)
                }
            }

            if let remaining = audioPlayer.sleepTimerRemainingText {
                Text("剩余 \(remaining)")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.top, 20)
            }

            Spacer()
        }
        .padding(.top, 16)
        .navigationTitle("定时播放")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ProfileView()
        .environment(DataStore())
        .environment(VocabularyStore())
        .environment(AudioPlayer())
        .environment(SubscriptionManager())
}
