import SwiftUI

struct FeynmanChallengeView: View {
    @Environment(VocabularyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex = 0
    @State private var challengeWords: [SavedWord] = []
    @State private var completed = false

    // Sentence building
    @State private var availableTokens: [WordToken] = []
    @State private var selectedTokens: [WordToken] = []
    @State private var answerState: AnswerState = .building
    @State private var correctSentence = ""

    enum AnswerState {
        case building
        case correct
        case wrong
    }

    struct WordToken: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        ZStack {
            Color(hex: "F7F8FC").ignoresSafeArea()

            if completed {
                completedContent
            } else if challengeWords.isEmpty {
                emptyContent
            } else {
                challengeContent
            }
        }
        .onAppear { loadWords() }
    }

    // MARK: - Challenge Content

    private var challengeContent: some View {
        let word = challengeWords[currentIndex]

        return VStack(spacing: 20) {
            // Header
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(hex: "94A3B8"))
                }
                Spacer()
                Text("组词造句")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: "1E293B"))
                Spacer()
                Text("\(currentIndex + 1)/\(challengeWords.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "3B82F6"))
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "E2E8F0"))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "3B82F6"))
                        .frame(width: geo.size.width * CGFloat(currentIndex + 1) / CGFloat(challengeWords.count), height: 4)
                }
            }
            .frame(height: 4)

            // Word card
            VStack(spacing: 8) {
                Text(word.word)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(hex: "1E293B"))
                Text(word.phonetic)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "94A3B8"))
                Text(word.translationZh)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "3B82F6"))
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
            )

            // Prompt
            Text("用这个词组成正确的句子：")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: "64748B"))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Answer area — selected tokens
            answerArea

            // Available tokens to pick from
            tokenPool

            Spacer()

            // Bottom button
            bottomButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    // MARK: - Answer Area

    private var answerArea: some View {
        let borderColor: Color = switch answerState {
        case .building: Color(hex: "E2E8F0")
        case .correct: Color(hex: "22C55E")
        case .wrong: Color(hex: "EF4444")
        }

        let bgColor: Color = switch answerState {
        case .building: Color.white
        case .correct: Color(hex: "F0FDF4")
        case .wrong: Color(hex: "FEF2F2")
        }

        return VStack(spacing: 8) {
            FlowLayout(spacing: 8) {
                ForEach(selectedTokens) { token in
                    Button {
                        if answerState == .building {
                            removeToken(token)
                        }
                    } label: {
                        Text(token.text)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color(hex: "1E293B"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(hex: "EFF6FF"), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }

            if selectedTokens.isEmpty {
                Text("点击下方单词组成句子")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "CBD5E1"))
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .padding(14)
        .background(bgColor, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: answerState == .building ? 1 : 2)
        )
    }

    // MARK: - Token Pool

    private var tokenPool: some View {
        FlowLayout(spacing: 8) {
            ForEach(availableTokens) { token in
                Button {
                    if answerState == .building {
                        addToken(token)
                    }
                } label: {
                    Text(token.text)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: "64748B"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(hex: "F1F5F9"), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Bottom Button

    private var bottomButton: some View {
        Group {
            switch answerState {
            case .building:
                Button {
                    checkAnswer()
                } label: {
                    Text("确认")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            selectedTokens.isEmpty ? Color(hex: "CBD5E1") : Color(hex: "3B82F6"),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                }
                .disabled(selectedTokens.isEmpty)

            case .correct:
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(hex: "22C55E"))
                        Text("正确！")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(hex: "22C55E"))
                    }

                    Button { advanceWord() } label: {
                        Text(currentIndex + 1 < challengeWords.count ? "下一题" : "完成")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(hex: "22C55E"), in: RoundedRectangle(cornerRadius: 14))
                    }
                }

            case .wrong:
                VStack(spacing: 12) {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color(hex: "EF4444"))
                            Text("再试一次")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color(hex: "EF4444"))
                        }
                        Text("正确答案：\(correctSentence)")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "94A3B8"))
                    }

                    Button {
                        resetCurrentQuestion()
                    } label: {
                        Text("重试")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(hex: "3B82F6"), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    // MARK: - Completed

    private var completedContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "star.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color(hex: "F59E0B"))

            Text("全部完成！")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color(hex: "1E293B"))

            Text("你完成了 \(challengeWords.count) 个词的组词练习")
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: "94A3B8"))

            Spacer()

            Button { dismiss() } label: {
                Text("完成")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(hex: "3B82F6"), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Empty

    private var emptyContent: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("还没有可以练习的词汇")
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: "94A3B8"))
            Text("先听一些播客，积累词汇")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "94A3B8"))
            Spacer()
            Button { dismiss() } label: {
                Text("返回")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "3B82F6"))
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Logic

    private func loadWords() {
        let candidates = store.words
        challengeWords = Array(candidates.prefix(10))
        currentIndex = 0
        completed = false
        if !challengeWords.isEmpty {
            setupQuestion()
        }
    }

    private func setupQuestion() {
        let word = challengeWords[currentIndex]
        // Use the example sentence from the word
        correctSentence = word.example
        let words = correctSentence.split(separator: " ").map(String.init)
        availableTokens = words.shuffled().map { WordToken(text: $0) }
        selectedTokens = []
        answerState = .building
    }

    private func addToken(_ token: WordToken) {
        selectedTokens.append(token)
        availableTokens.removeAll { $0.id == token.id }
    }

    private func removeToken(_ token: WordToken) {
        availableTokens.append(token)
        selectedTokens.removeAll { $0.id == token.id }
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters).joined()
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func checkAnswer() {
        let userSentence = selectedTokens.map(\.text).joined(separator: " ")
        if normalize(userSentence) == normalize(correctSentence) {
            withAnimation(.easeInOut(duration: 0.3)) {
                answerState = .correct
            }
            store.upgradeMastery(challengeWords[currentIndex].word, to: .canUse)
            store.markReviewed(challengeWords[currentIndex].word)
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                answerState = .wrong
            }
        }
    }

    private func resetCurrentQuestion() {
        setupQuestion()
    }

    private func advanceWord() {
        if currentIndex + 1 < challengeWords.count {
            currentIndex += 1
            setupQuestion()
        } else {
            withAnimation { completed = true }
        }
    }
}

// MARK: - Flow Layout (wrapping horizontal layout)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}

#Preview {
    FeynmanChallengeView()
        .environment(VocabularyStore())
}
