import SwiftUI

struct ProfileView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(VocabularyStore.self) private var vocabularyStore
    @State private var showPaywall = false
    @State private var showShareCard = false
    @State private var showClearAlert = false

    var body: some View {
        ZStack {
            Color(hex: "F7F8FC").ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Title
                    Text("我的")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(hex: "1E293B"))
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
                    Text("LangPod v1.0.0")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "CBD5E1"))
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
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
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "DBEAFE"), Color(hex: "EFF6FF")],
                            center: .center,
                            startRadius: 0,
                            endRadius: 26
                        )
                    )
                    .frame(width: 52, height: 52)
                Image(systemName: "headphones")
                    .font(.system(size: 24))
                    .foregroundStyle(Color(hex: "3B82F6"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("英语学习者")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "1E293B"))

                HStack(spacing: 6) {
                    Text("Lv.\(dataStore.listeningLevel.rawValue) \(dataStore.listeningLevel.name)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "3B82F6"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(hex: "EFF6FF"), in: RoundedRectangle(cornerRadius: 6))

                    Text("Pro")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "92400E"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(hex: "FEF3C7"), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            Spacer()
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
        )
    }

    // MARK: - Learning Settings

    private var settingsSection: some View {
        VStack(spacing: 0) {
            settingsRow(icon: "antenna.radiowaves.left.and.right", iconColor: "3B82F6",
                        title: "当前级别", value: dataStore.selectedLevel.tabName)
            divider
            settingsRow(icon: "globe", iconColor: "3B82F6",
                        title: "翻译语言", value: "中文")
            divider
            settingsRow(icon: "bell", iconColor: "3B82F6",
                        title: "每日提醒", value: "08:30")
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
        )
    }

    // MARK: - Other Section

    private var otherSection: some View {
        VStack(spacing: 0) {
            Button { showPaywall = true } label: {
                menuRow(icon: "crown", iconColor: "F59E0B", title: "升级 Pro")
            }
            divider
            menuRow(icon: "trophy", iconColor: "94A3B8", title: "成就徽章")
            divider
            Button { showShareCard = true } label: {
                menuRow(icon: "square.and.arrow.up", iconColor: "94A3B8", title: "分享给朋友")
            }
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
        )
    }

    // MARK: - Legal Section

    private var legalSection: some View {
        VStack(spacing: 0) {
            Link(destination: URL(string: "https://langpod.com/privacy")!) {
                menuRow(icon: "shield", iconColor: "94A3B8", title: "隐私政策")
            }
            divider
            Link(destination: URL(string: "https://langpod.com/terms")!) {
                menuRow(icon: "doc.text", iconColor: "94A3B8", title: "用户协议")
            }
            divider
            Button { showClearAlert = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hex: "EF4444"))
                    Text("清除所有数据")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: "EF4444"))
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
                .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
        )
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
                    .foregroundStyle(Color(hex: "1E293B"))
            }
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "94A3B8"))
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
                    .foregroundStyle(Color(hex: "1E293B"))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "CBD5E1"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(hex: "F1F5F9"))
            .frame(height: 1)
    }

    // MARK: - Actions

    private func clearAllData() {
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        dataStore.hasCompletedOnboarding = false
    }
}

#Preview {
    ProfileView()
        .environment(DataStore())
        .environment(VocabularyStore())
}
