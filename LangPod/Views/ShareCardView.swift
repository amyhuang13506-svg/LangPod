import SwiftUI

struct ShareCardView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(\.dismiss) private var dismiss

    @State private var showSavedToast = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Preview of the shareable card (on-screen only)
                cardContent
                    .padding(.horizontal, 32)

                // Buttons
                VStack(spacing: 10) {
                    Button { saveToPhotos() } label: {
                        Text("保存到相册")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
                    }

                    Button { shareToWeChat() } label: {
                        Text("分享到朋友圈")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.border, lineWidth: 1)
                            )
                    }
                }
                .padding(.top, 20)
                .padding(.horizontal, 32)

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 44, height: 44)
                }
                .padding(.bottom, 20)
            }

            // Save success toast
            if showSavedToast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.success)
                        Text("已保存到相册")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
                    .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Card Content (on-screen preview)

    private var cardContent: some View {
        VStack(spacing: 0) {
            mainCardBody
            brandFooter
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    // MARK: - Shareable Image (rendered for export — includes background + download CTA)

    private var shareableImage: some View {
        VStack(spacing: 0) {
            // Branded gradient background with the card inside
            VStack(spacing: 0) {
                Spacer().frame(height: 32)

                // Card with rounded corners on top of gradient
                VStack(spacing: 0) {
                    mainCardBody
                    brandFooter
                }
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
                .padding(.horizontal, 20)

                Spacer().frame(height: 20)

                // Download CTA
                HStack(spacing: 10) {
                    // App icon
                    Image(systemName: "headphones")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "3B82F6"), Color(hex: "6366F1")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 8)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Castlingo")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: "1E293B"))
                        Text("App Store 搜索下载")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "94A3B8"))
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 24)
            }
            .background(
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "DBEAFE"), location: 0),
                        .init(color: Color(hex: "EEF2FF"), location: 0.4),
                        .init(color: Color(hex: "F7F8FC"), location: 0.7),
                        .init(color: Color(hex: "FFFFFF"), location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
    }

    // MARK: - Card Subviews (shared between preview and export)

    private var mainCardBody: some View {
        VStack(spacing: 20) {
            // Hook copy — 方案 A
            VStack(spacing: 6) {
                Text("不背单词，不做题")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("光听就学会了 \(vocabularyStore.totalCount) 个英语词汇")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            .multilineTextAlignment(.center)

            // Big streak
            HStack(spacing: 8) {
                Text("🔥")
                    .font(.system(size: 28))
                Text("连续 \(dataStore.streakDays) 天")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .tracking(-1)
            }

            // Badges
            HStack(spacing: 8) {
                badgePill("Lv.\(dataStore.listeningLevel.rawValue) \(dataStore.listeningLevel.name)", bg: "EFF6FF", text: "3B82F6")
                badgePill("\(vocabularyStore.totalCount) 词", bg: "F0FDF4", text: "16A34A")
                badgePill(dataStore.totalListeningTimeDisplay, bg: "FEF3C7", text: "92400E")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.primaryLighter, .white],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var brandFooter: some View {
        Text("Castlingo · 听播客，学英语")
            .font(.system(size: 11))
            .foregroundStyle(Color.textQuaternary)
            .padding(.vertical, 12)
    }

    private func badgePill(_ text: String, bg: String, text textColor: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(hex: textColor))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(hex: bg), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    @MainActor
    private func renderShareImage() -> UIImage? {
        let renderer = ImageRenderer(content: shareableImage.frame(width: 380))
        renderer.scale = 3.0
        return renderer.uiImage
    }

    @MainActor
    private func saveToPhotos() {
        guard let image = renderShareImage() else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation { showSavedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSavedToast = false }
        }
    }

    private func shareToWeChat() {
        guard let image = renderShareImage() else { return }

        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            activityVC.popoverPresentationController?.sourceView = topVC.view
            topVC.present(activityVC, animated: true)
        }
    }
}

#Preview {
    ShareCardView()
        .environment(DataStore())
        .environment(VocabularyStore())
}
