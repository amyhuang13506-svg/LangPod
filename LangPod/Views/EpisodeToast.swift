import SwiftUI

struct EpisodeToast: View {
    let title: String
    let wordCount: Int
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.success)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\"\(title)\" 已完成")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text("已保存 \(wordCount) 个新词 · 即将播放下一集")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer()
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
