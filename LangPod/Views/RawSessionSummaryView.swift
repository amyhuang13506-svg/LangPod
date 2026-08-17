import SwiftUI
import UIKit

// MARK: - Quiz models

/// 原声理解题（OSS: raw_podcasts/{id}/quiz.json，pipeline generate_raw_quiz.py 产出）。
/// 老内容没有该文件 → fetch 404 → CTA 不出现，静默降级。
struct RawQuiz: Codable {
    let podcastId: String?
    let questions: [RawQuizQuestion]

    enum CodingKeys: String, CodingKey {
        case podcastId = "podcast_id"
        case questions
    }
}

struct RawQuizQuestion: Codable, Identifiable {
    let q: String                       // 英文题干（考大意，不考语法）
    let options: [String]
    let answer: Int                     // 正确选项下标
    let explain: [String: String]?      // 按语言的解析 {"zh": "...", "ja": "..."}

    var id: String { q }

    /// 按用户母语取解析，缺失时回落中文 → 任意语言。
    var explainText: String? {
        guard let explain, !explain.isEmpty else { return nil }
        return explain[ContentLanguage.current.rawValue]
            ?? explain["zh"]
            ?? explain.values.first
    }
}

enum RawQuizLoader {
    /// 从 transcriptUrl 派生 quiz.json 地址（同目录），懒加载。
    static func quizURL(fromTranscriptUrl transcriptUrl: String?) -> URL? {
        guard let t = transcriptUrl, let url = URL(string: t) else { return nil }
        return url.deletingLastPathComponent().appendingPathComponent("quiz.json")
    }

    static func fetch(transcriptUrl: String?) async -> RawQuiz? {
        guard let url = quizURL(fromTranscriptUrl: transcriptUrl) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let quiz = try? JSONDecoder().decode(RawQuiz.self, from: data),
              !quiz.questions.isEmpty
        else { return nil }
        return quiz
    }
}

// MARK: - Summary data

/// 本次会话划词存下的一个生词（结算卡具体列出，不只报数字）。
struct RawSessionWordBrief: Identifiable, Equatable {
    let word: String
    let translation: String
    var id: String { word }
}

/// 一次退出结算的快照（在关闭手势那一刻从 controller / TaskEngine / DataStore 取好）。
struct RawSessionSummary {
    let podcastId: String
    let seconds: Int                    // 本次未结算的收听秒数
    let words: [RawSessionWordBrief]    // 本次会话划词存下的生词（具体词条）
    let todayTotalSeconds: Int          // 今日累计原声收听
    let streakDays: Int
    let rawTaskDone: Bool               // 「听 5 分钟真实播客」任务今日是否已达成
}

// MARK: - Summary overlay

/// 原声播放页退出时的「结算时刻」：成果卡 + 可选理解题流。
/// 视觉延续 DailyTaskPopupView（浅色 appBackground 卡 + 白色行 + 蓝/绿胶囊）。
/// 叠在播放页最上层展示（先结算再 dismiss），点空白处直接关闭，绝不强制停留。
struct RawSessionSummaryView: View {
    let summary: RawSessionSummary
    let quiz: RawQuiz?              // nil = 没题或还没加载完 → 不显示 CTA
    let onContinueListening: () -> Void
    let onClose: () -> Void

    @State private var cardScale: CGFloat = 0.92
    @State private var cardOpacity: Double = 0
    @State private var quizMode = false

    // Quiz flow state
    @State private var questionIndex = 0
    @State private var selectedOption: Int?
    @State private var correctCount = 0
    @State private var showResult = false

    /// 结算卡最多列几个生词，多出的折叠成"还有 N 个"
    private static let maxWordRows = 4

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !quizMode else { return }   // 答题中不给误触关闭
                    Analytics.track(.rawSummaryCta, params: ["action": "close"])
                    onClose()
                }

            Group {
                if quizMode {
                    quizCard
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    summaryCard
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .scaleEffect(cardScale)
            .opacity(cardOpacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                cardScale = 1.0
                cardOpacity = 1.0
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - 成果卡（任务弹框同款浅色）

    private var summaryCard: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 22)
                .padding(.horizontal, 22)

            if !summary.words.isEmpty {
                wordsSection
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }

            if summary.rawTaskDone {
                taskDoneRow
                    .padding(.horizontal, 16)
                    .padding(.top, summary.words.isEmpty ? 16 : 8)
            }

            ctaButtons
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 18)
        }
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .topTrailing) {
            Button {
                Analytics.track(.rawSummaryCta, params: ["action": "close"])
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white))
            }
            .padding(12)
        }
        .padding(.horizontal, 28)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("🎉")
                .font(.system(size: 34))

            VStack(alignment: .leading, spacing: 3) {
                Text("真实听力 +\(max(1, summary.seconds / 60)) 分钟")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 4) {
                    Text("今日累计 \(max(1, summary.todayTotalSeconds / 60)) 分钟")
                    if summary.streakDays > 0 {
                        Text("· 🔥 连续 \(summary.streakDays) 天")
                    }
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
    }

    /// 本次学到的具体生词（词 + 释义逐条列出，不只报数字）
    private var wordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本次学到 \(summary.words.count) 个生词")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .padding(.leading, 6)

            VStack(spacing: 6) {
                ForEach(summary.words.prefix(Self.maxWordRows)) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "character.book.closed.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.appPrimary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.primaryLight))

                        Text(item.word)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)

                        Spacer(minLength: 8)

                        Text(item.translation)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                }

                if summary.words.count > Self.maxWordRows {
                    Text("还有 \(summary.words.count - Self.maxWordRows) 个已入生词本")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// 任务达成行（任务弹框已完成行同款）
    private var taskDoneRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.success)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.successLight))

            Text("听 5 分钟真实播客")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                Text("已完成")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.success)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.successLight, in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private var ctaButtons: some View {
        VStack(spacing: 8) {
            if quiz != nil {
                Button {
                    Analytics.track(.rawSummaryCta, params: ["action": "quiz"])
                    Analytics.track(.rawQuizStart, params: ["podcast_id": summary.podcastId])
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        quizMode = true
                    }
                } label: {
                    Text("测测听懂了多少")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            Button {
                Analytics.track(.rawSummaryCta, params: ["action": "continue"])
                onContinueListening()
            } label: {
                Text("继续听")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(quiz != nil ? Color.textSecondary : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: quiz != nil ? 44 : 48)
                    .background(
                        quiz != nil ? Color.white : Color.appPrimary,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
        }
    }

    // MARK: - 理解题卡（同套浅色）

    /// 答题全程卡片高度固定：题目/选项/解析/按钮各占恒定槽位，
    /// 内容变化（作答、换题、看结果）时卡片不再变大变小。
    private static let quizCardHeight: CGFloat = 460

    private var quizCard: some View {
        VStack(spacing: 0) {
            if showResult {
                quizResult
            } else if let question = currentQuestion {
                quizQuestion(question)
            }
        }
        .frame(height: Self.quizCardHeight)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 28)
    }

    private var currentQuestion: RawQuizQuestion? {
        guard let quiz, questionIndex < quiz.questions.count else { return nil }
        return quiz.questions[questionIndex]
    }

    private func quizQuestion(_ question: RawQuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("第 \(questionIndex + 1)/\(quiz?.questions.count ?? 0) 题")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .padding(.top, 22)

            // 题干固定槽位：不同长度的题不推挤下方选项
            Text(question.q)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                .padding(.top, 8)

            VStack(spacing: 8) {
                ForEach(question.options.indices, id: \.self) { idx in
                    optionButton(question: question, idx: idx)
                }
            }

            Spacer(minLength: 6)

            // 解析槽位恒定占位：未作答时透明，不改变布局
            Text(selectedOption != nil ? (question.explainText ?? "") : " ")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .topLeading)

            // 按钮恒定占位：未作答时透明禁用
            Button {
                advance()
            } label: {
                Text(questionIndex + 1 >= (quiz?.questions.count ?? 0) ? "看结果" : "下一题")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(selectedOption == nil)
            .opacity(selectedOption == nil ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: selectedOption == nil)
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private func optionButton(question: RawQuizQuestion, idx: Int) -> some View {
        let answered = selectedOption != nil
        let isCorrect = idx == question.answer
        let isSelected = selectedOption == idx

        // 答后配色：正确项恒绿；选错的红；其余淡出（浅色系）
        let background: Color = {
            guard answered else { return .white }
            if isCorrect { return Color.successLight }
            if isSelected { return Color.dangerLight }
            return Color.white.opacity(0.5)
        }()
        let border: Color = {
            guard answered else { return Color.border }
            if isCorrect { return Color.success }
            if isSelected { return Color.danger }
            return Color.clear
        }()

        return Button {
            guard selectedOption == nil else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedOption = idx
            }
            if isCorrect {
                correctCount += 1
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        } label: {
            HStack(spacing: 10) {
                Text(question.options[idx])
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(answered && !isCorrect && !isSelected
                                     ? Color.textTertiary : Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if answered, isCorrect {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.success)
                } else if answered, isSelected {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.danger)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(border, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func advance() {
        let total = quiz?.questions.count ?? 0
        if questionIndex + 1 >= total {
            Analytics.track(.rawQuizComplete, params: [
                "podcast_id": summary.podcastId,
                "correct_count": "\(correctCount)",
                "total": "\(total)"
            ])
            if correctCount == total {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showResult = true
            }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                questionIndex += 1
                selectedOption = nil
            }
        }
    }

    private var quizResult: some View {
        let total = quiz?.questions.count ?? 0
        let allCorrect = correctCount == total
        return VStack(spacing: 0) {
            Spacer()

            Text(allCorrect ? "🏆" : "💪")
                .font(.system(size: 44))

            Text("\(correctCount)/\(total)")
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 4)

            Text(allCorrect ? "全对！你真的听懂了" : "不错，明天再来一段")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 4)

            Spacer()

            Button {
                onClose()
            } label: {
                Text("完成")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
    }
}
