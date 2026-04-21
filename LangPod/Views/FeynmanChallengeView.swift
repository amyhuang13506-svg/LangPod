import SwiftUI

struct FeynmanChallengeView: View {
    @Environment(VocabularyStore.self) private var store
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    @State private var currentIndex = 0
    @State private var challengeWords: [SavedWord] = []
    @State private var completed = false

    // Sentence building
    @State private var availableTokens: [WordToken] = []
    @State private var selectedTokens: [WordToken] = []
    @State private var answerState: AnswerState = .building
    @State private var correctSentence = ""

    // Session tracking
    @State private var sessionPracticedWords: Set<String> = []
    @State private var sessionRound = 1
    @State private var isFirstCompletion = true
    @State private var wrongWordCounts: [String: Int] = [:]  // word → remaining repeat count

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
            Color.appBackground.ignoresSafeArea()

            if completed {
                completedContent
            } else if challengeWords.isEmpty {
                emptyContent
            } else {
                challengeContent
            }
        }
        .onAppear { startGame() }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(subscriptionManager)
        }
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
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                Text("连词成句")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(currentIndex + 1)/\(challengeWords.count)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.appPrimary)
                    if sessionRound > 1 {
                        Text("· 累计\(sessionPracticedWords.count)词")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.border)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.appPrimary)
                        .frame(width: geo.size.width * CGFloat(currentIndex + 1) / CGFloat(challengeWords.count), height: 4)
                }
            }
            .frame(height: 4)

            // Word card
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(word.word)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Button { WordSpeaker.shared.speak(word.word) } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.appPrimary)
                    }
                }
                Text(word.phonetic)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
                Text(word.translationZh)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.border, lineWidth: 1)
            )

            // Prompt
            Text("用这个词组成正确的句子：")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.textSecondary)
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
        case .building: Color.border
        case .correct: Color.success
        case .wrong: Color.danger
        }

        let bgColor: Color = switch answerState {
        case .building: Color.white
        case .correct: Color(hex: "F0FDF4")
        case .wrong: Color.dangerLight
        }

        return VStack(spacing: 8) {
            FlowLayout(spacing: 8) {
                ForEach(selectedTokens) { token in
                    Button {
                        if answerState == .building {
                            WordSpeaker.shared.speak(token.text)
                            removeToken(token)
                        }
                    } label: {
                        Text(token.text)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.primaryLight, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }

            if selectedTokens.isEmpty {
                Text("点击下方单词组成句子")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textQuaternary)
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
                        WordSpeaker.shared.speak(token.text)
                        addToken(token)
                    }
                } label: {
                    Text(token.text)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.divider, in: RoundedRectangle(cornerRadius: 10))
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
                            selectedTokens.isEmpty ? Color.textQuaternary : Color.appPrimary,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                }
                .disabled(selectedTokens.isEmpty)

            case .correct:
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.success)
                        Text("正确！")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.success)
                    }

                    // Play correct sentence
                    Button { WordSpeaker.shared.speakSentence(correctSentence) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.appPrimary)
                            Text(correctSentence)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "F0FDF4"), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    // Sentence translation
                    if let exampleZh = challengeWords[currentIndex].exampleZh, !exampleZh.isEmpty {
                        Text(exampleZh)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("\(challengeWords[currentIndex].word) = \(challengeWords[currentIndex].translationZh)")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button { advanceWord() } label: {
                        Text(currentIndex + 1 < challengeWords.count ? "下一题" : "完成")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.success, in: RoundedRectangle(cornerRadius: 14))
                    }
                }

            case .wrong:
                VStack(spacing: 12) {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.danger)
                            Text("再试一次")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.danger)
                        }
                        Text("正确答案：\(correctSentence)")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textTertiary)
                    }

                    HStack(spacing: 12) {
                        Button {
                            resetCurrentQuestion()
                        } label: {
                            Text("重试")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
                        }

                        Button {
                            advanceWord()
                        } label: {
                            Text("跳过")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 80)
                                .frame(height: 52)
                                .background(Color.divider, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Completed

    @State private var starScale: CGFloat = 0
    @State private var textOpacity: Double = 0
    @State private var confettiOffsets: [(CGFloat, CGFloat)] = (0..<12).map { _ in
        (CGFloat.random(in: -150...150), CGFloat.random(in: -200...(-50)))
    }
    @State private var confettiVisible = false

    private var completedContent: some View {
        ZStack {
            // Confetti particles (only on first completion)
            if confettiVisible && isFirstCompletion {
                ForEach(0..<12, id: \.self) { i in
                    Circle()
                        .fill([Color.appPrimary, Color.warning, Color.success, Color.danger][i % 4])
                        .frame(width: CGFloat.random(in: 6...10), height: CGFloat.random(in: 6...10))
                        .offset(x: confettiOffsets[i].0, y: confettiOffsets[i].1)
                        .opacity(confettiVisible ? 0 : 1)
                        .animation(.easeOut(duration: 1.5).delay(Double(i) * 0.05), value: confettiVisible)
                }
            }

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "star.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.warning)
                    .scaleEffect(starScale)

                Text("本组完成！")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .opacity(textOpacity)

                Text("完成 \(challengeWords.count) 个词的连词成句练习")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.textTertiary)
                    .opacity(textOpacity)

                if sessionPracticedWords.count > challengeWords.count {
                    Text("本次累计已练 \(sessionPracticedWords.count) 个词")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .opacity(textOpacity)
                }

                Spacer()

                VStack(spacing: 12) {
                    let hasMore = hasMoreWords
                    let dailyLocked = !subscriptionManager.isProUser && store.dailySentencePlayed
                    Button {
                        if dailyLocked {
                            showPaywall = true
                        } else {
                            startNextSet()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if dailyLocked {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 14))
                            }
                            Text("🔥")
                            Text(dailyLocked ? "升级 Pro 继续练习" : "再来一组")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            dailyLocked ? Color.appPrimary : (hasMore ? Color.warning : Color.textQuaternary),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                    }
                    .disabled(!hasMore && !dailyLocked)

                    if !hasMore && !dailyLocked {
                        Text("所有词汇都练过了")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textTertiary)
                    } else if dailyLocked {
                        Text("免费用户每日 1 轮")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textTertiary)
                    }

                    Button { dismiss() } label: {
                        Text("返回词汇本")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(textOpacity)
            }
        }
        .onAppear {
            celebrateCompletion()
        }
    }

    private func celebrateCompletion() {
        // Haptic
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Star bounce in
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
            starScale = 1.0
        }

        // Text fade in
        withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
            textOpacity = 1.0
        }

        // Confetti burst (only first time)
        if isFirstCompletion {
            confettiVisible = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation { confettiVisible = true }
            }
        }

        // Second haptic for emphasis
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    // MARK: - Empty

    private var emptyContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()

            Image(systemName: "text.quote")
                .font(.system(size: 48))
                .foregroundStyle(Color.textQuaternary)
                .padding(.bottom, 16)

            Text("还没有可以练习的词汇")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            Text("听一集播客，词汇会自动收藏到这里")
                .font(.system(size: 14))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            Spacer()

            Button { dismiss() } label: {
                Text("去听一集")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Logic

    private var hasMoreWords: Bool {
        return store.words.filter { !$0.example.isEmpty }.count > 0
    }

    private func startGame() {
        sessionPracticedWords = []
        wrongWordCounts = [:]
        sessionRound = 1
        isFirstCompletion = true
        loadWords()
    }

    private func startNextSet() {
        sessionRound += 1
        isFirstCompletion = false
        // Reset animation states
        starScale = 0
        textOpacity = 0
        completed = false
        currentIndex = 0
        loadWords()
    }

    private let maxWordsPerSet = 8

    private func loadWords() {
        let wordsWithExamples = store.words.filter { !$0.example.isEmpty }
        var pool: [SavedWord] = []

        if sessionRound == 1 {
            // First set: priority reviewing → new → mastered
            pool += wordsWithExamples.filter { $0.memoryState == .fading }.shuffled()
            pool += wordsWithExamples.filter { $0.memoryState == .forgetting }.shuffled()
            pool += wordsWithExamples.filter { $0.memoryState == .strong }.shuffled()
        } else {
            // Subsequent sets: wrong words + unpracticed, mixed randomly
            let wrongWords = wordsWithExamples.filter { wrongWordCounts[$0.word, default: 0] > 0 }
            let unpracticed = wordsWithExamples.filter {
                !sessionPracticedWords.contains($0.word) && wrongWordCounts[$0.word, default: 0] == 0
            }
            pool = (wrongWords + unpracticed).shuffled()

            // Not enough — add practiced words (excluding wrong words)
            if pool.count < maxWordsPerSet {
                let extras = wordsWithExamples.filter {
                    sessionPracticedWords.contains($0.word) && wrongWordCounts[$0.word, default: 0] == 0
                }.shuffled()
                pool += extras
            }
        }

        // Decrement wrong word counts for words entering this set
        for word in pool.prefix(maxWordsPerSet) {
            if let count = wrongWordCounts[word.word], count > 0 {
                wrongWordCounts[word.word] = count - 1
            }
        }

        challengeWords = Array(pool.prefix(maxWordsPerSet))
        currentIndex = 0
        completed = false
        if !challengeWords.isEmpty {
            setupQuestion()
        }
    }

    private func setupQuestion() {
        let word = challengeWords[currentIndex]
        correctSentence = word.example
        // Split into tokens, strip punctuation from each token for display
        let words = correctSentence.split(separator: " ").map(String.init)
        let cleanWords = words.map { token in
            token.trimmingCharacters(in: .punctuationCharacters)
        }.filter { !$0.isEmpty }
        availableTokens = cleanWords.shuffled().map { WordToken(text: $0) }
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.3)) {
                answerState = .correct
            }
            // Auto-play the complete sentence
            WordSpeaker.shared.speakSentence(correctSentence)
            store.recordSentenceCorrect(challengeWords[currentIndex].word)
            sessionPracticedWords.insert(challengeWords[currentIndex].word)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            wrongWordCounts[challengeWords[currentIndex].word] = 5
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
            store.markDailySentencePlayed()
            Analytics.track(.feynmanComplete, params: [
                "words_practiced": "\(sessionPracticedWords.count)"
            ])
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
        .environment(SubscriptionManager())
}
