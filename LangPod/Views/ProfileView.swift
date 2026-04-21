import SwiftUI

struct ProfileView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(AudioPlayer.self) private var audioPlayer
    @Environment(SubscriptionManager.self) private var subscriptionManager
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

                    // Learning settings
                    settingsSection

                    // Other
                    otherSection

                    // Legal
                    legalSection

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
            NavigationLink {
                LevelSelectPage(dataStore: dataStore)
            } label: {
                settingsRow(icon: "antenna.radiowaves.left.and.right", iconColor: "3B82F6",
                            title: "当前级别", value: dataStore.selectedLevel.tabName)
            }
            divider
            NavigationLink {
                LanguageSelectPage()
            } label: {
                settingsRow(icon: "globe", iconColor: "3B82F6",
                            title: "翻译语言", value: "中文")
            }
            divider
            NavigationLink {
                ReminderTimePage(reminderTime: $reminderTime)
            } label: {
                settingsRow(icon: "bell", iconColor: "3B82F6",
                            title: "每日提醒", value: reminderTimeString)
            }
            divider
            NavigationLink {
                SleepTimerPage(audioPlayer: audioPlayer)
            } label: {
                settingsRow(icon: "moon.zzz", iconColor: "8B5CF6",
                            title: "定时停止", value: sleepTimerDisplayValue)
            }
            divider
            patternPlaybackToggle
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    private var patternPlaybackToggle: some View {
        HStack(spacing: 12) {
            Image(systemName: "quote.bubble.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color(hex: "14B8A6"), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("句型混播")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                Text("播完一集后自动接这集的句型讲解")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { audioPlayer.playPatternsAlongside },
                set: { newValue in
                    audioPlayer.playPatternsAlongside = newValue
                    audioPlayer.rebuildQueueAfterSettingChange()
                }
            ))
            .labelsHidden()
            .tint(Color.appPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }


    // MARK: - Other Section

    private var otherSection: some View {
        VStack(spacing: 0) {
            if subscriptionManager.isProUser {
                menuRow(icon: "crown.fill", iconColor: "F59E0B", title: "已订阅 Pro")
            } else {
                Button { showPaywall = true } label: {
                    menuRow(icon: "crown", iconColor: "F59E0B", title: "升级 Pro")
                }
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
                divider
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
        .navigationTitle("定时停止")
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
