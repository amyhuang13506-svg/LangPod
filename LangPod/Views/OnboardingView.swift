import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var currentPage: OnboardingPage = .welcome

    enum OnboardingPage: Int, CaseIterable {
        case welcome = 0
        case goal = 1
        case levelSelect = 2
        case dailyTime = 3
        case plan = 4
        case userSource = 5
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                if let step = questionStep {
                    questionProgressBar(step: step)
                        .padding(.top, 16)
                        .padding(.horizontal, 24)
                }

                switch currentPage {
                case .welcome:
                    welcomePage
                        .transition(pageTransition)
                case .goal:
                    goalPage
                        .transition(pageTransition)
                case .levelSelect:
                    levelSelectPage
                        .transition(pageTransition)
                case .dailyTime:
                    dailyTimePage
                        .transition(pageTransition)
                case .plan:
                    planPage
                        .transition(pageTransition)
                case .userSource:
                    userSourcePage
                        .transition(pageTransition)
                }
            }
        }
        .onDisappear {
            stopAllAudio()
        }
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    /// 三个问题页顶部的进度条（1/3 → 3/3），其余页不显示
    private var questionStep: Int? {
        switch currentPage {
        case .goal: return 1
        case .levelSelect: return 2
        case .dailyTime: return 3
        default: return nil
        }
    }

    private func questionProgressBar(step: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(hex: "E2E8F0"))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.appPrimary)
                    .frame(width: geo.size.width * CGFloat(step) / 3)
                    .animation(.easeInOut(duration: 0.35), value: step)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Shared Audio (level trial listen)

    @State private var audioPlayer: AVAudioPlayer?
    @State private var clipTimer: Timer?
    @State private var isAudioPlaying = false

    private func playBundledAudio(_ name: String, onFinish: (() -> Void)? = nil) {
        stopAllAudio()

        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else {
            #if DEBUG
            print("⚠️ Missing bundle audio: \(name).mp3")
            #endif
            onFinish?()
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            isAudioPlaying = true

            clipTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
                if let p = self.audioPlayer, !p.isPlaying {
                    timer.invalidate()
                    self.isAudioPlaying = false
                    onFinish?()
                }
            }
        } catch {
            #if DEBUG
            print("⚠️ Audio play error: \(error)")
            #endif
            onFinish?()
        }
    }

    private func stopAllAudio() {
        clipTimer?.invalidate()
        clipTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isAudioPlaying = false
    }

    private func goToPage(_ page: OnboardingPage) {
        stopAllAudio()
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage = page
        }
    }

    /// 选项点击后的统一节奏：震动 → 短暂停留展示选中态 → 自动前进
    private func selectAndAdvance(to page: OnboardingPage) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            goToPage(page)
        }
    }

    // MARK: - Page 1: Welcome

    /// 欢迎页浮动的场景短句：长短混搭（十几条轮换，控制在单行宽度内）
    private static let heroPhrases: [(scene: String, en: String)] = [
        ("☕️ 点单", "To go, please!"),
        ("✈️ 机场", "Where's gate B12?"),
        ("🏠 租房", "Is the deposit refundable?"),
        ("🩺 看病", "Can I book an appointment?"),
        ("🛒 超市", "Where's the dairy aisle?"),
        ("🚕 打车", "Right here is fine!"),
        ("🍽️ 餐厅", "Can we get the check?"),
        ("🏦 银行", "I'd like to open an account."),
        ("🏨 酒店", "A late check-out, please?"),
        ("🚇 地铁", "Does this go downtown?"),
        ("📱 办卡", "A SIM card, please."),
        ("🛃 过关", "Just here for vacation."),
        ("💇 理发", "Just a trim."),
        ("📦 快递", "Where's my package?"),
        ("🧾 退货", "Can I get a refund?"),
        ("👋 社交", "Wanna grab a coffee?"),
    ]

    private static let heroSlotCount = 7

    @State private var heroTimer: Timer?
    @State private var heroBobbing = false
    @State private var heroSize: CGSize = .zero
    /// 每个槽位当前显示第几条短句
    @State private var slotPhrases: [Int] = Array(0..<heroSlotCount)
    /// 每个槽位当前是否可见（整批一条条弹出 → 停留 → 一条条消失 → 循环）
    @State private var slotVisible: [Bool] = Array(repeating: false, count: heroSlotCount)
    /// 每个槽位解算后的绝对坐标（松弛去重叠后的结果）
    @State private var slotPos: [CGPoint] = Array(repeating: .zero, count: heroSlotCount)
    @State private var nextPhrase = 0

    /// 气泡的有机种子位置（hero 相对坐标 0-1）：中间密、上下疏，像被地球引力聚拢的一团。
    /// 解算时以此为起点，只把真正重叠的对儿轻推开——保留聚拢感，又不重叠。
    private static let heroSeeds: [CGPoint] = [
        CGPoint(x: 0.31, y: 0.17),
        CGPoint(x: 0.66, y: 0.15),
        CGPoint(x: 0.40, y: 0.29),
        CGPoint(x: 0.61, y: 0.33),
        CGPoint(x: 0.30, y: 0.45),
        CGPoint(x: 0.58, y: 0.48),
        CGPoint(x: 0.46, y: 0.60),
    ]

    /// 估算某条短句气泡的宽度（用于分配位置 + 无重叠松弛）
    private static func heroWidthEstimate(_ phraseIndex: Int) -> CGFloat {
        let p = heroPhrases[phraseIndex % heroPhrases.count]
        return 66 + CGFloat(p.en.count) * 6.4   // 场景标签+内边距≈66，英文≈每字符6.4
    }

    private func heroChip(phraseIndex: Int) -> some View {
        let phrase = Self.heroPhrases[phraseIndex % Self.heroPhrases.count]
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(phrase.scene)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.appPrimary)
            Text(phrase.en)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white, in: Capsule())
        .overlay(Capsule().stroke(Color.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 5)
    }

    /// 单个气泡：使用松弛解算后的绝对坐标，靠下的略大
    private func heroBubble(slot: Int) -> some View {
        let visible = slotVisible[slot]
        let depth = 0.9 + 0.16 * (slotPos[slot].y / max(1, heroSize.height))

        return heroChip(phraseIndex: slotPhrases[slot])
            .offset(y: heroBobbing ? -4 : 4)
            .animation(
                .easeInOut(duration: 1.9 + Double(slot) * 0.25).repeatForever(autoreverses: true),
                value: heroBobbing
            )
            .scaleEffect(visible ? depth : 0.01, anchor: .bottom)
            .opacity(visible ? 1 : 0)
            .animation(
                visible
                    ? .spring(response: 0.45, dampingFraction: 0.62)
                    : .easeIn(duration: 0.28),
                value: visible
            )
            .position(slotPos[slot])
    }

    private var welcomeHero: some View {
        GeometryReader { geo in
            let diameter = min(geo.size.width * 0.62, geo.size.height * 0.56)
            let center = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.44)

            ZStack {
                // 地球身后的柔光，和页面渐变背景连成一体
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.appPrimary.opacity(0.13), .clear],
                            center: .center,
                            startRadius: diameter * 0.2,
                            endRadius: diameter * 0.9
                        )
                    )
                    .frame(width: diameter * 1.8, height: diameter * 1.8)
                    .position(center)

                // 地面投影（淡蓝椭圆，跟手绘贴纸风一致）
                Ellipse()
                    .fill(Color(hex: "BBDDF5").opacity(0.55))
                    .frame(width: diameter * 0.85, height: diameter * 0.18)
                    .blur(radius: 6)
                    .position(x: center.x + diameter * 0.06, y: center.y + diameter * 0.56)

                // 手绘卡通地球，轻轻上下漂浮
                Image("cartoonGlobe")
                    .resizable()
                    .scaledToFit()
                    .frame(width: diameter, height: diameter)
                    .offset(y: heroBobbing ? -6 : 6)
                    .animation(
                        .easeInOut(duration: 3.0).repeatForever(autoreverses: true),
                        value: heroBobbing
                    )
                    .position(center)

                // 围绕地球的场景短句：一条条弹出、一条条消失，滚动换新
                ForEach(0..<Self.heroSlotCount, id: \.self) { slot in
                    heroBubble(slot: slot)
                }
            }
            .offset(y: geo.size.height * 0.06)   // 地球+泡泡整体下移一点
            .onAppear {
                heroSize = geo.size
                startHeroLoop()
            }
        }
        .frame(height: UIScreen.main.bounds.height * 0.52)
        .onDisappear {
            heroTimer?.invalidate()
            heroTimer = nil
        }
    }

    // 一波循环：staggerIn 依次弹出 → hold 停留 → staggerOut 依次消失 → 换一批句子再来
    private static let heroStagger = 0.16      // 相邻气泡出/入的时间差
    private static let heroHold = 2.6          // 全部弹出后停留时长

    private var heroCycleDuration: TimeInterval {
        let span = Double(slotVisible.count) * Self.heroStagger
        return span + Self.heroHold + span + 0.4   // 入 + 停 + 出 + 间隙
    }

    private func startHeroLoop() {
        heroBobbing = true
        runHeroWave()
        heroTimer?.invalidate()
        heroTimer = Timer.scheduledTimer(withTimeInterval: heroCycleDuration, repeats: true) { _ in
            runHeroWave()
        }
    }

    /// 一整波「第一次出场」效果：解算无重叠位置 → 依次弹出、停留、依次消失
    private func runHeroWave() {
        let n = Self.heroSlotCount
        let count = Self.heroPhrases.count

        // 本波要显示的一批句子
        let chosen = (0..<n).map { (nextPhrase + $0) % count }
        nextPhrase = (nextPhrase + 5) % count   // 下波错开，减少重复感

        // 宽度感知分配：最宽的句子给最靠中线的种子位，narrow 的放两侧，避免侧边裁切
        let seedOrder = (0..<n).sorted { abs(Self.heroSeeds[$0].x - 0.5) < abs(Self.heroSeeds[$1].x - 0.5) }
        let phraseOrder = chosen.sorted { Self.heroWidthEstimate($0) > Self.heroWidthEstimate($1) }
        var assign = [Int](repeating: 0, count: n)
        for k in 0..<n { assign[seedOrder[k]] = phraseOrder[k] }

        // 从有机种子出发做无重叠松弛
        let pos = solveHeroPositions(assign: assign, size: heroSize)

        let stagger = Self.heroStagger
        let inSpan = Double(n) * stagger

        // 依次弹出（弹出前把该波的句子和解算坐标填进槽位）
        for slot in 0..<n {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(slot) * stagger) {
                slotPhrases[slot] = assign[slot]
                slotPos[slot] = pos[slot]
                slotVisible[slot] = true
            }
        }

        // 停留后依次消失
        let outStart = inSpan + Self.heroHold
        for slot in 0..<n {
            DispatchQueue.main.asyncAfter(deadline: .now() + outStart + Double(slot) * stagger) {
                slotVisible[slot] = false
            }
        }
    }

    /// 无重叠松弛：以有机种子为起点，只把重叠的气泡沿最小穿透方向轻推开，
    /// 保留「向地球聚拢」的团簇感，同时保证任意两条都不叠。
    private func solveHeroPositions(assign: [Int], size: CGSize) -> [CGPoint] {
        let n = assign.count
        guard size.width > 1, size.height > 1 else {
            return Self.heroSeeds.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        }
        var pos = Self.heroSeeds.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        var halfW = [CGFloat](repeating: 0, count: n)
        let halfH: CGFloat = 15
        let pad: CGFloat = 8
        for i in 0..<n { halfW[i] = Self.heroWidthEstimate(assign[i]) / 2 }

        for _ in 0..<60 {
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let dx = pos[j].x - pos[i].x
                    let dy = pos[j].y - pos[i].y
                    let overlapX = (halfW[i] + halfW[j] + pad) - abs(dx)
                    let overlapY = (halfH + halfH + pad) - abs(dy)
                    guard overlapX > 0, overlapY > 0 else { continue }
                    if overlapY <= overlapX {
                        let push = overlapY / 2 * (dy < 0 ? -1 : 1)
                        pos[i].y -= push; pos[j].y += push
                    } else {
                        let push = overlapX / 2 * (dx < 0 ? -1 : 1)
                        pos[i].x -= push; pos[j].x += push
                    }
                }
            }
            // 夹在 hero 边界内
            for i in 0..<n {
                pos[i].x = min(max(halfW[i] + 4, pos[i].x), size.width - halfW[i] - 4)
                pos[i].y = min(max(halfH + 6, pos[i].y), size.height - halfH - 6)
            }
        }
        return pos
    }

    private var welcomePage: some View {
        ZStack {
            // 整页统一背景：顶部天空蓝渐变到页面底色，与地球光晕衔接
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "E7F2FF"), location: 0),
                    .init(color: Color(hex: "F4F9FF"), location: 0.45),
                    .init(color: Color.appBackground, location: 0.75),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            welcomePageContent
        }
    }

    private var welcomePageContent: some View {
        VStack(spacing: 0) {
            welcomeHero

            VStack(spacing: 12) {
                Text("Castlingo")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .tracking(-0.5)

                Text("从真实场景，学实用英语")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.bodyText)

                Text("点单、租房、看病、机场，学了就能用\n每天几分钟，听得懂，开得了口")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.top, 8)
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 14) {
                Button {
                    goToPage(.goal)
                } label: {
                    Text("开始定制")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Page 2: Goal question

    enum LearningGoal: String, CaseIterable {
        case travel = "travel"
        case study = "study"
        case living = "overseas_living"
        case work = "work"
        case video = "video"
        case selfGrowth = "self_growth"

        var icon: String {
            switch self {
            case .travel: return "airplane"
            case .study: return "graduationcap.fill"
            case .living: return "house.fill"
            case .work: return "briefcase.fill"
            case .video: return "play.rectangle.fill"
            case .selfGrowth: return "sparkles"
            }
        }

        var label: String {
            switch self {
            case .travel: return "出国旅行"
            case .study: return "留学生活"
            case .living: return "在国外生活"
            case .work: return "工作需要"
            case .video: return "刷懂英文原声视频"
            case .selfGrowth: return "提升自己"
            }
        }

        var color: Color {
            switch self {
            case .travel: return Color(hex: "F59E0B")
            case .study: return Color(hex: "8B5CF6")
            case .living: return Color(hex: "10B981")
            case .work: return Color(hex: "3B82F6")
            case .video: return Color(hex: "FF0000")
            case .selfGrowth: return Color(hex: "EC4899")
            }
        }

        var bgColor: Color {
            switch self {
            case .travel: return Color(hex: "FFFBEB")
            case .study: return Color(hex: "F5F3FF")
            case .living: return Color(hex: "ECFDF5")
            case .work: return Color(hex: "EFF6FF")
            case .video: return Color(hex: "FEF2F2")
            case .selfGrowth: return Color(hex: "FDF2F8")
            }
        }

        /// 计划页里 90 天效果预期的文案
        var outcome90d: String {
            switch self {
            case .travel: return "旅行常用场景对话不慌不忙，点单问路都能自己来"
            case .study: return "课堂内外的日常交流跟得上，社交场合敢开口"
            case .living: return "办事、就医、社交都能自己搞定，不用再靠翻译软件"
            case .work: return "职场高频表达张口就来，开会邮件不再卡壳"
            case .video: return "不开字幕也能跟上英文原声播客和视频"
            case .selfGrowth: return "英语听力形成条件反射，把'学过'变成'用得上'"
            }
        }
    }

    @State private var selectedGoal: LearningGoal? = nil

    private var goalPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)

            VStack(alignment: .leading, spacing: 8) {
                Text("你为什么学英语？")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Text("我们会按你的目标安排学习内容")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Spacer().frame(height: 28)

            VStack(spacing: 10) {
                ForEach(LearningGoal.allCases, id: \.rawValue) { goal in
                    optionRow(
                        icon: goal.icon,
                        iconColor: goal.color,
                        iconBg: goal.bgColor,
                        label: goal.label,
                        isSelected: selectedGoal == goal
                    ) {
                        selectedGoal = goal
                        selectAndAdvance(to: .levelSelect)
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func optionRow(icon: String, iconColor: Color, iconBg: Color, label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(iconBg)
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 17))
                        .foregroundStyle(iconColor)
                }

                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.appPrimary : Color.textQuaternary)
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.appPrimary : Color.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Page 3: Level self-assess + trial listen

    @State private var selectedLevel: PodcastLevel = .easy
    @State private var hasPickedLevel = false
    @State private var trialPlayingLevel: PodcastLevel? = nil

    private var levelSelectPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)

            VStack(alignment: .leading, spacing: 8) {
                Text("你现在的听力水平？")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Text("不确定就点喇叭试听，选能听懂一半的那档")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Spacer().frame(height: 24)

            VStack(spacing: 12) {
                trialLevelCard(
                    level: .easy,
                    dotFill: Color.success,
                    dotBg: Color.successLight,
                    name: "初级",
                    desc: "简单日常对话，慢速播放",
                    detail: "适合基础薄弱、久没碰英语"
                )
                trialLevelCard(
                    level: .medium,
                    dotFill: Color.appPrimary,
                    dotBg: Color.primaryLighter,
                    name: "中级",
                    desc: "生活、文化、旅行话题",
                    detail: "适合能听懂慢速、想再上一层"
                )
                trialLevelCard(
                    level: .hard,
                    dotFill: Color.hardOrange,
                    dotBg: Color.warningLight,
                    name: "高级",
                    desc: "新闻、商务，自然语速",
                    detail: "适合想挑战原声语速"
                )
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func trialLevelCard(level: PodcastLevel, dotFill: Color, dotBg: Color, name: String, desc: String, detail: String) -> some View {
        let isSelected = hasPickedLevel && selectedLevel == level
        let isPlaying = trialPlayingLevel == level

        return Button {
            selectedLevel = level
            hasPickedLevel = true
            selectAndAdvance(to: .dailyTime)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(dotBg)
                        .frame(width: 44, height: 44)
                    Circle()
                        .fill(dotFill)
                        .frame(width: 14, height: 14)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(desc)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textTertiary)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textQuaternary)
                }

                Spacer()

                Button {
                    toggleTrialPlay(level: level)
                } label: {
                    ZStack {
                        Circle()
                            .fill(isPlaying ? Color.appPrimary : Color.primaryLight)
                            .frame(width: 36, height: 36)

                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(isPlaying ? .white : Color.appPrimary)
                    }
                }
                .buttonStyle(.plain)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.appPrimary : Color.textQuaternary)
            }
            .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.appPrimary : Color.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func trialAudioName(for level: PodcastLevel) -> String {
        switch level {
        case .easy: return "onboarding_trial_easy_en"
        case .medium: return "onboarding_trial_medium_en"
        case .hard: return "onboarding_trial_hard_en"
        }
    }

    private func toggleTrialPlay(level: PodcastLevel) {
        if trialPlayingLevel == level {
            stopAllAudio()
            trialPlayingLevel = nil
        } else {
            trialPlayingLevel = level
            playBundledAudio(trialAudioName(for: level)) {
                DispatchQueue.main.async {
                    trialPlayingLevel = nil
                }
            }
        }
    }

    // MARK: - Page 4: Daily time commitment

    private struct TimeOption: Identifiable {
        let minutes: Int
        let label: String
        let detail: String
        let isRecommended: Bool
        var id: Int { minutes }
    }

    private let timeOptions: [TimeOption] = [
        TimeOption(minutes: 5, label: "每天 5 分钟", detail: "极简 · 先把每天听英语的习惯养起来", isRecommended: false),
        TimeOption(minutes: 10, label: "每天 10 分钟", detail: "轻松 · 一集播客，加一个句型讲解", isRecommended: false),
        TimeOption(minutes: 15, label: "每天 15 分钟", detail: "推荐 · 播客、句型，加每日任务打卡", isRecommended: true),
        TimeOption(minutes: 20, label: "每天 20 分钟", detail: "认真 · 再加一篇出国场景课堂", isRecommended: false),
        TimeOption(minutes: 30, label: "每天 30 分钟", detail: "沉浸 · 全部内容，加原声播客磨耳朵", isRecommended: false),
    ]

    @State private var selectedMinutes: Int? = nil

    private var dailyTimePage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)

            VStack(alignment: .leading, spacing: 8) {
                Text("每天想投入多久？")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Text("少而稳定比多而三天打鱼更有效")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Spacer().frame(height: 28)

            VStack(spacing: 10) {
                ForEach(Array(timeOptions.enumerated()), id: \.element.id) { index, option in
                    timeOptionRow(option: option, index: index)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func timeOptionRow(option: TimeOption, index: Int) -> some View {
        let isSelected = selectedMinutes == option.minutes
        let letter = String(UnicodeScalar(UInt8(65 + index)))   // A / B / C / D / E

        return Button {
            selectedMinutes = option.minutes
            selectAndAdvance(to: .plan)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.appPrimary : Color.primaryLighter)
                        .frame(width: 44, height: 44)
                    Text(letter)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(isSelected ? .white : Color.appPrimary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(option.label)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)

                        if option.isRecommended {
                            Text("推荐")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.appPrimary, in: Capsule())
                        }
                    }
                    Text(option.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.appPrimary : Color.textQuaternary)
            }
            .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.appPrimary : Color.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Page 5: Plan build + reveal

    /// 0 = 生成中，1-3 = 第 N 条已完成，4 = 计划揭示
    @State private var planStage = 0

    private var levelDisplayName: String {
        switch selectedLevel {
        case .easy: return "初级"
        case .medium: return "中级"
        case .hard: return "高级"
        }
    }

    private var planBuildSteps: [String] {
        [
            "分析听力水平 · \(levelDisplayName)",
            "按目标匹配学习内容 · \(selectedGoal?.label ?? "实用口语")",
            "生成每日 \(selectedMinutes ?? 15) 分钟计划",
        ]
    }

    // MARK: 计划条目 —— 按目标和时长拼装，不是人人相同

    private struct PlanItem: Identifiable {
        let icon: String
        let color: Color
        let title: String
        let detail: String
        var id: String { title }
    }

    /// 场景课堂一行的说明，跟随用户目标侧重
    private var lessonDetailText: String {
        switch selectedGoal {
        case .travel: return "机场、酒店、餐厅，旅行场景课优先安排"
        case .study: return "校园、社交、日常琐事，留学场景课优先安排"
        case .living: return "租房、看病、办事，海外生活场景课优先安排"
        case .work: return "职场沟通高频场景课优先安排"
        default: return "点单、租房、看病，按真实场景分类的实用课"
        }
    }

    private var planItems: [PlanItem] {
        var items: [PlanItem] = [
            PlanItem(icon: "headphones", color: Color.appPrimary,
                     title: "每天 1 集\(levelDisplayName)播客",
                     detail: "英语 ×3 → 中文 ×1 → 英语 ×1，重复成本能"),
            PlanItem(icon: "text.bubble.fill", color: Color(hex: "F59E0B"),
                     title: "高频句型讲解",
                     detail: "从当天播客拆出来，讲透场景和语感"),
        ]

        let youtubeItem = PlanItem(icon: "play.rectangle.fill", color: Color(hex: "FF0000"),
                                   title: "YouTube 原声播客",
                                   detail: "中英双语字幕，检验真实语速听力")
        let lessonItem = PlanItem(icon: "graduationcap.fill", color: Color(hex: "10B981"),
                                  title: "出国场景课堂",
                                  detail: lessonDetailText)

        // 目标决定第三块的侧重；时间充裕（≥20 分钟）则两块都排进来
        if selectedGoal == .video {
            items.append(youtubeItem)
            if (selectedMinutes ?? 15) >= 20 { items.append(lessonItem) }
        } else {
            items.append(lessonItem)
            if (selectedMinutes ?? 15) >= 20 { items.append(youtubeItem) }
        }

        items.append(PlanItem(icon: "flame.fill", color: Color(hex: "F97316"),
                              title: "每日任务打卡",
                              detail: "词汇 + 句型练习，连续打卡不断档"))
        return items
    }

    private var planPage: some View {
        VStack(spacing: 0) {
            if planStage < 4 {
                Spacer()

                VStack(spacing: 24) {
                    Text("正在生成你的专属计划…")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.textPrimary)

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(0..<planBuildSteps.count, id: \.self) { i in
                            HStack(spacing: 12) {
                                ZStack {
                                    if planStage > i {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(Color.success)
                                            .transition(.scale.combined(with: .opacity))
                                    } else if planStage == i {
                                        ProgressView()
                                            .tint(Color.appPrimary)
                                    } else {
                                        Circle()
                                            .stroke(Color(hex: "E2E8F0"), lineWidth: 2)
                                            .frame(width: 18, height: 18)
                                    }
                                }
                                .frame(width: 22, height: 22)

                                Text(planBuildSteps[i])
                                    .font(.system(size: 15, weight: planStage >= i ? .medium : .regular))
                                    .foregroundStyle(planStage >= i ? Color.textPrimary : Color.textQuaternary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)

                Spacer()
            } else {
                planRevealContent
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onAppear { runPlanBuildAnimation() }
    }

    private func runPlanBuildAnimation() {
        planStage = 0
        for i in 1...4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55 * Double(i)) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    planStage = i
                }
                if i == 4 {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }

    private var planRevealContent: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 32)

                    VStack(spacing: 10) {
                        Text("你的专属听力计划")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color.textPrimary)

                        HStack(spacing: 8) {
                            planChip(levelDisplayName)
                            planChip("每天 \(selectedMinutes ?? 15) 分钟")
                            if let goal = selectedGoal {
                                planChip(goal.label)
                            }
                        }
                    }

                    Spacer().frame(height: 24)

                    // 每天做什么 —— 条目由级别、目标、时长拼装
                    VStack(spacing: 0) {
                        ForEach(Array(planItems.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { planDivider }
                            planRow(icon: item.icon, color: item.color,
                                    title: item.title, detail: item.detail)
                        }
                    }
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 20)

                    // 效果预期时间线
                    VStack(alignment: .leading, spacing: 16) {
                        Text("坚持下去，你会听到变化")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.textPrimary)

                        milestoneRow(
                            day: "第 7 天",
                            title: "耳朵热起来",
                            desc: "适应 5 遍精听的节奏，能从整句里抓到关键词，英语不再是一片模糊的背景音"
                        )
                        milestoneRow(
                            day: "第 21 天",
                            title: "句型上口",
                            desc: "高频句型开始形成条件反射，听到熟悉的场景，能直接反应出该说的那句话"
                        )
                        milestoneRow(
                            day: "第 30 天",
                            title: "跟上对话",
                            desc: "日常对话不用暂停回放也能跟上大意，敢在真实场景里开口回应"
                        )
                        milestoneRow(
                            day: "第 90 天",
                            title: "真的用得上",
                            desc: selectedGoal?.outcome90d ?? "英语听力形成条件反射，把'学过'变成'用得上'"
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color.primaryLight, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 20)
                }
            }

            Button {
                goToPage(.userSource)
            } label: {
                Text("开启我的计划")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .padding(.top, 8)
        }
    }

    private var planDivider: some View {
        Divider().padding(.leading, 70)
    }

    private func planRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func planChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.appPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primaryLight, in: Capsule())
    }

    private func milestoneRow(day: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(day)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.appPrimary)
                .frame(width: 52, alignment: .leading)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Page 6: User Source

    @State private var selectedSource: String? = nil

    private struct SourceOption: Identifiable {
        let icon: String
        let label: String
        let color: Color
        let bgColor: Color
        var id: String { label }
    }

    private let sourceOptions: [SourceOption] = [
        SourceOption(icon: "person.2.fill", label: "朋友推荐", color: Color(hex: "3B82F6"), bgColor: Color(hex: "EFF6FF")),
        SourceOption(icon: "camera.fill", label: "小红书", color: Color(hex: "FF2442"), bgColor: Color(hex: "FFF1F2")),
        SourceOption(icon: "bag.fill", label: "App Store 推荐", color: Color(hex: "007AFF"), bgColor: Color(hex: "E8F4FD")),
        SourceOption(icon: "video.fill", label: "抖音", color: Color(hex: "000000"), bgColor: Color(hex: "F1F5F9")),
        SourceOption(icon: "play.tv.fill", label: "B站", color: Color(hex: "00A1D6"), bgColor: Color(hex: "E8F7FC")),
        SourceOption(icon: "message.fill", label: "微信", color: Color(hex: "07C160"), bgColor: Color(hex: "ECFDF5")),
        SourceOption(icon: "ellipsis.circle.fill", label: "其他", color: Color(hex: "94A3B8"), bgColor: Color(hex: "F1F5F9")),
    ]

    private var userSourcePage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)

            VStack(alignment: .leading, spacing: 8) {
                Text("最后一个问题")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.appPrimary)

                Text("你是怎么发现 Castlingo 的？")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Spacer().frame(height: 24)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(sourceOptions) { option in
                        sourceOptionRow(option: option)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private func sourceOptionRow(option: SourceOption) -> some View {
        let isSelected = selectedSource == option.label

        return Button {
            guard selectedSource == nil else { return }
            selectedSource = option.label
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                completeOnboarding()
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(option.bgColor)
                        .frame(width: 40, height: 40)

                    Image(systemName: option.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(option.color)
                }

                Text(option.label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.appPrimary : Color.border, lineWidth: isSelected ? 6 : 1.5)
                        .frame(width: 20, height: 20)

                    if isSelected {
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.appPrimary : Color.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func completeOnboarding() {
        if let source = selectedSource {
            UserDefaults.standard.set(source, forKey: "userAcquisitionSource")
        }
        if let goal = selectedGoal {
            UserDefaults.standard.set(goal.rawValue, forKey: "userLearningGoal")
        }
        if let minutes = selectedMinutes {
            UserDefaults.standard.set(minutes, forKey: "dailyGoalMinutes")
        }
        dataStore.selectedLevel = selectedLevel
        dataStore.hasCompletedOnboarding = true
        Analytics.track(.onboardingComplete, params: [
            "level": selectedLevel.rawValue,
            "source": selectedSource ?? "unknown",
            "goal": selectedGoal?.rawValue ?? "unknown",
            "daily_minutes": "\(selectedMinutes ?? 0)"
        ])
    }
}

#Preview {
    OnboardingView()
        .environment(DataStore())
}
