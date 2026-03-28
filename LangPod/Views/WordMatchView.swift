import SwiftUI

struct WordMatchView: View {
    @Environment(VocabularyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var round = 1
    @State private var totalRounds = 8
    @State private var currentWords: [SavedWord] = []
    @State private var shuffledTranslations: [String] = []
    @State private var selectedLeft: String?
    @State private var selectedRight: String?
    @State private var matchedPairs: Set<String> = []
    @State private var wrongPair: (String, String)?
    @State private var timer: Double = 0
    @State private var timerRunning = true
    @State private var gameComplete = false

    private let wordsPerRound = 4

    var body: some View {
        ZStack {
            Color(hex: "F7F8FC").ignoresSafeArea()

            if gameComplete {
                gameCompleteContent
            } else {
                gameContent
            }
        }
        .onAppear { startGame() }
    }

    // MARK: - Game Content

    private var gameContent: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(hex: "94A3B8"))
                }
                Spacer()
                Text("词义配对")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: "1E293B"))
                Spacer()
                Text(formattedTime)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "92400E"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: "FEF3C7"), in: RoundedRectangle(cornerRadius: 8))
            }

            // Progress
            HStack {
                Text("第 \(round)/\(totalRounds) 轮")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "64748B"))
                Spacer()
                Text("即将遗忘的词")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "EF4444"))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "E2E8F0"))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "3B82F6"))
                        .frame(width: geo.size.width * CGFloat(round) / CGFloat(totalRounds), height: 4)
                }
            }
            .frame(height: 4)

            // Match area
            HStack(spacing: 16) {
                // Left column - English
                VStack(spacing: 12) {
                    ForEach(currentWords, id: \.word) { word in
                        matchCard(
                            text: matchedPairs.contains(word.word) ? "\(word.word) ✓" : word.word,
                            isSelected: selectedLeft == word.word,
                            isMatched: matchedPairs.contains(word.word),
                            isWrong: wrongPair?.0 == word.word
                        ) {
                            if !matchedPairs.contains(word.word) {
                                selectLeft(word.word)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // Right column - Chinese
                VStack(spacing: 12) {
                    ForEach(shuffledTranslations, id: \.self) { translation in
                        let matchedWord = currentWords.first { $0.translationZh == translation && matchedPairs.contains($0.word) }
                        matchCard(
                            text: matchedWord != nil ? "\(translation) ✓" : translation,
                            isSelected: selectedRight == translation,
                            isMatched: matchedWord != nil,
                            isWrong: wrongPair?.1 == translation,
                            isRight: true
                        ) {
                            if matchedWord == nil {
                                selectRight(translation)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)

            // Hint
            Text("点击左边英文，再点右边中文释义进行配对")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "94A3B8"))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.top, 62)
        .padding(.bottom, 24)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if timerRunning { timer += 1 }
        }
    }

    // MARK: - Match Card

    private func matchCard(text: String, isSelected: Bool, isMatched: Bool, isWrong: Bool, isRight: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    isMatched ? Color(hex: "22C55E") :
                    isWrong ? Color(hex: "EF4444") :
                    isRight ? Color(hex: "64748B") :
                    Color(hex: "1E293B")
                )
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background(
                    isMatched ? Color(hex: "F0FDF4") :
                    isWrong ? Color(hex: "FEF2F2") :
                    Color.white,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isMatched ? Color(hex: "22C55E") :
                            isSelected ? Color(hex: "3B82F6") :
                            isWrong ? Color(hex: "EF4444") :
                            Color(hex: "E2E8F0"),
                            lineWidth: (isSelected || isMatched || isWrong) ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isMatched)
    }

    // MARK: - Game Complete

    private var gameCompleteContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color(hex: "22C55E"))

            Text("全部配对完成！")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color(hex: "1E293B"))

            Text("用时 \(formattedTime)")
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

    // MARK: - Logic

    private func startGame() {
        let available = store.words
        totalRounds = max(1, available.count / wordsPerRound)
        round = 1
        timer = 0
        timerRunning = true
        gameComplete = false
        loadRound()
    }

    private func loadRound() {
        matchedPairs = []
        selectedLeft = nil
        selectedRight = nil
        wrongPair = nil

        let available = store.words
        let startIdx = ((round - 1) * wordsPerRound) % available.count
        var roundWords: [SavedWord] = []
        for i in 0..<min(wordsPerRound, available.count) {
            roundWords.append(available[(startIdx + i) % available.count])
        }
        currentWords = roundWords
        shuffledTranslations = roundWords.map(\.translationZh).shuffled()
    }

    private func selectLeft(_ word: String) {
        wrongPair = nil
        selectedLeft = word
        if let right = selectedRight {
            checkMatch(left: word, right: right)
        }
    }

    private func selectRight(_ translation: String) {
        wrongPair = nil
        selectedRight = translation
        if let left = selectedLeft {
            checkMatch(left: left, right: translation)
        }
    }

    private func checkMatch(left: String, right: String) {
        if let word = currentWords.first(where: { $0.word == left }), word.translationZh == right {
            // Correct match
            _ = withAnimation(.easeInOut(duration: 0.3)) {
                matchedPairs.insert(left)
            }
            selectedLeft = nil
            selectedRight = nil

            // Upgrade mastery
            store.markReviewed(left)
            if store.words.first(where: { $0.word == left })?.masteryLevel == .heard {
                store.upgradeMastery(left, to: .recognized)
            }

            // Check if round complete
            if matchedPairs.count == currentWords.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    advanceRound()
                }
            }
        } else {
            // Wrong match
            wrongPair = (left, right)
            selectedLeft = nil
            selectedRight = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation { wrongPair = nil }
            }
        }
    }

    private func advanceRound() {
        if round >= totalRounds {
            timerRunning = false
            withAnimation { gameComplete = true }
        } else {
            round += 1
            loadRound()
        }
    }

    private var formattedTime: String {
        let m = Int(timer) / 60
        let s = Int(timer) % 60
        return String(format: "%d:%02d", m, s)
    }
}

#Preview {
    WordMatchView()
        .environment(VocabularyStore())
}
