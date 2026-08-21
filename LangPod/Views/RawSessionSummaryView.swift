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
                    // 公用固定尺寸答题卡（与听力测验同一组件）
                    QuizFlowCard(
                        questions: quiz?.questions ?? [],
                        onFinished: { correct in
                            Analytics.track(.rawQuizComplete, params: [
                                "podcast_id": summary.podcastId,
                                "correct_count": "\(correct)",
                                "total": "\(quiz?.questions.count ?? 0)"
                            ])
                        },
                        onDone: onClose
                    )
                    .padding(.horizontal, 28)
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

}
