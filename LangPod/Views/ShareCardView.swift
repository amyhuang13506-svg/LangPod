import SwiftUI

struct ShareCardView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(\.dismiss) private var dismiss

    @State private var renderedImage: UIImage?

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // The shareable card
                cardContent
                    .padding(.horizontal, 32)

                // Buttons
                VStack(spacing: 10) {
                    Button {
                        saveToPhotos()
                    } label: {
                        Text("保存到相册")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
                    }

                    Button {
                        shareToWeChat()
                    } label: {
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

                // Close
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 44, height: 44)
                }
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(spacing: 0) {
            // Top section with gradient
            VStack(spacing: 20) {
                // Quote
                Text("\"每天 6 分钟\n不知不觉就坚持了 \(dataStore.streakDays) 天\"")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                // Big streak number
                HStack(spacing: 8) {
                    Text("🔥")
                        .font(.system(size: 28))
                    Text("\(dataStore.streakDays)天")
                        .font(.system(size: 36, weight: .bold))
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

            // Brand footer
            Text("Castlingo · 听播客，学英语")
                .font(.system(size: 11))
                .foregroundStyle(Color.textQuaternary)
                .padding(.vertical, 12)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.border, lineWidth: 1)
        )
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
    private func saveToPhotos() {
        let renderer = ImageRenderer(content: cardContent.frame(width: 340))
        renderer.scale = 3.0
        if let image = renderer.uiImage {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
    }

    private func shareToWeChat() {
        // Use system share sheet
        let renderer = ImageRenderer(content: cardContent.frame(width: 340))
        renderer.scale = 3.0
        guard let image = renderer.uiImage else { return }

        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

#Preview {
    ShareCardView()
        .environment(DataStore())
        .environment(VocabularyStore())
}
