import SwiftUI

struct MasteryDetailView: View {
    @Environment(VocabularyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLevel: MasteryLevel = .heard

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }
                    Text("掌握深度")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                }

                // Tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MasteryLevel.allCases, id: \.rawValue) { level in
                            masteryTab(level)
                        }
                    }
                }

                // Description
                Text(descriptionFor(selectedLevel))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appPrimary)
                    .lineSpacing(4)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primaryLight, in: RoundedRectangle(cornerRadius: 12))

                // Word list
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(store.wordsByMastery(selectedLevel)) { word in
                            wordRow(word)
                        }

                        if store.wordsByMastery(selectedLevel).isEmpty {
                            Text("暂无词汇")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.textTertiary)
                                .padding(.top, 40)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 62)
            .padding(.bottom, 24)
        }
    }

    private func masteryTab(_ level: MasteryLevel) -> some View {
        let isSelected = selectedLevel == level
        let count = store.wordsByMastery(level).count

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedLevel = level }
        } label: {
            Text("\(level.icon) \(level.label) \(count)")
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : Color.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color.appPrimary : Color.divider,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func wordRow(_ word: SavedWord) -> some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.appPrimary)
                Text(word.word)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            Spacer()
            Text(word.translationZh)
                .font(.system(size: 13))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    private func descriptionFor(_ level: MasteryLevel) -> String {
        switch level {
        case .heard:
            "\"听懂\" = 在播客里听到这个词时能理解意思，但还不能主动使用。继续听更多包含这些词的播客来加深印象。"
        case .recognized:
            "\"认出\" = 看到这个词能选对正确释义。通过词义配对游戏可以达到这个层级。"
        case .canUse:
            "\"会用\" = 能用这个词造出正确的句子。通过费曼挑战可以达到这个层级。"
        case .canTeach:
            "\"能教\" = 能用自己的话解释这个词的意思，是最高层级的掌握。"
        }
    }
}

#Preview {
    MasteryDetailView()
        .environment(VocabularyStore())
}
