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

/// 一次退出结算的快照（在关闭手势那一刻从 controller / TaskEngine / DataStore 取好）。
struct RawSessionSummary {
    let podcastId: String
    let seconds: Int            // 本次未结算的收听秒数
    let wordsSaved: Int         // 本次会话划词数
    let todayTotalSeconds: Int  // 今日累计原声收听
    let streakDays: Int
    let rawTaskDone: Bool       // 「听 5 分钟真实播客」任务今日是否已达成
}

// MARK: - Summary overlay

/// 原声播放页退出时的「结算时刻」：成果卡 + 可选理解题流。
/// 叠在播放页最上层展示（先结算再 dismiss），点空白处直接关闭，绝不强制停留。
struct RawSessionSummaryView: View {
    let summary: RawSessionSummary
    let quiz: RawQuiz?              // nil = 没题或还没加载完 → 不显示 CTA
    let onContinueListening: () -> Void
    let onClose: () -> Void

    @State private var appeared = false
    @State private var quizMode = false

    // Quiz flow state
    @State private var questionIndex = 0
    @State private var selectedOption: Int?
    @State private var correctCount = 0
    @State private var showResult = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !quizMode else { return }   // 答题中不给误触关闭
                    Analytics.track(.rawSummaryCta, params: ["action": "close"])
                    onClose()
                }

            if quizMode {
                quizCard
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                summaryCard
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                appeared = true
            }
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }

    // MARK: - 成果卡

    private var summaryCard: some View {
        VStack(spacing: 0) {
            Text("🎉")
                .font(.system(size: 44))
                .scaleEffect(appeared ? 1 : 0.3)
                .padding(.top, 28)

            // 大数字：本次分钟数
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("+\(max(1, summary.seconds / 60))")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("分钟")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.top, 6)
            .scaleEffect(appeared ? 1 : 0.6)

            Text("真实语料听力")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 2)

            VStack(spacing: 12) {
                if summary.wordsSaved > 0 {
                    statRow(icon: "character.book.closed.fill",
                            text: String(localized: "划过 \(summary.wordsSaved) 个生词"))
                }
                statRow(icon: "clock.fill",
                        text: String(localized: "今日累计 \(max(1, summary.todayTotalSeconds / 60)) 分钟"))
                if summary.streakDays > 0 {
                    statRow(icon: "flame.fill",
                            text: String(localized: "连续第 \(summary.streakDays) 天"),
                            iconColor: .orange)
                }
                if summary.rawTaskDone {
                    statRow(icon: "checkmark.circle.fill",
                            text: String(localized: "今日任务「听 5 分钟真实播客」已完成"),
                            iconColor: .green)
                }
            }
            .padding(.top, 22)
            .padding(.horizontal, 28)

            VStack(spacing: 10) {
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
                            .frame(height: 50)
                            .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                Button {
                    Analytics.track(.rawSummaryCta, params: ["action": "continue"])
                    onContinueListening()
                } label: {
                    Text("继续听")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
                Button {
                    Analytics.track(.rawSummaryCta, params: ["action": "close"])
                    onClose()
                } label: {
                    Text("关闭")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(height: 36)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: 340)
        .background(Color(hex: "1C1C22"), in: RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }

    private func statRow(icon: String, text: String, iconColor: Color = .appPrimary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
        }
    }

    // MARK: - 理解题卡

    private var quizCard: some View {
        VStack(spacing: 0) {
            if showResult {
                quizResult
            } else if let question = currentQuestion {
                quizQuestion(question)
            }
        }
        .frame(maxWidth: 340)
        .background(Color(hex: "1C1C22"), in: RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }

    private var currentQuestion: RawQuizQuestion? {
        guard let quiz, questionIndex < quiz.questions.count else { return nil }
        return quiz.questions[questionIndex]
    }

    private func quizQuestion(_ question: RawQuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "第 \(questionIndex + 1)/\(quiz?.questions.count ?? 0) 题"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 24)

            Text(question.q)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            VStack(spacing: 10) {
                ForEach(question.options.indices, id: \.self) { idx in
                    optionButton(question: question, idx: idx)
                }
            }
            .padding(.top, 18)

            // 答完显示解析 + 下一题
            if selectedOption != nil {
                if let explain = question.explainText {
                    Text(explain)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }
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
                .padding(.top, 18)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
    }

    private func optionButton(question: RawQuizQuestion, idx: Int) -> some View {
        let answered = selectedOption != nil
        let isCorrect = idx == question.answer
        let isSelected = selectedOption == idx

        // 答后配色：正确项恒绿；选错的红；其余淡出
        let background: Color = {
            guard answered else { return Color.white.opacity(0.08) }
            if isCorrect { return Color.green.opacity(0.28) }
            if isSelected { return Color.red.opacity(0.28) }
            return Color.white.opacity(0.04)
        }()
        let border: Color = {
            guard answered else { return Color.white.opacity(0.12) }
            if isCorrect { return Color.green.opacity(0.8) }
            if isSelected { return Color.red.opacity(0.8) }
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
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(answered && !isCorrect && !isSelected ? 0.4 : 0.95))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if answered, isCorrect {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if answered, isSelected {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
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
            Text(allCorrect ? "🏆" : "💪")
                .font(.system(size: 44))
                .padding(.top, 28)

            Text("\(correctCount)/\(total)")
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 6)

            Text(allCorrect
                 ? String(localized: "全对！你真的听懂了")
                 : String(localized: "不错，明天再来一段"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 4)

            Button {
                onClose()
            } label: {
                Text("完成")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
    }
}
