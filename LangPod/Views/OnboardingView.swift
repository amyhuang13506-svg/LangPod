import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var currentPage: OnboardingPage = .welcome

    enum OnboardingPage: Int, CaseIterable {
        case welcome = 0
        case methodDemo = 1
        case levelSelect = 2
        case userSource = 3
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            // Skip button (top right, pages 2-3 only)
            if currentPage == .methodDemo || currentPage == .levelSelect {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            goToNextPage()
                        } label: {
                            Text("跳过")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.textTertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                    }
                    Spacer()
                }
                .padding(.top, 8)
                .zIndex(10)
            }

            switch currentPage {
            case .welcome:
                welcomePage
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .methodDemo:
                methodDemoPage
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .levelSelect:
                levelSelectPage
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .userSource:
                userSourcePage
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .onDisappear {
            stopAllAudio()
        }
    }

    // MARK: - Shared Audio

    @State private var audioPlayer: AVAudioPlayer?
    @State private var clipTimer: Timer?
    @State private var isAudioPlaying = false
    @State private var waveformTimer: Timer?
    @State private var waveformHeights: [CGFloat] = (0..<20).map { _ in CGFloat.random(in: 6...28) }

    private func playBundledAudio(_ name: String, clipDuration: TimeInterval? = nil, onFinish: (() -> Void)? = nil) {
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

            // Start waveform animation timer
            waveformTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    waveformHeights = (0..<20).map { _ in CGFloat.random(in: 6...28) }
                }
            }

            // Poll for playback completion
            clipTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
                if let p = self.audioPlayer, !p.isPlaying {
                    timer.invalidate()
                    self.waveformTimer?.invalidate()
                    self.waveformTimer = nil
                    self.isAudioPlaying = false
                    onFinish?()
                }
            }

            if let clip = clipDuration {
                DispatchQueue.main.asyncAfter(deadline: .now() + clip) {
                    self.audioPlayer?.stop()
                    self.waveformTimer?.invalidate()
                    self.waveformTimer = nil
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
        waveformTimer?.invalidate()
        waveformTimer = nil
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

    private func goToNextPage() {
        stopAllAudio()
        if let next = OnboardingPage(rawValue: currentPage.rawValue + 1) {
            goToPage(next)
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 180)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "E0F2FE"), Color.primaryLighter],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)

                Image(systemName: "headphones")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.appPrimary)
            }

            VStack(spacing: 12) {
                Text("Castlingo")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .tracking(-0.5)

                Text("600小时，听会一门语言")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.bodyText)

                Text("源于FSI外交官训练，重复即本能")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.top, 32)
            .padding(.horizontal, 32)

            Spacer()

            Button {
                goToPage(.methodDemo)
            } label: {
                Text("开始使用")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Page 2: Method Demo

    @State private var demoStep: DemoStep = .idle
    @State private var showWaveform = false

    enum DemoStep: Int {
        case idle = 0
        case playEn1 = 1
        case playEn2 = 2
        case playZh = 3
        case playEn3 = 4
        case complete = 5
    }

    // Demo script for display after completion
    private let demoScript: [(en: String, zh: String)] = [
        ("Hi Lisa, coffee or tea today?", "嗨丽莎，今天喝咖啡还是茶？"),
        ("Coffee, always! What about you?", "咖啡，永远都是咖啡！你呢？"),
        ("Tea for me. Let's grab some now!", "我选茶。走，现在就去买一杯！"),
    ]

    private var methodDemoPage: some View {
        VStack(spacing: 0) {
            // Scrollable content area
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 44)

                    // Title
                    VStack(spacing: 6) {
                        Text("Castlingo 听力法")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color.textPrimary)

                        Text("用60秒体验一次完整的听力训练")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.textTertiary)
                    }

                    Spacer().frame(height: 60)

                    // Demo steps
                    VStack(spacing: 0) {
                        demoStepRow(step: .playEn1, icon: "ear", label: "先听一段英语对话", sublabel: "第 1 遍英语")
                        demoConnector(active: demoStep.rawValue >= DemoStep.playEn2.rawValue)
                        demoStepRow(step: .playEn2, icon: "arrow.counterclockwise", label: "你听懂了多少？再来一遍", sublabel: "第 2 遍英语")
                        demoConnector(active: demoStep.rawValue >= DemoStep.playZh.rawValue)
                        demoStepRow(step: .playZh, icon: "globe.asia.australia.fill", label: "现在听中文对照", sublabel: "中文翻译")
                        demoConnector(active: demoStep.rawValue >= DemoStep.playEn3.rawValue)
                        demoStepRow(step: .playEn3, icon: "sparkles", label: "最后一遍英语，感受变化", sublabel: "第 3 遍英语")
                    }
                    .padding(.horizontal, 32)

                    Spacer().frame(height: 16)

                    // Waveform
                    if showWaveform {
                        waveformView
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }

                    // After complete: result text + dialogue card
                    if demoStep == .complete {
                        VStack(spacing: 12) {
                            Text("是不是全都听懂了？")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Color.appPrimary)

                            Text("这就是 Castlingo 听力法")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.textTertiary)

                            VStack(spacing: 10) {
                                ForEach(0..<demoScript.count, id: \.self) { i in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(demoScript[i].en)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(Color.textPrimary)
                                        Text(demoScript[i].zh)
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(16)
                            .background(Color.primaryLight, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 32)
                            .padding(.top, 4)
                        }
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }

            // Fixed bottom button
            Button {
                if demoStep == .idle {
                    startDemo()
                } else if demoStep == .complete {
                    goToPage(.levelSelect)
                } else {
                    advanceDemo()
                }
            } label: {
                Text(demoButtonText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            .padding(.top, 16)
        }
    }

    private var demoButtonText: String {
        switch demoStep {
        case .idle: return "开始体验"
        case .complete: return "选择级别"
        default: return "继续"
        }
    }

    private func demoStepRow(step: DemoStep, icon: String, label: String, sublabel: String) -> some View {
        let isActive = demoStep.rawValue >= step.rawValue
        let isCurrent = demoStep == step

        let circleSize: CGFloat = isCurrent ? 44 : 40

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.appPrimary : Color(hex: "E2E8F0"))
                    .frame(width: circleSize, height: circleSize)
                    .animation(.easeInOut(duration: 0.3), value: isCurrent)

                if isActive && !isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: isCurrent ? 18 : 16))
                        .foregroundStyle(isActive ? .white : Color.textTertiary)
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 15, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.textPrimary : Color.textTertiary)

                Text(sublabel)
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? Color.appPrimary : Color.textQuaternary)
            }

            Spacer()

            // Right indicator — fixed 20x20 frame for alignment
            ZStack {
                if isActive && !isCurrent {
                    // Completed — green checkmark
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.success)
                } else if isCurrent && isAudioPlaying {
                    // Playing — pulsing green dot
                    Circle()
                        .fill(Color.success)
                        .frame(width: 10, height: 10)
                        .scaleEffect(isAudioPlaying ? 1.4 : 1.0)
                        .opacity(isAudioPlaying ? 0.6 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                            value: isAudioPlaying
                        )
                } else if isCurrent && !isAudioPlaying && demoStep != .idle {
                    // Waiting — static green dot
                    Circle()
                        .fill(Color.success)
                        .frame(width: 10, height: 10)
                }
            }
            .frame(width: 20, height: 20)
        }
    }

    private func demoConnector(active: Bool) -> some View {
        HStack {
            Rectangle()
                .fill(active ? Color.appPrimary.opacity(0.3) : Color(hex: "E2E8F0"))
                .frame(width: 2, height: 28)
                .padding(.leading, 21)
            Spacer()
        }
    }

    private var waveformView: some View {
        HStack(spacing: 3) {
            ForEach(0..<20, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.appPrimary.opacity(0.6))
                    .frame(width: 4, height: isAudioPlaying ? waveformHeights[i] : 4)
            }
        }
        .frame(height: 32)
        .padding(.horizontal, 60)
    }

    private func startDemo() {
        withAnimation(.easeInOut(duration: 0.3)) {
            demoStep = .playEn1
            showWaveform = true
        }
        playBundledAudio("onboarding_demo_en")
    }

    private func advanceDemo() {
        guard let next = DemoStep(rawValue: demoStep.rawValue + 1) else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            demoStep = next
        }

        switch next {
        case .playEn2:
            playBundledAudio("onboarding_demo_en")
        case .playZh:
            playBundledAudio("onboarding_demo_zh")
        case .playEn3:
            playBundledAudio("onboarding_demo_en")
        case .complete:
            withAnimation(.easeInOut(duration: 0.3)) {
                showWaveform = false
            }
            stopAllAudio()
        default:
            break
        }
    }

    // MARK: - Page 3: Trial Listen + Level Select

    @State private var selectedLevel: PodcastLevel = .easy
    @State private var trialPlayingLevel: PodcastLevel? = nil

    private var levelSelectPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 62)

            VStack(alignment: .leading, spacing: 8) {
                Text("试听并选择你的级别")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Text("点击播放按钮试听不同级别，选择最适合你的")
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
                    detail: "1000词以内 · 3-5分钟"
                )
                trialLevelCard(
                    level: .medium,
                    dotFill: Color.appPrimary,
                    dotBg: Color.primaryLighter,
                    name: "中级",
                    desc: "生活、文化、旅行话题",
                    detail: "3000词以内 · 5-8分钟"
                )
                trialLevelCard(
                    level: .hard,
                    dotFill: Color.hardOrange,
                    dotBg: Color.warningLight,
                    name: "高级",
                    desc: "新闻、商务、深度话题",
                    detail: "自然语速 · 8-12分钟"
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                goToPage(.userSource)
            } label: {
                Text("继续")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    private func trialLevelCard(level: PodcastLevel, dotFill: Color, dotBg: Color, name: String, desc: String, detail: String) -> some View {
        let isSelected = selectedLevel == level
        let isPlaying = trialPlayingLevel == level

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedLevel = level
            }
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
            selectedLevel = level
            playBundledAudio(trialAudioName(for: level)) {
                DispatchQueue.main.async {
                    trialPlayingLevel = nil
                }
            }
        }
    }

    // MARK: - Page 4: User Source

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
            Spacer().frame(height: 62)

            VStack(alignment: .leading, spacing: 8) {
                Text("你是怎么发现 Castlingo 的？")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Text("帮助我们把 Castlingo 推荐给更多人")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Spacer().frame(height: 28)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(sourceOptions) { option in
                        sourceOptionRow(option: option)
                    }
                }
                .padding(.horizontal, 24)
            }

            Button {
                if let source = selectedSource {
                    UserDefaults.standard.set(source, forKey: "userAcquisitionSource")
                }
                dataStore.selectedLevel = selectedLevel
                dataStore.hasCompletedOnboarding = true
            } label: {
                Text("进入 Castlingo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        Color.appPrimary.opacity(selectedSource != nil ? 1 : 0.5),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
            }
            .disabled(selectedSource == nil)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    private func sourceOptionRow(option: SourceOption) -> some View {
        let isSelected = selectedSource == option.label

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSource = option.label
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
}

#Preview {
    OnboardingView()
        .environment(DataStore())
}
