import SwiftUI

// MARK: - 我的句子·连词成句
// UI/交互照搬词汇连词成句（FeynmanChallengeView），题卡从"单词+音标+释义"换成"句子中文翻译"。
// 不进 SavedWord 记忆体系，无每日次数限制（自己收藏的句子随便练）。

struct SentencePracticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SentenceStore.self) private var sentenceStore

    @State private var currentIndex = 0
    @State private var challengeSentences: [SavedSentence] = []
    @State private var completed = false

    // Sentence building
    @State private var availableTokens: [PracticeToken] = []
    @State private var selectedTokens: [PracticeToken] = []
    @State private var answerState: AnswerState = .building
    @State private var correctSentence = ""

    // Session tracking
    @State private var sessionPracticed: Set<String> = []
    @State private var sessionRound = 1
    @State private var isFirstCompletion = true

    enum AnswerState { case building, correct, wrong }

    struct PracticeToken: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    private let maxPerSet = 8

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if completed {
                completedContent
            } else if challengeSentences.isEmpty {
                emptyContent
            } else {
                challengeContent
            }
        }
        .onAppear { startGame() }
    }

    // MARK: - Challenge Content

    private var challengeContent: some View {
        let sentence = challengeSentences[currentIndex]

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
                    Text("\(currentIndex + 1)/\(challengeSentences.count)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.appPrimary)
                    if sessionRound > 1 {
                        Text("· 累计\(sessionPracticed.count)句")
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
                        .frame(width: geo.size.width * CGFloat(currentIndex + 1) / CGFloat(challengeSentences.count), height: 4)
                }
            }
            .frame(height: 4)

            // 题卡：场景 tag + 中文翻译（对应词汇版的 单词+音标+释义）
            VStack(spacing: 8) {
                Text(sentence.scene)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.gold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.warningLight))
                Text(sentence.chinese)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.border, lineWidth: 1)
            )

            // Prompt
            Text("把这句话拼出来：")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            answerArea

            tokenPool

            Spacer()

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
                    Button { playCurrent() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.appPrimary)
                            Text(correctSentence)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "F0FDF4"), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Text(challengeSentences[currentIndex].chinese)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button { advance() } label: {
                        Text(currentIndex + 1 < challengeSentences.count ? "下一题" : "完成")
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
                            setupQuestion()
                        } label: {
                            Text("重试")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
                        }

                        Button {
                            advance()
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

    // MARK: - Completed（同词汇版：星星弹入 + 首轮彩屑 + 再来一组）

    @State private var starScale: CGFloat = 0
    @State private var textOpacity: Double = 0
    @State private var confettiOffsets: [(CGFloat, CGFloat)] = (0..<12).map { _ in
        (CGFloat.random(in: -150...150), CGFloat.random(in: -200...(-50)))
    }
    @State private var confettiVisible = false

    private var completedContent: some View {
        ZStack {
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

                Text("完成 \(challengeSentences.count) 句连词成句练习")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.textTertiary)
                    .opacity(textOpacity)

                if sessionPracticed.count > challengeSentences.count {
                    Text("本次累计已练 \(sessionPracticed.count) 句")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .opacity(textOpacity)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        startNextSet()
                    } label: {
                        HStack(spacing: 8) {
                            Text("🔥")
                            Text("再来一组")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.warning, in: RoundedRectangle(cornerRadius: 14))
                    }

                    Button { dismiss() } label: {
                        Text("返回我的句子")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(textOpacity)
            }
        }
        .onAppear { celebrateCompletion() }
    }

    private func celebrateCompletion() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
            starScale = 1.0
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
            textOpacity = 1.0
        }
        if isFirstCompletion {
            confettiVisible = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation { confettiVisible = true }
            }
        }
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

            Text("还没有可以练习的句子")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            Text("在句型和小课堂里点 ＋ 收藏句子\n（句子需 ≤12 个单词）")
                .font(.system(size: 14))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            Spacer()
        }
    }

    // MARK: - Logic

    private func startGame() {
        sessionPracticed = []
        sessionRound = 1
        isFirstCompletion = true
        loadSet()
    }

    private func startNextSet() {
        sessionRound += 1
        isFirstCompletion = false
        starScale = 0
        textOpacity = 0
        completed = false
        currentIndex = 0
        loadSet()
    }

    private func loadSet() {
        let all = sentenceStore.practiceableSentences
        // 优先没练过的，练完一轮后全体重新洗牌
        var pool = all.filter { !sessionPracticed.contains($0.english) }.shuffled()
        if pool.count < maxPerSet {
            pool += all.filter { sessionPracticed.contains($0.english) }.shuffled()
        }
        challengeSentences = Array(pool.prefix(maxPerSet))
        currentIndex = 0
        completed = false
        if !challengeSentences.isEmpty {
            setupQuestion()
        }
    }

    private func setupQuestion() {
        let sentence = challengeSentences[currentIndex]
        correctSentence = sentence.english
        let words = correctSentence.split(separator: " ").map(String.init)
        let cleanWords = words.map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        availableTokens = cleanWords.shuffled().map { PracticeToken(text: $0) }
        selectedTokens = []
        answerState = .building
    }

    private func addToken(_ token: PracticeToken) {
        selectedTokens.append(token)
        availableTokens.removeAll { $0.id == token.id }
    }

    private func removeToken(_ token: PracticeToken) {
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
            playCurrent()
            sessionPracticed.insert(correctSentence)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.easeInOut(duration: 0.3)) {
                answerState = .wrong
            }
        }
    }

    private func playCurrent() {
        let sentence = challengeSentences[currentIndex]
        LessonAudioPlayer.shared.play(sentence.audioUrl, from: sentence.audioStart, to: sentence.audioEnd) {
            WordSpeaker.shared.speakSentence(sentence.english)
        }
    }

    private func advance() {
        if currentIndex + 1 < challengeSentences.count {
            currentIndex += 1
            setupQuestion()
        } else {
            Analytics.track(.sentencePracticeComplete, params: [
                "total": "\(challengeSentences.count)",
                "practiced": "\(sessionPracticed.count)",
            ])
            withAnimation { completed = true }
        }
    }
}

// MARK: - 场景模拟（对话填空）
// 真实场景对话（店员说 → 你说 → 店员说 → 你说，来自课堂的模拟现场对话数据），
// 其中一句"你说"留白，从 4 个选项里选出该说的那句填进去。

struct SceneQuizView: View {
    @Environment(\.dismiss) private var dismiss
    // 自包含：不依赖 LessonStore 环境（此页从句型 tab 打开，环境里没有 LessonStore）。
    // 国家读上次浏览记录，数据直接走 APIService。
    @AppStorage("lessonCountry") private var savedCountry = "us"

    private struct Question {
        let lessonTitle: String     // 在 Starbucks 点单
        let otherRole: String       // 店员
        let turns: [RoleplayLine]   // 4 句（other/you 交替）
        let blankIndex: Int         // 留白的那句（you）
        let options: [RoleplayLine] // 4 个候选（含正确项），已打乱
        var answer: RoleplayLine { turns[blankIndex] }
    }

    @State private var questions: [Question] = []
    @State private var loading = true
    @State private var currentIndex = 0
    @State private var selectedOption: String?   // 点中的选项 en
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
                    onRestart: { Task { await startGame() } },
                    onClose: { dismiss() }
                )
            } else if loading {
                VStack(spacing: 10) {
                    ProgressView().tint(Color.appPrimary)
                    Text("正在准备场景…")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textTertiary)
                }
            } else if questions.isEmpty {
                emptyContent
            } else {
                quizContent
            }
        }
        .task { await startGame() }
    }

    private var current: Question { questions[currentIndex] }

    // MARK: - 出题（题源 = 课堂模拟现场对话）

    @MainActor
    private func startGame() async {
        loading = true
        completed = false
        currentIndex = 0
        correctCount = 0
        selectedOption = nil
        revealed = false

        // 拉当前国家课堂列表 → 并发取有模拟对话的
        var country = savedCountry
        var items = await APIService.shared.fetchLessonIndex(country: country)
        var roleplays = await Self.fetchRoleplays(items: items, country: country)
        // 当前国家还没生成模拟对话（如英国）→ fallback 到美国，保证有内容
        if roleplays.isEmpty && country != "us" {
            country = "us"
            items = await APIService.shared.fetchLessonIndex(country: "us")
            roleplays = await Self.fetchRoleplays(items: items, country: "us")
        }

        // 干扰项池：所有课堂里"你说"的台词
        let allYouLines = roleplays.flatMap { $0.roleplay.dialogue.filter { $0.isYou } }

        var built: [Question] = []
        for (title, rp) in roleplays.shuffled() {
            let dialogue = rp.dialogue
            // 取一个 4 句窗口（从"对方"开头的偶数位起，保持 店员/你 交替）
            let maxStart = dialogue.count - 4
            let starts = stride(from: 0, through: maxStart, by: 2).map { $0 }
            guard let start = starts.randomElement() else { continue }
            let turns = Array(dialogue[start..<(start + 4)])
            // 留白：窗口里随机一句"你说"
            let youIndexes = turns.indices.filter { turns[$0].isYou }
            guard let blank = youIndexes.randomElement() else { continue }
            let answer = turns[blank]
            var distractors = allYouLines
                .filter { $0.en != answer.en }
                .shuffled()
            // 去重
            var seen = Set<String>()
            distractors = distractors.filter { seen.insert($0.en).inserted }
            guard distractors.count >= 3 else { continue }
            let options = ([answer] + distractors.prefix(3)).shuffled()
            built.append(Question(
                lessonTitle: title,
                otherRole: rp.otherRoleZh,
                turns: turns,
                blankIndex: blank,
                options: options
            ))
            if built.count >= 5 { break }
        }

        questions = built
        loading = false
    }

    /// 并发拉课堂详情（最多 8 个），取有 ≥4 句模拟对话的
    private static func fetchRoleplays(
        items: [SceneLessonIndexItem], country: String
    ) async -> [(title: String, roleplay: LessonRoleplay)] {
        let candidates = items.shuffled().prefix(8)
        var result: [(title: String, roleplay: LessonRoleplay)] = []
        await withTaskGroup(of: (String, LessonRoleplay?).self) { group in
            for item in candidates {
                group.addTask {
                    let lesson = await APIService.shared.fetchLessonDetail(country: country, id: item.id)
                    return (item.titleZh, lesson?.roleplay)
                }
            }
            for await (title, rp) in group {
                if let rp, rp.dialogue.count >= 4 {
                    result.append((title, rp))
                }
            }
        }
        return result
    }

    private func choose(_ option: RoleplayLine) {
        guard !revealed else { return }
        selectedOption = option.en
        withAnimation(.spring(duration: 0.35)) { revealed = true }
        if option.en == current.answer.en {
            correctCount += 1
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            LessonAudioPlayer.shared.play(current.answer.audio) {
                WordSpeaker.shared.speakSentence(current.answer.en)
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        // 不再自动跳题，等用户点底部「下一题」
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
        VStack(spacing: 16) {
            practiceHeader(title: "场景模拟", progress: "\(currentIndex + 1)/\(questions.count)") { dismiss() }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // 场景标题
                    HStack(spacing: 6) {
                        Image(systemName: "theatermasks.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.gold)
                        Text(current.lessonTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.gold)
                        Spacer()
                    }

                    // 对话：纯文本一行行列出（说话人 + 英文），留白行用下划线，无翻译无气泡
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(current.turns.enumerated()), id: \.offset) { index, turn in
                            dialogueLine(turn, isBlank: index == current.blankIndex)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))

                    Text("选择恰当的句子填空")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, 2)

                    VStack(spacing: 10) {
                        ForEach(Array(current.options.enumerated()), id: \.element.id) { idx, option in
                            optionRow(option, label: optionLabel(idx))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }

            // 底部「下一题」CTA：选完手动进入
            if revealed {
                Button { advance() } label: {
                    Text(currentIndex + 1 < questions.count ? "下一题" : "完成")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// 一行对话：说话人用 A/B（对方=A，你=B）+ 英文。纯文本，无翻译。
    private func dialogueLine(_ turn: RoleplayLine, isBlank: Bool) -> some View {
        let speaker = turn.isYou ? "B" : "A"
        return HStack(alignment: .top, spacing: 8) {
            Text("\(speaker)：")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(turn.isYou ? Color.appPrimary : Color.hardOrange)
                .fixedSize()
            if isBlank && !revealed {
                Text("_______________")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.appPrimary.opacity(0.5))
            } else {
                Text(turn.en)
                    .font(.system(size: 15, weight: isBlank ? .semibold : .regular))
                    .foregroundStyle(isBlank ? Color.success : Color.textPrimary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
    }

    private func optionLabel(_ index: Int) -> String {
        String(UnicodeScalar(65 + index)!)  // A/B/C/D
    }

    private func optionRow(_ option: RoleplayLine, label: String) -> some View {
        let isAnswer = option.en == current.answer.en
        let isSelected = selectedOption == option.en
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
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(revealed && isAnswer ? Color.success : (revealed && isSelected ? Color.danger : Color.appPrimary))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(
                            revealed && isAnswer ? Color.successLight
                            : (revealed && isSelected ? Color.dangerLight : Color.primaryLight)
                        )
                    )
                Text(option.en)
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

    private var emptyContent: some View {
        VStack(spacing: 12) {
            practiceHeader(title: "场景模拟", progress: "") { dismiss() }
            Spacer()
            Image(systemName: "theatermasks")
                .font(.system(size: 40))
                .foregroundStyle(Color.textQuaternary)
            Text("场景对话准备中")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            Text("请检查网络后重试")
                .font(.system(size: 13))
                .foregroundStyle(Color.textTertiary)
            Button("重试") { Task { await startGame() } }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.appPrimary)
            Spacer()
        }
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

// FlowLayout 复用 FeynmanChallengeView.swift 里的现有实现

/// 练习完成页（场景模拟用）
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
