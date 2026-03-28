import SwiftUI

struct LevelUpView: View {
    let level: ListeningLevel
    let episodesCompleted: Int
    let wordsLearned: Int
    var onShare: () -> Void
    var onContinue: () -> Void

    @State private var badgeScale: CGFloat = 0
    @State private var contentOpacity: Double = 0

    var body: some View {
        ZStack {
            Color(hex: "F7F8FC").ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Level badge
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "DBEAFE"), Color(hex: "EFF6FF")],
                                center: .center,
                                startRadius: 0,
                                endRadius: 60
                            )
                        )
                        .frame(width: 120, height: 120)

                    Text("Lv.\(level.rawValue)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Color(hex: "3B82F6"))
                }
                .scaleEffect(badgeScale)

                // Title
                Text("恭喜升级！")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(hex: "1E293B"))
                    .opacity(contentOpacity)

                // Level name
                Text("🎉 \(level.name)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "3B82F6"))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color(hex: "EFF6FF"), in: Capsule())
                    .opacity(contentOpacity)

                // Description
                Text("你已经听完 \(episodesCompleted) 集播客\n掌握了 \(wordsLearned) 个单词")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "64748B"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .opacity(contentOpacity)

                // Unlock info
                if let unlock = level.unlockDescription {
                    VStack(spacing: 8) {
                        Text("🔓 已解锁")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: "16A34A"))
                        Text(unlock)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: "16A34A"))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: "F0FDF4"), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(hex: "22C55E").opacity(0.27), lineWidth: 1)
                    )
                    .padding(.horizontal, 32)
                    .opacity(contentOpacity)
                }

                Spacer()

                // Buttons
                VStack(spacing: 10) {
                    Button(action: onShare) {
                        Text("炫耀一下")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(hex: "3B82F6"), in: RoundedRectangle(cornerRadius: 14))
                    }

                    Button(action: onContinue) {
                        Text("继续学习")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: "3B82F6"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
                .opacity(contentOpacity)
            }
        }
        .onAppear { startAnimation() }
    }

    private func startAnimation() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
            badgeScale = 1.0
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
            contentOpacity = 1.0
        }
    }
}

#Preview {
    LevelUpView(
        level: .lv3,
        episodesCompleted: 15,
        wordsLearned: 60,
        onShare: {},
        onContinue: {}
    )
}
