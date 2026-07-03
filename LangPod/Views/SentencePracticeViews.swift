import SwiftUI

// MARK: - 我的句子·连词成句
// 轻量版（不进 SavedWord 记忆体系，无每日次数限制）：
// 题源 = 收藏句子（≤12 词），词块打散 → 点选拼句 → 对错反馈。

struct SentencePracticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SentenceStore.self) private var sentenceStore

    @State private var queue: [SavedSentence] = []
    @State private var currentIndex = 0
    @State private var availableTokens: [PracticeToken] = []
    @State private var selectedTokens: [PracticeToken] = []
    @State private var answerState: AnswerState = .building
    @State private var correctCount = 0
    @State private var completed = false

    enum AnswerState { case building, correct, wrong }

    struct PracticeToken: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if completed {
                PracticeCompleteView(
                    title: "完成！",
                    subtitle: "拼对了 \(correctCount)/\(queue.count) 句",
                    onRestart: { startGame() },
                    onClose: { dismiss() }
                )
            } else if queue.isEmpty {
                emptyContent
            } else {
                practiceContent
            }
        }
        .onAppear { startGame() }
    }

    private var currentSentence: SavedSentence { queue[currentIndex] }

    // MARK: - Game

    private func startGame() {
        queue = sentenceStore.practiceableSentences.shuffled()
        currentIndex = 0
        correctCount = 0
        completed = false
        if !queue.isEmpty { setupQuestion() }
    }

    private func setupQuestion() {
        let words = currentSentence.english
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        availableTokens = words.shuffled().map { PracticeToken(text: $0) }
        selectedTokens = []
        answerState = .building
    }

    private func checkAnswer() {
        let built = selectedTokens.map(\.text).joined(separator: " ").lowercased()
        let target = currentSentence.english
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
            .joined(separator: " ").lowercased()

        if built == target {
            answerState = .correct
            correctCount += 1
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            LessonAudioPlayer.shared.play(currentSentence.audioUrl, from: currentSentence.audioStart, to: currentSentence.audioEnd) {
                WordSpeaker.shared.speakSentence(currentSentence.english)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { advance() }
        } else {
            answerState = .wrong
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                // 重试：词块放回
                availableTokens = (availableTokens + selectedTokens).shuffled()
                selectedTokens = []
                answerState = .building
            }
        }
    }

    private func advance() {
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            setupQuestion()
        } else {
            completed = true
            Analytics.track(.sentencePracticeComplete, params: [
                "total": "\(queue.count)", "correct": "\(correctCount)",
            ])
        }
    }

    // MARK: - UI

    private var practiceContent: some View {
        VStack(spacing: 20) {
            practiceHeader(title: "连词成句", progress: "\(currentIndex + 1)/\(queue.count)") { dismiss() }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(currentSentence.scene)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.gold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.warningLight))
                    Spacer()
                }
                Text(currentSentence.chinese)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)

            // 已选词块（拼句区）
            FlowTokens(tokens: selectedTokens, style: answerStyle) { token in
                guard answerState == .building else { return }
                selectedTokens.removeAll { $0 == token }
                availableTokens.append(token)
            }
            .frame(minHeight: 70)
            .padding(.horizontal, 20)

            Divider().padding(.horizontal, 20)

            // 待选词块
            FlowTokens(tokens: availableTokens, style: .neutral) { token in
                guard answerState == .building else { return }
                availableTokens.removeAll { $0 == token }
                selectedTokens.append(token)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if availableTokens.isEmpty { checkAnswer() }
            }
            .padding(.horizontal, 20)

            if answerState == .correct {
                Text("✓ \(currentSentence.english)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.success)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }

            Spacer()
        }
    }

    private var answerStyle: FlowTokens.Style {
        switch answerState {
        case .building: .selected
        case .correct: .correct
        case .wrong: .wrong
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 12) {
            practiceHeader(title: "连词成句", progress: "") { dismiss() }
            Spacer()
            Text("没有可练习的句子（句子需 ≤12 个单词）")
                .font(.system(size: 14))
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
    }
}

// MARK: - 我的句子·场景模拟（场景选择题）
// 给定使用场景 + 中文意思 → 4 个英文句子里选出该说的那句。

struct SceneQuizView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SentenceStore.self) private var sentenceStore

    private struct Question {
        let answer: SavedSentence
        let options: [SavedSentence]  // 4 个（含正确项），已打乱
    }

    @State private var questions: [Question] = []
    @State private var currentIndex = 0
    @State private var selectedOption: String?   // english of tapped option
    @State private var revealed = false
    @State private var correctCount = 0
    @State private var completed = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if completed {
                PracticeCompleteView(
                    title: "场景通关！",
                    subtitle: "答对 \(correctCount)/\(questions.count) 题",
                    onRestart: { startGame() },
                    onClose: { dismiss() }
                )
            } else if questions.isEmpty {
                ProgressView().tint(Color.appPrimary)
            } else {
                quizContent
            }
        }
        .onAppear { startGame() }
    }

    private var current: Question { questions[currentIndex] }

    // MARK: - Game

    private func startGame() {
        let all = sentenceStore.sentences
        guard all.count >= 4 else {
            dismiss()
            return
        }
        let picked = all.shuffled().prefix(min(5, all.count))
        questions = picked.map { answer in
            let distractors = all.filter { $0.id != answer.id }.shuffled().prefix(3)
            return Question(answer: answer, options: ([answer] + distractors).shuffled())
        }
        currentIndex = 0
        correctCount = 0
        selectedOption = nil
        revealed = false
        completed = false
    }

    private func choose(_ option: SavedSentence) {
        guard !revealed else { return }
        selectedOption = option.english
        revealed = true
        if option.id == current.answer.id {
            correctCount += 1
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            LessonAudioPlayer.shared.play(current.answer.audioUrl, from: current.answer.audioStart, to: current.answer.audioEnd) {
                WordSpeaker.shared.speakSentence(current.answer.english)
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { advance() }
    }

    private func advance() {
        if currentIndex + 1 < questions.count {
            currentIndex += 1
            selectedOption = nil
            revealed = false
        } else {
            completed = true
            Analytics.track(.sentenceQuizComplete, params: [
                "total": "\(questions.count)", "correct": "\(correctCount)",
            ])
        }
    }

    // MARK: - UI

    private var quizContent: some View {
        VStack(spacing: 20) {
            practiceHeader(title: "场景模拟", progress: "\(currentIndex + 1)/\(questions.count)") { dismiss() }

            // 题干：场景 + 你想表达的意思
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "theatermasks.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.gold)
                    Text("场景：\(current.answer.scene)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.gold)
                }
                Text("你想表达：\(current.answer.chinese)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("这时该说哪句？")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.warningLight, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)

            VStack(spacing: 10) {
                ForEach(current.options, id: \.id) { option in
                    optionRow(option)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    private func optionRow(_ option: SavedSentence) -> some View {
        let isAnswer = option.id == current.answer.id
        let isSelected = selectedOption == option.english
        let bg: Color = {
            guard revealed else { return .white }
            if isAnswer { return Color.successLight }
            if isSelected { return Color.dangerLight }
            return .white
        }()
        let border: Color = {
            guard revealed else { return Color.border }
            if isAnswer { return Color.success }
            if isSelected { return Color.danger }
            return Color.border
        }()

        return Button { choose(option) } label: {
            HStack {
                Text(option.english)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer()
                if revealed && isAnswer {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.success)
                } else if revealed && isSelected {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.danger)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bg, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(border, lineWidth: revealed && (isAnswer || isSelected) ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(revealed)
    }
}

// MARK: - 共享小组件

/// 练习页统一头部
private func practiceHeader(title: String, progress: String, onClose: @escaping () -> Void) -> some View {
    ZStack {
        Text(title)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Color.textPrimary)
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white))
            }
            Spacer()
            if !progress.isEmpty {
                Text(progress)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
    .padding(.horizontal, 20)
    .padding(.top, 12)
}

/// 自动换行词块区
struct FlowTokens: View {
    enum Style { case neutral, selected, correct, wrong }

    let tokens: [SentencePracticeView.PracticeToken]
    let style: Style
    let onTap: (SentencePracticeView.PracticeToken) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(tokens) { token in
                Button { onTap(token) } label: {
                    Text(token.text)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(textColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(bgColor, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(borderColor, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bgColor: Color {
        switch style {
        case .neutral: .white
        case .selected: Color.primaryLight
        case .correct: Color.successLight
        case .wrong: Color.dangerLight
        }
    }

    private var textColor: Color {
        switch style {
        case .wrong: Color.danger
        case .correct: Color(hex: "16A34A")
        default: Color.textPrimary
        }
    }

    private var borderColor: Color {
        switch style {
        case .neutral: Color.border
        case .selected: Color.primaryLighter
        case .correct: Color.success
        case .wrong: Color.danger
        }
    }
}

// FlowLayout 复用 FeynmanChallengeView.swift 里的现有实现

/// 练习完成页（两种练习共用）
struct PracticeCompleteView: View {
    let title: String
    let subtitle: String
    let onRestart: () -> Void
    let onClose: () -> Void

    @State private var scale: CGFloat = 0.4

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "star.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.warning)
                .scaleEffect(scale)
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { scale = 1 }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            VStack(spacing: 10) {
                Button(action: onRestart) {
                    Text("再来一轮")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 25))
                }
                Button(action: onClose) {
                    Text("完成")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }
}
