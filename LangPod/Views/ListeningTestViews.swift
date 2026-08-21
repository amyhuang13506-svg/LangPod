import SwiftUI
import AVFoundation
import UIKit

extension Notification.Name {
    /// 切到首页「听测」segment（onboarding 首弹得分页 CTA / 任务深链用）
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

private extension PodcastLevel {
    var nextUp: PodcastLevel? {
        switch self { case .easy: .medium; case .medium: .hard; case .hard: nil }
    }
    var nextDown: PodcastLevel? {
        switch self { case .easy: nil; case .medium: .easy; case .hard: .medium }
    }
}

// MARK: - 成绩 + 等级爬坡存储

/// 听力测验状态：成绩（episodeId → 最好成绩）+ 等级爬坡（升降由成绩驱动）。
@Observable
final class ListeningTestStore {
    static let shared = ListeningTestStore()

    /// 连续 N 套全对升级 / 连续 N 套 ≤1 题降级
    static let ladderThreshold = 3

    struct TestRecord: Codable {
        let episodeId: String
        let level: String
        let episodeDate: String     // yyyy-MM-dd（episode.date）
        var correct: Int
        var total: Int
        var completedAt: Date
    }

    struct LevelChange: Equatable {
        let to: PodcastLevel
        let isUp: Bool
    }

    private(set) var records: [String: TestRecord] = [:]
    /// 各级别集列表缓存（index 轻量集，带 audio URL + 日期，日期新→旧）
    private(set) var levelEpisodes: [String: [Episode]] = [:]

    // 爬坡状态（UserDefaults 持久化）
    private(set) var testLevel: PodcastLevel = .easy
    private(set) var consecutivePerfect: Int = 0
    private(set) var consecutivePoor: Int = 0
    /// 刚发生的升/降级，等 UI（得分页）消费展示
    private(set) var pendingLevelChange: LevelChange?

    private let storageKey = "listeningTestRecords"
    private let levelKey = "listeningTestLevel"
    private let perfectKey = "listeningTestPerfectStreak"
    private let poorKey = "listeningTestPoorStreak"
    private let initializedKey = "listeningTestLevelInitialized"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([String: TestRecord].self, from: data) {
            records = saved
        }
        if let raw = UserDefaults.standard.string(forKey: levelKey),
           let level = PodcastLevel(rawValue: raw) {
            testLevel = level
        }
        consecutivePerfect = UserDefaults.standard.integer(forKey: perfectKey)
        consecutivePoor = UserDefaults.standard.integer(forKey: poorKey)
    }

    // MARK: 爬坡

    /// 首次进听测页：用学习级别作为爬坡起点（只设一次）。
    func initializeLevelIfNeeded(from level: PodcastLevel) {
        guard !UserDefaults.standard.bool(forKey: initializedKey) else { return }
        setTestLevel(level)
    }

    /// 显式设置爬坡等级（onboarding 分级测试的建议也走这里），双计数清零。
    func setTestLevel(_ level: PodcastLevel) {
        testLevel = level
        consecutivePerfect = 0
        consecutivePoor = 0
        persistLadder()
        UserDefaults.standard.set(true, forKey: initializedKey)
    }

    func consumeLevelChange() -> LevelChange? {
        let change = pendingLevelChange
        pendingLevelChange = nil
        return change
    }

    private func persistLadder() {
        UserDefaults.standard.set(testLevel.rawValue, forKey: levelKey)
        UserDefaults.standard.set(consecutivePerfect, forKey: perfectKey)
        UserDefaults.standard.set(consecutivePoor, forKey: poorKey)
    }

    // MARK: 成绩

    func record(for episodeId: String) -> TestRecord? { records[episodeId] }

    func save(episode: Episode, correct: Int, total: Int) {
        // 24 小时内重测同一集不计爬坡（防"刷同一集升级"；隔天重测正常计入）。
        // 必须在覆盖 records 之前取旧的 completedAt。
        let isRecentRetest = records[episode.id].map {
            Date().timeIntervalSince($0.completedAt) < 24 * 3600
        } ?? false

        // 成绩取最好，completedAt 总是更新
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

        // 爬坡记账：只统计当前爬坡等级的测验（本次实际成绩，不是历史最好）；
        // 24 小时内重测不计（见上）
        guard !isRecentRetest, episode.level == testLevel.rawValue else { return }
        if correct == total {
            consecutivePerfect += 1
            consecutivePoor = 0
        } else if correct <= 1 {
            consecutivePoor += 1
            consecutivePerfect = 0
        } else {
            consecutivePerfect = 0
            consecutivePoor = 0
        }
        if consecutivePerfect >= Self.ladderThreshold, let up = testLevel.nextUp {
            testLevel = up
            consecutivePerfect = 0
            consecutivePoor = 0
            pendingLevelChange = LevelChange(to: up, isUp: true)
            Analytics.track(.listeningTestComplete, params: ["ladder": "up", "to": up.rawValue])
        } else if consecutivePoor >= Self.ladderThreshold, let down = testLevel.nextDown {
            testLevel = down
            consecutivePerfect = 0
            consecutivePoor = 0
            pendingLevelChange = LevelChange(to: down, isUp: false)
            Analytics.track(.listeningTestComplete, params: ["ladder": "down", "to": down.rawValue])
        }
        persistLadder()
    }

    // MARK: 集列表 + 队列

    @MainActor
    func loadEpisodes(for level: PodcastLevel) async {
        let eps = await APIService.shared.fetchEpisodes(for: level)
        guard !eps.isEmpty else { return }
        levelEpisodes[level.rawValue] = eps.sorted { $0.date > $1.date }
    }

    /// 某级别「今日测验」的集：今天的第 1 集；没有今天的就用最新一集。
    /// 与任务深链「听一集」取 last(where:) 相反端，保证两格不同集（8/21 拍板）。
    func todayTestEpisode(for level: PodcastLevel) -> Episode? {
        guard let eps = levelEpisodes[level.rawValue], !eps.isEmpty else { return nil }
        let today = DateFormatter.episodeDate.string(from: Date())
        return eps.first { $0.date == today } ?? eps.first
    }

    /// 沉浸式连续测的下一集：当前爬坡等级，未测集优先（日期新→旧），
    /// 全测过则接列表里的下一条循环重测。避免返回同一集。
    func nextEpisode(after episodeId: String, level: PodcastLevel) -> Episode? {
        guard let eps = levelEpisodes[level.rawValue], !eps.isEmpty else { return nil }
        if let untested = eps.first(where: { records[$0.id] == nil && $0.id != episodeId }) {
            return untested
        }
        guard let idx = eps.firstIndex(where: { $0.id == episodeId }) else {
            return eps.first?.id == episodeId ? nil : eps.first
        }
        let next = eps[(idx + 1) % eps.count]
        return next.id == episodeId ? nil : next
    }

    // MARK: 统计

    var totalTested: Int { records.count }

    /// 全对率（%）
    var perfectRate: Int {
        guard !records.isEmpty else { return 0 }
        let perfect = records.values.filter { $0.correct == $0.total }.count
        return Int((Double(perfect) / Double(records.count) * 100).rounded())
    }

    /// 连续测验天数（今天没测则从昨天起算）
    var consecutiveTestDays: Int {
        let cal = Calendar.current
        let days = Set(records.values.map { cal.startOfDay(for: $0.completedAt) })
        guard !days.isEmpty else { return 0 }
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: day),
                  days.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    enum DayDotState { case perfect, partial, none }
    struct DayDot: Identifiable {
        let id: Int
        let label: String
        let state: DayDotState
        let isToday: Bool
    }

    /// 近 7 天圆点（🟢当日有全对 🟡测过有错 ⚪未测）
    func weekDots() -> [DayDot] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.dateFormat = "E"
        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let recs = records.values.filter { cal.isDate($0.completedAt, inSameDayAs: day) }
            let state: DayDotState = recs.isEmpty
                ? .none
                : (recs.contains { $0.correct == $0.total } ? .perfect : .partial)
            return DayDot(id: offset, label: fmt.string(from: day), state: state, isToday: offset == 0)
        }
    }
}

// MARK: - 共用答题卡（结算卡 + 听力测验共用）

/// 固定尺寸答题卡：全部题目透明叠放（高度取最高一题），题内解析/按钮恒定占位。
/// showsResult=true 时自带 🏆 结果页；false 时答完最后一题只回调 onFinished，
/// 由父级接管结果展示（听力测验的得分页有生词/升降级/下一集等扩展内容）。
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
    private(set) var clipEnd: Double
    var isPlaying = false
    var currentTime: Double = 0
    var reachedEnd = false
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    /// 集音频真实时长（index 提供）：盲听窗口的硬上限，任何来源的设置都不能超过它
    private let durationCap: Double?

    init(urlString: String, clipEnd: Double, durationCap: Double? = nil) {
        self.durationCap = durationCap
        self.clipEnd = durationCap.map { min(clipEnd, $0) } ?? clipEnd
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        self.player = AVPlayer(url: URL(string: urlString) ?? URL(fileURLWithPath: "/dev/null"))
        // 纯音频快速起播（不等长缓冲）
        self.player.automaticallyWaitsToMinimizeStalling = false
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let t = time.seconds.isFinite ? time.seconds : 0
            self.currentTime = t
            self.isPlaying = self.player.timeControlStatus == .playing
            // 音频本身比盲听窗口短（Easy 集常见 20-80 秒 < 90 秒）：
            // 片段终点收敛到真实时长，进度条 total 跟着变准
            if let d = self.player.currentItem?.duration.seconds,
               d.isFinite, d > 1, d < self.clipEnd {
                self.clipEnd = d
            }
            if t >= self.clipEnd, !self.reachedEnd {
                self.reachedEnd = true
                self.player.pause()
                self.isPlaying = false   // 周期回调暂停后不再触发，这里手动收尾
            }
        }
        // 播到文件尾（时长信息未就绪时的兜底）：视为片段结束 → 自动进答题
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.currentTime > 1 { self.clipEnd = min(self.clipEnd, self.currentTime) }
            self.reachedEnd = true
            self.isPlaying = false
        }
    }

    /// quiz.json 晚于首次点播到达时校正片段长度（90 → 150 等）。
    /// 已提前停在旧终点的允许继续播到新终点。
    func updateClipEnd(_ end: Double) {
        let capped = durationCap.map { min(end, $0) } ?? end
        guard capped > 0, capped != clipEnd else { return }
        clipEnd = capped
        if currentTime < capped { reachedEnd = false }
    }

    func toggle() {
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            if reachedEnd {   // 重听：回到开头
                player.seek(to: .zero)
                reachedEnd = false
            }
            player.play()
            isPlaying = true
        }
    }

    func tearDown() {
        player.pause()
        if let obs = timeObserver { player.removeTimeObserver(obs); timeObserver = nil }
        if let end = endObserver { NotificationCenter.default.removeObserver(end); endObserver = nil }
    }
}

// MARK: - 测验全流程（试听 → 答题 → 得分 → 自动下一集，沉浸式连续测）

struct ListeningTestSessionView: View {
    let source: String                        // home_tab / daily_task / onboarding_popup / history
    var onGoToTestTab: (() -> Void)? = nil    // 得分页「去今日听力测试」（onboarding 首弹用）
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(SubscriptionManager.self) private var subscriptionManager

    private enum Phase { case listening, quiz, score }
    @State private var currentEpisode: Episode
    @State private var phase: Phase = .listening
    @State private var quiz: ListeningQuiz?
    @State private var quizMissing = false
    @State private var clipPlayer: ClipPlayer?
    @State private var detailEpisode: Episode?       // 补拉的完整集（拿 vocabulary）
    @State private var score: Int = 0
    @State private var wordsSaved = false
    @State private var levelChange: ListeningTestStore.LevelChange?
    @State private var nextInQueue: Episode?
    @State private var showPaywall = false
    @State private var loadTask: Task<Void, Never>?

    init(episode: Episode, source: String, onGoToTestTab: (() -> Void)? = nil) {
        self.source = source
        self.onGoToTestTab = onGoToTestTab
        _currentEpisode = State(initialValue: episode)
    }

    private var clipSeconds: Double { Double(quiz?.clipSeconds ?? 90) }
    private var level: PodcastLevel { currentEpisode.podcastLevel ?? .easy }

    /// 盲听 = 听整集（8/22 用户拍板：不设 90 秒窗口，进度条就是真实全长）。
    /// index 时长缺失时先给个上限，播放器拿到真实时长后自动收敛。
    private var fullDuration: Double {
        let d = Double(currentEpisode.durationSeconds)
        return d > 5 ? d : 600
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                stepIndicator
                    .padding(.top, 14)
                    .padding(.horizontal, 24)
                switch phase {
                case .listening:
                    blindListeningPage
                case .quiz:
                    Spacer(minLength: 0)
                    QuizFlowCard(
                        questions: quiz?.questions ?? [],
                        showsResult: false,
                        onFinished: { correct in finish(correct: correct) }
                    )
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    Spacer(minLength: 0)
                case .score:
                    scorePage
                }
            }
        }
        .task {
            await loadContent()
        }
        .onChange(of: clipPlayer?.reachedEnd) { _, reached in
            // 听完片段自动进入答题——不用再点按钮（有题时）
            guard reached == true, quiz != nil, phase == .listening else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                phase = .quiz
            }
        }
        .onDisappear {
            loadTask?.cancel()
            clipPlayer?.tearDown()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(subscriptionManager)
        }
    }

    /// 每一集的内容加载（初始 + 连续测切集都走这里）
    private func loadContent() async {
        Analytics.track(.listeningTestStart, params: ["source": source, "episode_id": currentEpisode.id])
        quiz = await APIService.shared.fetchEpisodeQuiz(level: level.rawValue, episodeId: currentEpisode.id)
        if quiz == nil { quizMissing = true }
        detailEpisode = await APIService.shared.fetchEpisodeDetail(id: currentEpisode.id, level: level)
    }

    /// 沉浸流：切到下一集，重置全部会话状态
    private func advance(to next: Episode) {
        clipPlayer?.tearDown()
        clipPlayer = nil
        quiz = nil
        quizMissing = false
        detailEpisode = nil
        score = 0
        wordsSaved = false
        levelChange = nil
        nextInQueue = nil
        currentEpisode = next
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            phase = .listening
        }
        loadTask?.cancel()
        loadTask = Task { await loadContent() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("听力测验")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(level.tabName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.appPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.primaryLight, in: Capsule())
                }
                Text(currentEpisode.title)
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

    // MARK: 步骤指示（盲听 → 答题 → 看原文）

    private var stepIndicator: some View {
        let steps: [(String, Phase)] = [
            (String(localized: "盲听"), .listening),
            (String(localized: "答题"), .quiz),
            (String(localized: "看原文"), .score)
        ]
        let currentIndex = steps.firstIndex { $0.1 == phase } ?? 0

        return HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { i in
                let active = i == currentIndex
                let done = i < currentIndex
                HStack(spacing: 5) {
                    Group {
                        if done {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.success)
                        } else {
                            Text("\(i + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(active ? .white : Color.textTertiary)
                                .frame(width: 16, height: 16)
                                .background(Circle().fill(active ? Color.appPrimary : Color.border))
                        }
                    }
                    Text(steps[i].0)
                        .font(.system(size: 12, weight: active ? .bold : .medium))
                        .foregroundStyle(active ? Color.textPrimary : Color.textTertiary)
                }
                if i < steps.count - 1 {
                    Rectangle()
                        .fill(i < currentIndex ? Color.success : Color.border)
                        .frame(height: 1.5)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: ① 盲听（整页）

    private var blindListeningPage: some View {
        VStack(spacing: 0) {
            Spacer()

            WaveformBars(isActive: clipPlayer?.isPlaying == true)

            Text("盲听整集 · \(currentEpisode.durationDisplay)")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 26)
            Text("不看字幕，抓大意就好\n听完回答 \(quiz?.questions.count ?? 3) 个问题")
                .font(.system(size: 13.5))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 6)

            Button {
                if clipPlayer == nil {
                    clipPlayer = ClipPlayer(urlString: currentEpisode.audio.english, clipEnd: fullDuration)
                }
                clipPlayer?.toggle()
            } label: {
                Image(systemName: clipPlayer?.isPlaying == true ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .background(Circle().fill(Color.appPrimary))
                    .shadow(color: Color.appPrimary.opacity(0.35), radius: 16, y: 6)
            }
            .padding(.top, 32)

            // total 用 player 的 clipEnd（单一事实源），避免 quiz 晚到时 90/150 对不上
            VStack(spacing: 6) {
                ProgressView(
                    value: min(clipPlayer?.currentTime ?? 0, clipPlayer?.clipEnd ?? fullDuration),
                    total: clipPlayer?.clipEnd ?? fullDuration
                )
                .tint(Color.appPrimary)
                HStack {
                    Text(timeString(clipPlayer?.currentTime ?? 0))
                    Spacer()
                    Text(timeString(clipPlayer?.clipEnd ?? fullDuration))
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
                .monospacedDigit()
            }
            .padding(.horizontal, 44)
            .padding(.top, 26)

            Spacer()

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
                    .frame(height: 50)
                    .background(
                        startEnabled ? Color.appPrimary : Color.border,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .disabled(!startEnabled)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// 开始答题的门槛：题目已加载 且（听满片段 或 已听 ≥15 秒主动跳）
    private var startEnabled: Bool {
        guard quiz != nil else { return false }
        let t = clipPlayer?.currentTime ?? 0
        return (clipPlayer?.reachedEnd == true) || t >= 15
    }

    // MARK: 得分

    private func finish(correct: Int) {
        score = correct
        let total = quiz?.questions.count ?? 3
        let store = ListeningTestStore.shared
        store.save(episode: currentEpisode, correct: correct, total: total)
        levelChange = store.consumeLevelChange()
        Analytics.track(.listeningTestComplete, params: [
            "source": source,
            "episode_id": currentEpisode.id,
            "level": level.rawValue,
            "correct_count": "\(correct)",
            "total": "\(total)"
        ])
        NotificationCenter.default.post(name: .taskEventListeningTestDone, object: nil)

        // 沉浸流：备好下一集（升/降级后用新等级的队列；手动点击进入，不自动跳）
        if source != "onboarding_popup" {
            nextInQueue = store.nextEpisode(after: currentEpisode.id, level: store.testLevel)
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            phase = .score
        }
    }

    private func isLocked(_ episode: Episode) -> Bool {
        episode.date != DateFormatter.episodeDate.string(from: Date()) && !subscriptionManager.isProUser
    }

    /// ③ 得分 + 原文（整页滚动）：分数 → 盲听内容的原文对照（可重听）→ 生词 → 下一集
    private var scorePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                scoreHeaderCard
                vocabCard
                if source == "onboarding_popup" {
                    onboardingScoreFooter
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                } else {
                    immersiveScoreFooter
                }
                transcriptCard
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .transition(.opacity)
    }

    private var scoreHeaderCard: some View {
        let total = quiz?.questions.count ?? 3
        let allCorrect = score == total

        return VStack(spacing: 0) {
            // 升/降级提示（在分数上方，最强信息优先）
            if let change = levelChange {
                HStack(spacing: 10) {
                    Text(change.isUp ? "🎉" : "💪")
                        .font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(change.isUp
                             ? "连续 \(ListeningTestStore.ladderThreshold) 套全对，升入「\(change.to.tabName)」！"
                             : "回到「\(change.to.tabName)」打牢基础")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(change.isUp ? Color.success : Color.textPrimary)
                        Text("接下来的测验按新等级出题")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(change.isUp ? Color.successLight : Color.warningLight,
                            in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }

            Text(allCorrect ? "🏆" : (score >= total - 1 ? "👏" : "💪"))
                .font(.system(size: 40))
                .padding(.top, levelChange == nil ? 24 : 10)

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
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: 原文对照（答完题才揭晓，可对照重听）

    /// 整集原文（盲听听的就是整集，原文对照也给全量；上限兜底防极端长脚本）
    private var clipScriptLines: [ScriptLine] {
        guard let script = detailEpisode?.script, !script.isEmpty else { return [] }
        return Array(script.prefix(80))
    }

    @ViewBuilder
    private var transcriptCard: some View {
        let lines = clipScriptLines
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("原文")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("刚才你听到的")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Button {
                        if clipPlayer == nil {
                            clipPlayer = ClipPlayer(urlString: currentEpisode.audio.english, clipEnd: fullDuration)
                        }
                        clipPlayer?.toggle()
                    } label: {
                        Label(clipPlayer?.isPlaying == true ? String(localized: "暂停") : String(localized: "重听一遍"),
                              systemImage: clipPlayer?.isPlaying == true ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.appPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primaryLight, in: Capsule())
                    }
                }
                .padding(.bottom, 12)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(lines) { line in
                        transcriptRow(line)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func transcriptRow(_ line: ScriptLine) -> some View {
        // 重听时高亮当前句
        let isActive: Bool = {
            guard clipPlayer?.isPlaying == true,
                  let s = line.start, let e = line.end,
                  let t = clipPlayer?.currentTime else { return false }
            return t >= s && t <= e
        }()

        return VStack(alignment: .leading, spacing: 2) {
            Text(line.speaker)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.appPrimary.opacity(0.8))
            Text(line.text)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(line.translation)
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isActive ? Color.primaryLight : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    // MARK: 生词卡

    @ViewBuilder
    private var vocabCard: some View {
        let vocab = (detailEpisode?.vocabulary ?? []).prefix(6)
        if !vocab.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Text("本集生词")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Button {
                        guard !wordsSaved else { return }
                        for item in vocab { _ = vocabularyStore.addWord(item, sourceLabel: "listening_test") }
                        wordsSaved = true
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Text(wordsSaved ? "已加入生词本 ✓" : "全部加入生词本")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(wordsSaved ? Color.success : Color.appPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(wordsSaved ? Color.successLight : Color.primaryLight, in: Capsule())
                    }
                }
                .padding(.bottom, 10)

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
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    /// 沉浸流底部：下一集（倒计时自动）/ 解锁 / 关闭
    @ViewBuilder
    private var immersiveScoreFooter: some View {
        VStack(spacing: 8) {
            if let next = nextInQueue {
                if isLocked(next) {
                    Button {
                        Analytics.track(.paywallView, params: ["source": "listening_test_flow"])
                        showPaywall = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("解锁往期，继续连测")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
                    }
                } else {
                    Button {
                        advance(to: next)
                    } label: {
                        HStack(spacing: 8) {
                            Text("下一集：\(next.title)")
                                .font(.system(size: 15, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    /// 新用户首弹底部：级别建议 + 去听测页
    @ViewBuilder
    private var onboardingScoreFooter: some View {
        VStack(spacing: 2) {
            if let suggestion = levelSuggestion {
                Text(suggestion.text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
                    .padding(.top, 12)
                    .padding(.horizontal, 20)
                    .multilineTextAlignment(.center)
            }
            Button {
                if let target = levelSuggestion?.level {
                    dataStore.selectedLevel = target
                    ListeningTestStore.shared.setTestLevel(target)   // 爬坡起点同步
                }
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
            .padding(.bottom, 16)
        }
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

// MARK: - 盲听波形动画（播放时跳动，暂停时静止）

private struct WaveformBars: View {
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isActive)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<9, id: \.self) { i in
                    Capsule()
                        .fill(Color.appPrimary.opacity(isActive ? 0.9 : 0.35))
                        .frame(width: 5, height: barHeight(i: i, t: t))
                }
            }
        }
        .frame(height: 56)
        .animation(.easeInOut(duration: 0.25), value: isActive)
    }

    private func barHeight(i: Int, t: TimeInterval) -> CGFloat {
        guard isActive else { return 16 }
        let phase = t * 3.2 + Double(i) * 0.85
        let wobble = sin(phase) * sin(phase * 0.63 + Double(i))
        return 16 + CGFloat(abs(wobble)) * 38
    }
}

// MARK: - 首页「听测」segment（统计条 + 本周日历 + 等级爬坡卡 + 听力库）

struct ListeningTestSegmentView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(SubscriptionManager.self) private var subscriptionManager

    @State private var sessionEpisode: Episode?
    @State private var sessionSource = "home_tab"
    @State private var showPaywall = false
    @State private var filterLevel: PodcastLevel?   // nil = 全部

    private var store: ListeningTestStore { ListeningTestStore.shared }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                statsBar
                weekRow
                ladderCard
                librarySection
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .task {
            store.initializeLevelIfNeeded(from: dataStore.selectedLevel)
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

    // MARK: ① 统计条

    private var statsBar: some View {
        HStack(spacing: 10) {
            statTile(value: "\(store.totalTested)", label: String(localized: "已测套数"))
            statTile(value: "\(store.perfectRate)%", label: String(localized: "全对率"))
            statTile(value: "\(store.consecutiveTestDays)", label: String(localized: "连续天数"))
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: ② 本周日历行

    private var weekRow: some View {
        HStack(spacing: 0) {
            ForEach(store.weekDots()) { dot in
                VStack(spacing: 5) {
                    Circle()
                        .fill(dotColor(dot.state))
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle().stroke(dot.isToday ? Color.appPrimary : .clear, lineWidth: 2)
                                .frame(width: 18, height: 18)
                        )
                    Text(dot.label)
                        .font(.system(size: 10))
                        .foregroundStyle(dot.isToday ? Color.appPrimary : Color.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private func dotColor(_ state: ListeningTestStore.DayDotState) -> Color {
        switch state {
        case .perfect: Color.success
        case .partial: Color.warning
        case .none: Color.border
        }
    }

    // MARK: ③ 等级爬坡卡（panel_layered_assets 设计稿实现）

    private static let panelDeep = Color(hex: "102A72")
    private static let panelMid = Color(hex: "1749C7")
    private static let panelViolet = Color(hex: "6355F6")
    private static let panelStroke = Color(hex: "7E8CFF")
    private static let panelInnerStroke = Color(hex: "8EA1FF")
    private static let panelSecondaryText = Color(hex: "C4CBEE")
    private static let panelYellow = Color(hex: "FFE65C")
    private static let panelCTABlue = Color(hex: "4652E8")

    @ViewBuilder
    private var ladderCard: some View {
        let level = store.testLevel
        let todayEp = store.todayTestEpisode(for: level)
        let record = todayEp.flatMap { store.record(for: $0.id) }

        VStack(alignment: .leading, spacing: 0) {
            // 头部：等级宝珠 + 等级/规则 + 升级进度点
            HStack(alignment: .center, spacing: 14) {
                levelOrb(level)

                VStack(alignment: .leading, spacing: 2) {
                    Text("当前等级")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Self.panelSecondaryText)
                    Text(level.tabName)
                        .font(.system(size: 25, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(highlightDigits(ladderRuleText, size: 12))
                        .foregroundStyle(Self.panelSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if level.nextUp != nil {
                    HStack(spacing: 6) {
                        ForEach(0..<ListeningTestStore.ladderThreshold, id: \.self) { i in
                            Circle()
                                .fill(i < store.consecutivePerfect ? Color.white : Color.white.opacity(0.28))
                                .frame(width: 9, height: 9)
                        }
                    }
                }
            }

            if store.consecutivePoor > 0 {
                Text("⚠️ 已连续 \(store.consecutivePoor)/\(ListeningTestStore.ladderThreshold) 套 ≤1 题")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Self.panelYellow)
                    .padding(.top, 6)
            }

            Divider()
                .overlay(Color.white.opacity(0.22))
                .padding(.vertical, 14)

            if let ep = todayEp {
                quizPanel(ep, record: record)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("今日测验加载中…")
                        .font(.system(size: 13))
                        .foregroundStyle(Self.panelSecondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Color.appPrimary, Color(hex: "2563EB")],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }

    /// 等级宝珠：外圈紫环 + 内层渐变珠（绿/黄/红对应初/中/高）+ 高光 + 星芒
    private func levelOrb(_ level: PodcastLevel) -> some View {
        let colors: [Color] = switch level {
        case .easy: [Color(hex: "B6FF8C"), Color(hex: "34E553"), Color(hex: "0CAD2E")]
        case .medium: [Color(hex: "FFF3A0"), Color(hex: "FFD93B"), Color(hex: "E0A800")]
        case .hard: [Color(hex: "FF9C8C"), Color(hex: "F5544D"), Color(hex: "C21F1F")]
        }
        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.16))
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.2))
                .frame(width: 42, height: 42)
            Circle()
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 29, height: 29)
            Circle()
                .fill(Color.white.opacity(0.5))
                .frame(width: 8, height: 8)
                .offset(x: -5, y: -6)
            Image(systemName: "sparkle")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: 13, y: -14)
        }
    }

    /// 今日测验内嵌面板：封面 + chip + 标题 + 副标题 + 白圆箭头 CTA
    private func quizPanel(_ ep: Episode, record: ListeningTestStore.TestRecord?) -> some View {
        Button {
            sessionSource = "home_tab"
            sessionEpisode = ep
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let thumb = ep.thumbnail, !thumb.isEmpty {
                        CachedAsyncImage(url: thumb) { thumbFallback }
                            .scaledToFill()
                    } else {
                        thumbFallback
                    }
                }
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text(record != nil
                         ? "\(record!.correct)/\(record!.total) · 再测一次"
                         : String(localized: "今日测验"))
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                    Text(ep.title)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: "headphones")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.75))
                        Text(highlightDigits(String(localized: "盲听整集 · 答 3 题"), size: 12))
                            .foregroundStyle(Self.panelSecondaryText)
                    }
                }

                Spacer(minLength: 8)

                ZStack {
                    Circle().fill(Color.white.opacity(0.14)).frame(width: 52, height: 52)
                    Circle().fill(.white).frame(width: 42, height: 42)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.appPrimary)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var thumbFallback: some View {
        LinearGradient(colors: [Color(hex: "6355F6"), Color(hex: "2947A6")],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(
                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            )
    }

    /// 文案里的数字用设计稿黄色 #FFE65C 加粗高亮（六语言通用，不依赖词序）
    private func highlightDigits(_ text: String, size: CGFloat) -> AttributedString {
        var attr = AttributedString(text)
        attr.font = .system(size: size)
        var idx = attr.startIndex
        while idx < attr.endIndex {
            let next = attr.index(afterCharacter: idx)
            if attr.characters[idx].isNumber {
                attr[idx..<next].foregroundColor = Self.panelYellow
                attr[idx..<next].font = .system(size: size, weight: .heavy)
            }
            idx = next
        }
        return attr
    }

    /// 爬坡规则文案（明示升降双向；边界级别只显示适用的一半）
    private var ladderRuleText: String {
        let n = ListeningTestStore.ladderThreshold
        let up = store.testLevel.nextUp
        let down = store.testLevel.nextDown
        switch (up, down) {
        case let (up?, down?):
            return String(localized: "连续 \(n) 套全对升入「\(up.tabName)」 · 连续 \(n) 套 ≤1 题回到「\(down.tabName)」")
        case let (up?, nil):
            return String(localized: "连续 \(n) 套全对升入「\(up.tabName)」")
        case let (nil, down?):
            return String(localized: "已是最高级！连续 \(n) 套 ≤1 题回到「\(down.tabName)」")
        default:
            return ""
        }
    }

    // MARK: ④ 听力库

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("听力库")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            // 级别筛选 chips
            HStack(spacing: 8) {
                filterChip(nil, label: String(localized: "全部"))
                ForEach(PodcastLevel.allCases, id: \.self) { level in
                    filterChip(level, label: level.tabName)
                }
                Spacer()
            }

            VStack(spacing: 6) {
                ForEach(libraryEpisodes) { ep in
                    libraryRow(ep)
                }
            }
        }
    }

    private func filterChip(_ level: PodcastLevel?, label: String) -> some View {
        let selected = filterLevel == level
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { filterLevel = level }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? .white : Color.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.appPrimary : Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 三级合并、按日期新→旧；筛选后取前 30
    private var libraryEpisodes: [Episode] {
        let all = PodcastLevel.allCases.flatMap { store.levelEpisodes[$0.rawValue] ?? [] }
        let filtered = filterLevel == nil ? all : all.filter { $0.level == filterLevel?.rawValue }
        return Array(filtered.sorted { $0.date > $1.date }.prefix(30))
    }

    private func libraryRow(_ ep: Episode) -> some View {
        let record = store.record(for: ep.id)
        let today = DateFormatter.episodeDate.string(from: Date())
        let locked = ep.date != today && !subscriptionManager.isProUser
        let level = ep.podcastLevel

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
                // 得分徽章：🟢全对 🟡部分 ⚪虚线未测
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
                    HStack(spacing: 5) {
                        if let level {
                            Text("\(level.icon) \(level.tabName)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.textSecondary)
                        }
                        Text("\(ep.dateDisplay) · \(ep.durationDisplay)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                    }
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
                Text("盲听一段真实语速的英语对话\n回答 3 个问题，马上知道你该从哪一级开始")
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
