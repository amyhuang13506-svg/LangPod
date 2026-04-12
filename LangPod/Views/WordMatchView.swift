import SwiftUI
import UIKit

struct WordMatchView: View {
    @Environment(VocabularyStore.self) private var store
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    @State private var round = 1
    @State private var totalRounds = 1
    @State private var currentWords: [SavedWord] = []
    @State private var shuffledTranslations: [String] = []
    @State private var selectedLeft: String?
    @State private var selectedRight: String?
    @State private var matchedPairs: Set<String> = []
    @State private var wrongPair: (String, String)?
    @State private var timer: Double = 0
    @State private var timerRunning = true
    @State private var gameComplete = false
    @AppStorage("wordMatchSoundEnabled") private var soundEnabled = true

    // Session tracking
    @State private var gameWords: [SavedWord] = []
    @State private var sessionPracticedWords: Set<String> = []  // all words practiced this session
    @State private var sessionRound = 1  // which "set" we're on
    @State private var isFirstCompletion = true
    @State private var wrongWordCounts: [String: Int] = [:]  // word → remaining repeat count

    private let wordsPerRound = 4

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if gameComplete {
                gameCompleteContent
            } else {
                gameContent
            }
        }
        .onAppear { startGame() }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(subscriptionManager)
        }
    }

    // MARK: - Game Content

    private var gameContent: some View {
        VStack(spacing: 24) {
            // Header
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }

                Button { soundEnabled.toggle() } label: {
                    Image(systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(soundEnabled ? Color.appPrimary : Color.textQuaternary)
                }

                Spacer()
                Text("词义配对")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(formattedTime)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.gold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.warningLight, in: RoundedRectangle(cornerRadius: 8))
            }

            // Progress
            HStack {
                Text("第 \(round)/\(totalRounds) 轮")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                if sessionRound > 1 {
                    Text("本次已练 \(sessionPracticedWords.count) 词")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.appPrimary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.border)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.appPrimary)
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
                .foregroundStyle(Color.textTertiary)
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
                    isMatched ? Color.success :
                    isWrong ? Color.danger :
                    isRight ? Color.textSecondary :
                    Color.textPrimary
                )
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background(
                    isMatched ? Color(hex: "F0FDF4") :
                    isWrong ? Color.dangerLight :
                    Color.white,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isMatched ? Color.success :
                            isSelected ? Color.appPrimary :
                            isWrong ? Color.danger :
                            Color.border,
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
                .foregroundStyle(Color.success)

            Text("本组完成！")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            // Stats
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text(formattedTime)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("用时")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                }
                VStack(spacing: 4) {
                    Text("\(gameWords.count)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.appPrimary)
                    Text("配对")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            if sessionPracticedWords.count > gameWords.count {
                Text("本次累计已练 \(sessionPracticedWords.count) 个词")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            VStack(spacing: 12) {
                let hasMore = hasMoreWords
                let dailyLocked = !subscriptionManager.isProUser && store.dailyMatchPlayed
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
                        dailyLocked ? Color.warning : (hasMore ? Color.appPrimary : Color.textQuaternary),
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
        }
    }

    // MARK: - Logic

    private var hasMoreWords: Bool {
        return store.words.count >= wordsPerRound
    }

    private func startGame() {
        sessionPracticedWords = []
        wrongWordCounts = [:]
        sessionRound = 1
        isFirstCompletion = true
        loadGameWords()
    }

    private func startNextSet() {
        sessionRound += 1
        isFirstCompletion = false
        timer = 0
        timerRunning = true
        gameComplete = false
        loadGameWords()
    }

    private let maxRoundsPerSet = 8

    private func loadGameWords() {
        let targetCount = maxRoundsPerSet * wordsPerRound
        var pool: [SavedWord] = []

        if sessionRound == 1 {
            // First set: priority new → reviewing → mastered
            let newWords = store.words.filter { $0.memoryState == .forgetting }.shuffled()
            let fadingWords = store.words.filter { $0.memoryState == .fading }.shuffled()
            let strongWords = store.words.filter { $0.memoryState == .strong }.shuffled()
            pool = newWords + fadingWords + strongWords
        } else {
            // Subsequent sets: wrong words + unpracticed, mixed randomly
            let wrongWords = store.words.filter { wrongWordCounts[$0.word, default: 0] > 0 }
            let unpracticed = store.words.filter {
                !sessionPracticedWords.contains($0.word) && wrongWordCounts[$0.word, default: 0] == 0
            }
            pool = (wrongWords + unpracticed).shuffled()

            // Not enough — add practiced words (excluding wrong words still in pool)
            if pool.count < targetCount {
                let extras = store.words.filter {
                    sessionPracticedWords.contains($0.word) && wrongWordCounts[$0.word, default: 0] == 0
                }.shuffled()
                pool += extras
            }
        }

        // Decrement wrong word counts for words entering this set
        for word in pool.prefix(targetCount) {
            if let count = wrongWordCounts[word.word], count > 0 {
                wrongWordCounts[word.word] = count - 1
            }
        }

        gameWords = Array(pool.prefix(targetCount))
        totalRounds = max(1, gameWords.count / wordsPerRound)
        round = 1
        gameComplete = false
        loadRound()
    }

    private func loadRound() {
        matchedPairs = []
        selectedLeft = nil
        selectedRight = nil
        wrongPair = nil

        let startIdx = ((round - 1) * wordsPerRound) % gameWords.count
        var roundWords: [SavedWord] = []
        for i in 0..<min(wordsPerRound, gameWords.count) {
            roundWords.append(gameWords[(startIdx + i) % gameWords.count])
        }
        currentWords = roundWords
        shuffledTranslations = roundWords.map(\.translationZh).shuffled()
    }

    private func selectLeft(_ word: String) {
        wrongPair = nil
        selectedLeft = word
        if soundEnabled {
            WordSpeaker.shared.speak(word)
        }
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            _ = withAnimation(.easeInOut(duration: 0.3)) {
                matchedPairs.insert(left)
            }
            selectedLeft = nil
            selectedRight = nil

            // Record correct match
            store.recordMatchCorrect(left)
            sessionPracticedWords.insert(left)

            // Check if round complete
            if matchedPairs.count == currentWords.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    advanceRound()
                }
            }
        } else {
            // Wrong match — mark for repeat (at least 5 more times)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            wrongWordCounts[left] = 5
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
            store.markDailyMatchPlayed()
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
        .environment(SubscriptionManager())
}
