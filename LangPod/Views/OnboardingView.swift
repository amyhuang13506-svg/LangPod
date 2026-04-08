import SwiftUI

struct OnboardingView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var currentPage: OnboardingPage = .welcome

    enum OnboardingPage {
        case welcome
        case levelSelect
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            switch currentPage {
            case .welcome:
                welcomePage
            case .levelSelect:
                levelSelectPage
            }
        }
    }

    // MARK: - Welcome Page

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 180)

            // Illustration circle
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "E0F2FE"), Color.primaryLighter],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)

                Image(systemName: "headphones")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.appPrimary)
            }

            // Content
            VStack(spacing: 12) {
                Text("Castlingo")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .tracking(-0.5)

                Text("600小时，听会一门语言")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.bodyText)

                Text("源于FSI外交官训练，重复即本能")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.top, 32)
            .padding(.horizontal, 32)

            Spacer()

            // Button area
            VStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentPage = .levelSelect
                    }
                } label: {
                    Text("开始使用")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 16))
                }



            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Level Select Page

    @State private var selectedLevel: PodcastLevel = .easy

    private var levelSelectPage: some View {
        VStack(spacing: 24) {
            // Title
            VStack(alignment: .leading, spacing: 8) {
                Text("选择你的英语水平")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Text("我们会根据你的水平推荐合适的播客")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Level cards
            VStack(spacing: 12) {
                levelCard(
                    level: .easy,
                    dotFill: Color.success,
                    name: "初级",
                    desc: "简单日常对话，慢速播放",
                    dotColor: Color.successLight
                )
                levelCard(
                    level: .medium,
                    dotFill: Color.appPrimary,
                    name: "中级",
                    desc: "生活、文化、旅行话题",
                    dotColor: Color.primaryLighter
                )
                levelCard(
                    level: .hard,
                    dotFill: Color.hardOrange,
                    name: "高级",
                    desc: "新闻、商务、深度话题",
                    dotColor: Color.warningLight
                )
            }

            Spacer()

            // Continue button
            Button {
                dataStore.selectedLevel = selectedLevel
                dataStore.hasCompletedOnboarding = true
            } label: {
                Text("继续")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.top, 62)
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    private func levelCard(level: PodcastLevel, dotFill: Color, name: String, desc: String, dotColor: Color) -> some View {
        let isSelected = selectedLevel == level
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedLevel = level
            }
        } label: {
            HStack(spacing: 14) {
                // Color dot
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(dotColor)
                        .frame(width: 40, height: 40)
                    Circle()
                        .fill(dotFill)
                        .frame(width: 14, height: 14)
                }

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(desc)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer()

                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.appPrimary)
                }
            }
            .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.appPrimary : Color.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingView()
        .environment(DataStore())
}
