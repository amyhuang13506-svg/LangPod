import SwiftUI

struct MemoryDetailView: View {
    @Environment(VocabularyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedState: MemoryState = .strong

    var body: some View {
        ZStack {
            Color(hex: "F7F8FC").ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color(hex: "94A3B8"))
                    }
                    Text("记忆状态")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(hex: "1E293B"))
                    Spacer()
                }

                // Tabs
                HStack(spacing: 8) {
                    ForEach(MemoryState.allCases, id: \.rawValue) { state in
                        memoryTab(state)
                    }
                    Spacer()
                }

                // Word list
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(wordsForState) { word in
                            memoryWordRow(word)
                        }

                        if wordsForState.isEmpty {
                            Text("暂无词汇")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "94A3B8"))
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

    private var wordsForState: [SavedWord] {
        switch selectedState {
        case .strong: store.strongWords
        case .fading: store.fadingWords
        case .forgetting: store.forgettingWords
        }
    }

    private func memoryTab(_ state: MemoryState) -> some View {
        let isSelected = selectedState == state
        let count: Int = switch state {
        case .strong: store.strongWords.count
        case .fading: store.fadingWords.count
        case .forgetting: store.forgettingWords.count
        }

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedState = state }
        } label: {
            Text("\(state.label) \(count)")
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : Color(hex: "64748B"))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color(hex: state.color) : Color(hex: "F1F5F9"),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func memoryWordRow(_ word: SavedWord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(word.word)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "1E293B"))
                Text(word.translationZh)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "94A3B8"))
            }
            Spacer()
            HStack(spacing: 6) {
                // Mini progress bar
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "E2E8F0"))
                        .frame(width: 60, height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: word.memoryState.color))
                        .frame(width: 60 * retentionRatio(word), height: 4)
                }
                Text("\(Int(retentionRatio(word) * 100))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: word.memoryState.color))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
        )
    }

    private func retentionRatio(_ word: SavedWord) -> CGFloat {
        let hoursSinceReview = Date().timeIntervalSince(word.lastReviewDate) / 3600
        // Retention window grows with review count
        let retentionHours: Double = switch word.reviewCount {
        case 0: 6.0
        case 1: 36.0
        case 2: 108.0
        case 3: 252.0
        case 4: 504.0
        default: 1080.0
        }
        let ratio = max(0, min(1, 1.0 - hoursSinceReview / retentionHours))
        return CGFloat(ratio)
    }
}

#Preview {
    MemoryDetailView()
        .environment(VocabularyStore())
}
