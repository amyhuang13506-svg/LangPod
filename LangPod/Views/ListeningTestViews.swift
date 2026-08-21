import SwiftUI
import AVFoundation
import UIKit

extension Notification.Name {
    /// 切到首页「听力测试」segment（onboarding 首弹得分页 CTA / 任务深链用）
    static let switchToListeningTest = Notification.Name("castlingo.switchToListeningTest")
}

// MARK: - 数据模型

/// 每日播客听力测验（OSS: episodes/{level}/{id}/quiz.json，generate_episode_quiz.py 产出）
struct ListeningQuiz: Codable {
    let episodeId: String?
    let clipSeconds: Int?          // 出题依据的片段长度（90 或 150），试听播到这里为止
    let questions: [RawQuizQuestion]

    enum CodingKeys: String, CodingKey {
        case episodeId = "episode_id"
        case clipSeconds = "clip_seconds"
        case questions
    }
}

// MARK: - 成绩存储

/// 听力测验成绩：episodeId → 一次成绩（重考覆盖，保留最好成绩）。
@Observable
final class ListeningTestStore {
    static let shared = ListeningTestStore()

    struct TestRecord: Codable {
        let episodeId: String
        let level: String
        let episodeDate: String     // yyyy-MM-dd（episode.date，成绩单按它分组）
        var correct: Int
        var total: Int
        var completedAt: Date
    }

    private(set) var records: [String: TestRecord] = [:]
    /// 测试页各级别的集列表缓存（index 轻量集，带 audio URL + 日期）
    private(set) var levelEpisodes: [String: [Episode]] = [:]

    private let storageKey = "listeningTestRecords"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([String: TestRecord].self, from: data) {
            records = saved
        }
    }

    func record(for episodeId: String) -> TestRecord? { records[episodeId] }

    func save(episode: Episode, correct: Int, total: Int) {
        // 重考取最好成绩，completedAt 总是更新
        if var old = records[episode.id], old.correct >= correct {
            old.completedAt = Date()
            records[episode.id] = old
        } else {
            records[episode.id] = TestRecord(
                episodeId: episode.id,
                level: episode.level,
                episodeDate: episode.date,
                correct: correct,
                total: total,
                completedAt: Date()
            )
        }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// 拉某级别的集列表（服务器 index），供测试页展示今日测验 + 往期成绩单。
    @MainActor
    func loadEpisodes(for level: PodcastLevel) async {
        let eps = await APIService.shared.fetchEpisodes(for: level)
        guard !eps.isEmpty else { return }
        // 按日期倒序（新→旧），成绩单直接用
        levelEpisodes[level.rawValue] = eps.sorted { $0.date > $1.date }
    }

    /// 某级别「今日测验」的集：今天的第 1 集；没有今天的就用最新一集。
    /// 与任务深链「听一集」取 last(where:) 相反端，保证两格不同集（8/21 拍板）。
    func todayTestEpisode(for level: PodcastLevel) -> Episode? {
        guard let eps = levelEpisodes[level.rawValue], !eps.isEmpty else { return nil }
        let today = DateFormatter.episodeDate.string(from: Date())
        return eps.first { $0.date == today } ?? eps.first
    }
}

// MARK: - 共用答题卡（结算卡 + 听力测验共用）

/// 固定尺寸答题卡：全部题目透明叠放（高度取最高一题），题内解析/按钮恒定占位。
/// showsResult=true 时自带 🏆 结果页；false 时答完最后一题只回调 onFinished，
/// 由父级接管结果展示（听力测验的得分页有生词/分级建议等扩展内容）。
struct QuizFlowCard: View {
    let questions: [RawQuizQuestion]
    var showsResult = true
    var onFinished: ((Int) -> Void)? = nil   // 最后一题答完（correctCount）
    var onDone: () -> Void = {}              // 内置结果页「完成」

    @State private var questionIndex = 0
    @State private var selectedOption: Int?
    @State private var correctCount = 0
    @State private var showResult = false

    var body: some View {
        ZStack {
            ForEach(Array(questions.enumerated()), id: \.offset) { idx, q in
                questionView(q, index: idx)
                    .opacity(!showResult && idx == questionIndex ? 1 : 0)
                    .allowsHitTesting(!showResult && idx == questionIndex)
            }
            if showResult {
                resultView
            }
        }
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 24))
    }

    private func questionView(_ question: RawQuizQuestion, index: Int) -> some View {
        let selected = (index == questionIndex && !showResult) ? selectedOption : nil

        return VStack(alignment: .leading, spacing: 0) {
            Text("第 \(index + 1)/\(questions.count) 题")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .padding(.top, 22)

            Text(question.q)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.top, 8)

            VStack(spacing: 8) {
                ForEach(question.options.indices, id: \.self) { idx in
                    optionButton(question: question, idx: idx, selected: selected)
                }
            }
            .padding(.top, 14)

            Text(selected != nil ? (question.explainText ?? "") : " ")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .topLeading)
                .padding(.top, 6)

            Button {
                advance()
            } label: {
                Text(index + 1 >= questions.count ? "看结果" : "下一题")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(selected == nil ? Color.textTertiary : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        selected == nil ? Color.border : Color.appPrimary,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .disabled(selected == nil)
            .animation(.easeInOut(duration: 0.2), value: selected == nil)
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private func optionButton(question: RawQuizQuestion, idx: Int, selected: Int?) -> some View {
        let answered = selected != nil
        let isCorrect = idx == question.answer
        let isSelected = selected == idx

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
        if questionIndex + 1 >= questions.count {
            onFinished?(correctCount)
            if correctCount == questions.count {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            if showsResult {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showResult = true
                }
            }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                questionIndex += 1
                selectedOption = nil
            }
        }
    }

    private var resultView: some View {
        let allCorrect = correctCount == questions.count
        return VStack(spacing: 0) {
            Text(allCorrect ? "🏆" : "💪")
                .font(.system(size: 44))
                .padding(.top, 26)

            Text("\(correctCount)/\(questions.count)")
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 4)

            Text(allCorrect ? "全对！你真的听懂了" : "不错，明天再来一段")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 4)

            Button {
                onDone()
            } label: {
                Text("完成")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 18)
        }
    }
}

// MARK: - 试听片段播放器（独立 AVPlayer，播到 clipSeconds 自动停）

@Observable
final class ClipPlayer {
    let player: AVPlayer
    let clipEnd: Double
    var isPlaying = false
    var currentTime: Double = 0
    var reachedEnd = false
    private var timeObserver: Any?

    init(urlString: String, clipEnd: Double) {
        self.clipEnd = clipEnd
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        self.player = AVPlayer(url: URL(string: urlString) ?? URL(fileURLWithPath: "/dev/null"))
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let t = time.seconds.isFinite ? time.seconds : 0
            self.currentTime = t
            self.isPlaying = self.player.timeControlStatus == .playing
            if t >= self.clipEnd, !self.reachedEnd {
                self.reachedEnd = true
                self.player.pause()
            }
        }
    }

    func toggle() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            if reachedEnd {   // 重听：回到开头
                player.seek(to: .zero)
                reachedEnd = false
            }
            player.play()
        }
    }

    func tearDown() {
        player.pause()
        if let obs = timeObserver { player.removeTimeObserver(obs); timeObserver = nil }
    }
}

// MARK: - 测验全流程（试听 → 答题 → 得分页）

struct ListeningTestSessionView: View {
    let episode: Episode
    let source: String                        // home_tab / daily_task / onboarding_popup / history
    var onGoToTestTab: (() -> Void)? = nil    // 得分页「去今日听力测试」（onboarding 首弹用）
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    @Environment(VocabularyStore.self) private var vocabularyStore

    private enum Phase { case listening, quiz, score }
    @State private var phase: Phase = .listening
    @State private var quiz: ListeningQuiz?
    @State private var quizMissing = false
    @State private var clipPlayer: ClipPlayer?
    @State private var detailEpisode: Episode?       // 补拉的完整集（拿 vocabulary）
    @State private var score: Int = 0
    @State private var wordsSaved = false

    private var clipSeconds: Double { Double(quiz?.clipSeconds ?? 90) }
    private var level: PodcastLevel { episode.podcastLevel ?? .easy }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                switch phase {
                case .listening: listeningCard
                case .quiz:
                    QuizFlowCard(
                        questions: quiz?.questions ?? [],
                        showsResult: false,
                        onFinished: { correct in finish(correct: correct) }
                    )
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                case .score: scoreCard
                }
                Spacer(minLength: 0)
            }
        }
        .task {
            Analytics.track(.listeningTestStart, params: ["source": source, "episode_id": episode.id])
            quiz = await APIService.shared.fetchEpisodeQuiz(level: level.rawValue, episodeId: episode.id)
            if quiz == nil { quizMissing = true }
            detailEpisode = await APIService.shared.fetchEpisodeDetail(id: episode.id, level: level)
        }
        .onDisappear {
            clipPlayer?.tearDown()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("听力测验")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text(episode.title)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                if source == "onboarding_popup" {
                    Analytics.track(.onboardingTestSkip, params: ["at": phase == .listening ? "listening" : "quiz"])
                }
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: 试听

    private var listeningCard: some View {
        VStack(spacing: 0) {
            Text("🎧")
                .font(.system(size: 40))
                .padding(.top, 26)

            Text("先听 \(Int(clipSeconds >= 150 ? 150 : 90)) 秒")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 8)
            Text("听完回答 \(quiz?.questions.count ?? 3) 个问题，看看你听懂了多少")
                .font(.system(size: 13))
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 3)

            // 播放按钮 + 进度
            Button {
                if clipPlayer == nil {
                    clipPlayer = ClipPlayer(urlString: episode.audio.english, clipEnd: clipSeconds)
                }
                clipPlayer?.toggle()
            } label: {
                Image(systemName: clipPlayer?.isPlaying == true ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color.appPrimary))
            }
            .padding(.top, 22)

            ProgressView(value: min(clipPlayer?.currentTime ?? 0, clipSeconds), total: clipSeconds)
                .tint(Color.appPrimary)
                .padding(.horizontal, 40)
                .padding(.top, 18)

            // 听到结尾自动亮「开始答题」；也允许提前进入（听懂了就答）
            Button {
                clipPlayer?.player.pause()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    phase = .quiz
                }
            } label: {
                Text(quizMissing ? "本集测验暂未生成" : "开始答题")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(startEnabled ? .white : Color.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        startEnabled ? Color.appPrimary : Color.border,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .disabled(!startEnabled)
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 24)
    }

    /// 开始答题的门槛：题目已加载 且（听满片段 或 已听 ≥15 秒主动跳）
    private var startEnabled: Bool {
        guard quiz != nil else { return false }
        let t = clipPlayer?.currentTime ?? 0
        return (clipPlayer?.reachedEnd == true) || t >= 15
    }

    // MARK: 得分页

    private func finish(correct: Int) {
        score = correct
        let total = quiz?.questions.count ?? 3
        ListeningTestStore.shared.save(episode: episode, correct: correct, total: total)
        Analytics.track(.listeningTestComplete, params: [
            "source": source,
            "episode_id": episode.id,
            "level": level.rawValue,
            "correct_count": "\(correct)",
            "total": "\(total)"
        ])
        NotificationCenter.default.post(name: .taskEventListeningTestDone, object: nil)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            phase = .score
        }
    }

    private var scoreCard: some View {
        let total = quiz?.questions.count ?? 3
        let allCorrect = score == total
        let vocab = (detailEpisode?.vocabulary ?? []).prefix(6)

        return VStack(spacing: 0) {
            Text(allCorrect ? "🏆" : (score >= total - 1 ? "👏" : "💪"))
                .font(.system(size: 40))
                .padding(.top, 24)

            Text("\(score)/\(total)")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 2)

            Text(scoreCaption)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 2)
                .padding(.horizontal, 20)
                .multilineTextAlignment(.center)

            if !vocab.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(vocab), id: \.word) { item in
                        HStack(spacing: 10) {
                            Image(systemName: "character.book.closed.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.appPrimary)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.primaryLight))
                            Text(item.word)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                            Spacer(minLength: 8)
                            Text(item.translation)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Button {
                    guard !wordsSaved else { return }
                    for item in vocab { _ = vocabularyStore.addWord(item, sourceLabel: "listening_test") }
                    wordsSaved = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Text(wordsSaved ? "已加入生词本 ✓" : "全部加入生词本")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(wordsSaved ? Color.success : Color.appPrimary)
                }
                .padding(.top, 10)
            }

            // 新用户首弹：得分 → 级别建议 + 去听力测试页
            if source == "onboarding_popup" {
                if let suggestion = levelSuggestion {
                    Text(suggestion.text)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.appPrimary)
                        .padding(.top, 12)
                        .padding(.horizontal, 20)
                        .multilineTextAlignment(.center)
                }
                Button {
                    if let target = levelSuggestion?.level { dataStore.selectedLevel = target }
                    dismiss()
                    onGoToTestTab?()
                } label: {
                    Text("去今日听力测试")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }

            Button {
                dismiss()
            } label: {
                Text("完成")
                    .font(.system(size: source == "onboarding_popup" ? 14 : 16, weight: source == "onboarding_popup" ? .medium : .bold))
                    .foregroundStyle(source == "onboarding_popup" ? Color.textSecondary : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: source == "onboarding_popup" ? 40 : 48)
                    .background(
                        source == "onboarding_popup" ? Color.clear : Color.appPrimary,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.top, source == "onboarding_popup" ? 2 : 16)
            .padding(.bottom, 18)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 24)
        .transition(.scale(scale: 0.94).combined(with: .opacity))
    }

    private var scoreCaption: String {
        let total = quiz?.questions.count ?? 3
        if score == total { return String(localized: "全对！你真的听懂了") }
        if score >= total - 1 { return String(localized: "不错，就差一点点") }
        return String(localized: "多听几遍就会更好")
    }

    /// 新用户分级建议（仅 onboarding 首弹 + Easy 集）：3/3 → 中级；≤1 → 初级。
    private var levelSuggestion: (text: String, level: PodcastLevel?)? {
        guard source == "onboarding_popup", level == .easy else { return nil }
        let total = quiz?.questions.count ?? 3
        if score >= total {
            return (String(localized: "你的听力不错！建议从「中级」开始"), .medium)
        }
        if score <= 1 {
            return (String(localized: "建议从「初级」开始，稳步提升"), .easy)
        }
        return (String(localized: "当前级别正适合你，继续保持"), nil)
    }
}

// MARK: - 首页「听力测试」segment

struct ListeningTestSegmentView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(SubscriptionManager.self) private var subscriptionManager

    @State private var sessionEpisode: Episode?
    @State private var sessionSource = "home_tab"
    @State private var showPaywall = false

    private var store: ListeningTestStore { ListeningTestStore.shared }
    private var userLevel: PodcastLevel { dataStore.selectedLevel }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 20) {
                todayHero
                otherLevelsRow
                historySection
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .task {
            for level in PodcastLevel.allCases where store.levelEpisodes[level.rawValue] == nil {
                await store.loadEpisodes(for: level)
            }
        }
        .fullScreenCover(item: $sessionEpisode) { ep in
            ListeningTestSessionView(episode: ep, source: sessionSource)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(subscriptionManager)
        }
    }

    // MARK: 今日测验 hero

    @ViewBuilder
    private var todayHero: some View {
        if let ep = store.todayTestEpisode(for: userLevel) {
            let record = store.record(for: ep.id)
            Button {
                sessionSource = "home_tab"
                sessionEpisode = ep
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("今日听力测验")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Text(userLevel.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.22), in: Capsule())
                    }
                    Text(ep.title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.top, 10)
                    HStack(spacing: 8) {
                        if let record {
                            Label("\(record.correct)/\(record.total)", systemImage: "checkmark.seal.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                            Text("再测一次")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.8))
                        } else {
                            Label(String(localized: "约 2 分钟 · 听 90 秒答 3 题"), systemImage: "headphones")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 14)
                }
                .padding(18)
                .background(
                    LinearGradient(colors: [Color.appPrimary, Color(hex: "2563EB")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20)
                )
            }
            .buttonStyle(.plain)
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .frame(height: 120)
                .overlay(
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("今日测验加载中…")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textSecondary)
                    }
                )
        }
    }

    // MARK: 其他级别

    @ViewBuilder
    private var otherLevelsRow: some View {
        let others = PodcastLevel.allCases.filter { $0 != userLevel }
        HStack(spacing: 10) {
            ForEach(others, id: \.self) { level in
                if let ep = store.todayTestEpisode(for: level) {
                    let record = store.record(for: ep.id)
                    Button {
                        sessionSource = "home_tab"
                        sessionEpisode = ep
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(level.displayName)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.textPrimary)
                            Text(record != nil ? "\(record!.correct)/\(record!.total)" : String(localized: "挑战一下"))
                                .font(.system(size: 11))
                                .foregroundStyle(record != nil ? Color.success : Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 往期成绩单

    @ViewBuilder
    private var historySection: some View {
        let eps = Array((store.levelEpisodes[userLevel.rawValue] ?? []).prefix(14))
        if !eps.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("成绩单")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                VStack(spacing: 6) {
                    ForEach(eps) { ep in
                        historyRow(ep)
                    }
                }
            }
        }
    }

    private func historyRow(_ ep: Episode) -> some View {
        let record = store.record(for: ep.id)
        let today = DateFormatter.episodeDate.string(from: Date())
        let locked = ep.date != today && !subscriptionManager.isProUser

        return Button {
            if locked {
                Analytics.track(.paywallView, params: ["source": "listening_test_history"])
                showPaywall = true
            } else {
                sessionSource = "history"
                sessionEpisode = ep
            }
        } label: {
            HStack(spacing: 12) {
                // 得分徽章：🟢全对 🟡部分 ⚪未做
                Group {
                    if let record {
                        Text("\(record.correct)/\(record.total)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(record.correct == record.total ? Color.success : Color.warning)
                            .frame(width: 38, height: 38)
                            .background(
                                Circle().fill(record.correct == record.total ? Color.successLight : Color.warningLight)
                            )
                    } else {
                        Circle()
                            .stroke(Color.border, style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                            .frame(width: 38, height: 38)
                            .overlay(
                                Image(systemName: locked ? "lock.fill" : "headphones")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.textTertiary)
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(ep.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(ep.dateDisplay)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textQuaternary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 新用户首弹卡（替代新用户首次的今日计划弹窗）

struct OnboardingTestIntroCard: View {
    var onStart: () -> Void
    var onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onSkip() }

            VStack(spacing: 0) {
                Text("🎧")
                    .font(.system(size: 40))
                    .padding(.top, 26)
                Text("测测你的听力水平")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.top, 10)
                Text("听 90 秒真实语速的英语对话\n回答 3 个问题，马上知道你该从哪一级开始")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.top, 6)
                    .padding(.horizontal, 20)

                Button {
                    onStart()
                } label: {
                    Text("开始测试")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Button {
                    onSkip()
                } label: {
                    Text("先逛逛")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .frame(height: 36)
                }
                .padding(.bottom, 12)
            }
            .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 36)
        }
    }
}
