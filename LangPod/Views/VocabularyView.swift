import SwiftUI

enum VocabFilter: String, CaseIterable {
    case all
    case strong
    case fading
    case new
}

struct VocabularyView: View {
    @Environment(VocabularyStore.self) private var store
    @State private var showWordMatch = false
    @State private var showFeynman = false
    @State private var filter: VocabFilter = .all
    @State private var showClearAlert = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: "F7F8FC").ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                    statsCards
                    wordList
                }
                .padding(.top, 16)
                .padding(.bottom, 140)
            }

            // Fixed bottom CTAs
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color(hex: "F7F8FC").opacity(0), Color(hex: "F7F8FC")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 16)

                practiceCTAs
                    .padding(.bottom, 16)
                    .background(Color(hex: "F7F8FC"))
            }
        }
        .fullScreenCover(isPresented: $showWordMatch) {
            WordMatchView()
        }
        .fullScreenCover(isPresented: $showFeynman) {
            FeynmanChallengeView()
        }
        .alert("清除已掌握词汇", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) {}
            Button("清零", role: .destructive) {
                withAnimation {
                    store.clearMasteredWords()
                }
            }
        } message: {
            Text("将 \(store.strongWords.count) 个已掌握的词移出词汇本。这些词你已经学会了！")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("我的词汇")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color(hex: "1E293B"))
                .tracking(-0.5)

            Spacer()

            Text("\(store.totalCount) 个词")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "3B82F6"))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: "EFF6FF"), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Stats Cards (tappable filters)

    private var statsCards: some View {
        HStack(spacing: 10) {
            filterCard(
                filter: .strong,
                count: store.strongWords.count,
                label: "已掌握",
                textColor: Color(hex: "16A34A"),
                bgColor: Color(hex: "DCFCE7"),
                activeBorder: Color(hex: "22C55E")
            )
            filterCard(
                filter: .fading,
                count: store.fadingWords.count,
                label: "复习中",
                textColor: Color(hex: "D97706"),
                bgColor: Color(hex: "FEF3C7"),
                activeBorder: Color(hex: "F59E0B")
            )
            filterCard(
                filter: .new,
                count: newWords.count,
                label: "新词",
                textColor: Color(hex: "3B82F6"),
                bgColor: Color(hex: "EFF6FF"),
                activeBorder: Color(hex: "3B82F6")
            )
        }
        .padding(.horizontal, 24)
    }

    private func filterCard(filter f: VocabFilter, count: Int, label: String, textColor: Color, bgColor: Color, activeBorder: Color) -> some View {
        let isActive = filter == f

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                filter = filter == f ? .all : f
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(count)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(textColor)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(textColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(bgColor, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isActive ? activeBorder : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Word List

    private var filteredWords: [SavedWord] {
        switch filter {
        case .all: store.words
        case .strong: store.strongWords
        case .fading: store.fadingWords
        case .new: newWords
        }
    }

    private var newWords: [SavedWord] {
        store.forgettingWords + store.words.filter { $0.reviewCount == 0 && $0.memoryState != .forgetting }
    }

    private var sectionTitle: String {
        switch filter {
        case .all: "全部词汇"
        case .strong: "已掌握"
        case .fading: "复习中"
        case .new: "新词"
        }
    }

    private var wordList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sectionTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "1E293B"))

                Spacer()
                if filter == .strong && !filteredWords.isEmpty {
                    Button { showClearAlert = true } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: "EF4444"))
                                .frame(width: 6, height: 6)
                            Text("清零")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Color(hex: "EF4444"))
                    }
                } else if filter == .strong && filteredWords.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                        Text("已清零")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color(hex: "22C55E"))
                } else if filter != .all {
                    Button {
                        withAnimation { filter = .all }
                    } label: {
                        Text("查看全部")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "3B82F6"))
                    }
                }
            }

            if filteredWords.isEmpty {
                Text("暂无词汇")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "94A3B8"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(filteredWords) { word in
                    wordRow(word)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private func wordRow(_ word: SavedWord) -> some View {
        HStack(spacing: 12) {
            // Play button
            Button { } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "3B82F6"))
            }

            // Word + phonetic
            VStack(alignment: .leading, spacing: 2) {
                Text(word.word)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "1E293B"))
                Text(word.phonetic)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "94A3B8"))
            }

            Spacer()

            Text(word.translationZh)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "64748B"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
        )
    }

    // MARK: - Practice CTAs

    private var practiceCTAs: some View {
        HStack(spacing: 12) {
            Button { showWordMatch = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 15))
                    Text("单词配对")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(hex: "3B82F6"), in: RoundedRectangle(cornerRadius: 14))
            }

            Button { showFeynman = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.word.spacing")
                        .font(.system(size: 15))
                    Text("连词成句")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(hex: "F59E0B"), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    VocabularyView()
        .environment(VocabularyStore())
}
