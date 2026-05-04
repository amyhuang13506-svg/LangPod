import SwiftUI

/// 「硅谷原声」歌词式字幕视图（Apple Music 风格）。
/// - 在播放页内联展示，不弹窗
/// - 当前段居中放大高亮，过去/未来段灰一些
/// - Pro 用户：所有段的每个单词独立可点 → 一键加生词本
/// - 免费用户：只看英文，单词不可点；当前段下方有「Pro 解锁双语 + 生词」提示
struct RawSubtitleSheet: View {
    let transcript: RawTranscript
    let currentTime: Double
    let isPro: Bool
    /// 是否显示中文翻译。false = 全英模式（即使 Pro 用户也只看英文，沉浸训练听力）
    let showChinese: Bool
    let onUpgrade: () -> Void
    /// 用户点击单词 —— 父视图弹预览卡，由用户决定是否加入生词本（不再自动加）
    let onTapWord: (String, RawTranscriptSegment) -> Void
    /// 用户点击字幕行（非单词区域）→ 跳到该段开头，进度条同步
    let onSeek: (Double) -> Void

    /// 当前段（按 currentTime 命中或最近的过去段）
    private var currentSegmentId: String? {
        let active = transcript.segments.first(where: { $0.start <= currentTime && currentTime < $0.end })
        let last = transcript.segments.last(where: { $0.start <= currentTime })
        return (active ?? last)?.id
    }

    @Environment(\.scenePhase) private var scenePhase
    /// 进后台 / 回前台后的"下一次"滚动跳过动画，避免一长段 rolling
    @State private var skipNextScrollAnimation: Bool = false
    /// Apple Music / 网易云规则：手动滚动只是「browse」状态，下一段播放就遗忘。
    /// isUserScrolling=true 仅用于：① 显示 scrub bar ② 暂时不打断手指
    @State private var isUserScrolling: Bool = false
    @State private var scrolledToID: String?
    /// Seek lock：用户点字幕 / scrub 跳转后，AVPlayer 短暂回弹的 600ms 期间
    /// 强制留在目标段，避免抖动
    @State private var seekLockedToID: String?
    @State private var seekLockTask: Task<Void, Never>?

    var body: some View {
        ScrollViewReader { proxy in
            // GeometryReader 量出字幕区高度，用于精准放置 scrub bar 在 18% 位置
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            // 顶部 padding：用空 spacer，保证第一段也能滚到 18% 位置
                            Color.clear.frame(height: 60)

                            ForEach(transcript.segments) { seg in
                                segmentRow(seg)
                                    .id(seg.id)
                            }

                            Color.clear.frame(height: 200)
                        }
                        .padding(.horizontal, 20)
                        .scrollTargetLayout()
                    }
                    // 关键：scrollPosition 和 proxy.scrollTo 用同一个 anchor，
                    // 避免两个机制争抢导致字幕回弹/横切。
                    .scrollPosition(id: $scrolledToID, anchor: autoAnchor)
                    .scrollIndicators(.hidden)
                    // 顶部渐隐：让上方字幕淡出，避免硬切到视频边缘
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [Color.black, Color.black.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 70)
                        .allowsHitTesting(false)
                    }
                // 用户手指拖动 → 显示 scrub bar。无 idle timer：next segment 自然结束 manual 模式。
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { _ in
                            if !isUserScrolling { isUserScrolling = true }
                        }
                )
                .onChange(of: currentSegmentId) { _, newId in
                    guard let id = newId else { return }

                    // Seek 锁定期：AVPlayer 600ms 内时间会抖动，强制锁在 seek 目标
                    if let locked = seekLockedToID {
                        if scrolledToID != locked { scrolledToID = locked }
                        return
                    }

                    // 音乐播放器规则：新段播放 → 立刻遗忘手动滚动位置，scrub bar 消失
                    if isUserScrolling { isUserScrolling = false }

                    if skipNextScrollAnimation {
                        scrolledToID = id
                        skipNextScrollAnimation = false
                    } else {
                        // 苹果音乐式平滑滚动 — spring 给一种"有惯性、自然减速"的感觉
                        withAnimation(.spring(response: 0.65, dampingFraction: 0.88)) {
                            scrolledToID = id
                        }
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        skipNextScrollAnimation = true
                        if let id = currentSegmentId { scrolledToID = id }
                    } else {
                        skipNextScrollAnimation = true
                    }
                }
                .onAppear {
                    if let id = currentSegmentId {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            scrolledToID = id
                        }
                    }
                }

                // 网易云风格 scrub bar：左侧时间戳 + 横向细线 + 右侧三角
                // 横向贯穿整屏，精确指示「点了就播放这一行」
                if isUserScrolling, let id = scrolledToID,
                   let seg = transcript.segments.first(where: { $0.id == id }) {
                    HStack(spacing: 10) {
                        Text(formatTime(seg.start))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Rectangle()
                            .fill(Color.white.opacity(0.32))
                            .frame(height: 1)
                        Button {
                            performSeek(to: seg)
                            let h = UIImpactFeedbackGenerator(style: .light)
                            h.impactOccurred()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.55))
                                    .overlay(
                                        Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.8)
                                    )
                                    .frame(width: 22, height: 22)
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .offset(x: 0.5)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        // 半透明黑色横条背景，跟网易云一致
                        Color.black.opacity(0.35)
                            .background(.ultraThinMaterial.opacity(0.4))
                    )
                    // scrub bar 放在与 autoAnchor 相同的 y 位置（18% from top），
                    // 这样 scrub bar 视觉上正好压在被 scrollPosition 锚定的那段字幕上
                    .offset(y: geo.size.height * autoAnchor.y - 20)
                    .transition(.opacity)
                }
                }  // ZStack
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isUserScrolling)
            }  // GeometryReader
        }
    }

    /// auto-scroll 时把当前播放段锚到顶部 18% 位置（贴近视频区，方便同时看视频和字幕）。
    /// 使用 UnitPoint 自定义 anchor，比 .top / .center 更精准。
    private var autoAnchor: UnitPoint { UnitPoint(x: 0.5, y: 0.18) }

    /// 分:秒 格式 — 长视频也用纯分钟（如 123:45），跟视频进度条对得上
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    @ViewBuilder
    private func segmentRow(_ seg: RawTranscriptSegment) -> some View {
        let isScrollTarget = isUserScrolling && seg.id == scrolledToID
        let isActive = !isUserScrolling && seg.id == currentSegmentId
        let isFocused = isActive || isScrollTarget

        VStack(alignment: .leading, spacing: 6) {
            if isPro {
                wordTaggedLine(seg, isFocused: isFocused, isActive: isActive)
            } else {
                Text(seg.en)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isFocused ? .white : Color(white: 0.55))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isPro, showChinese, let zh = seg.zh, !zh.isEmpty {
                Text(zh)
                    .font(.system(size: 13))
                    .foregroundStyle(isFocused ? .white.opacity(0.85) : Color(white: 0.5))
                    .fixedSize(horizontal: false, vertical: true)
            } else if !isPro && isActive {
                Button(action: onUpgrade) {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9))
                        Text("Pro 解锁中文翻译 + 点词加生词本")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color(hex: "FFD60A"))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            performSeek(to: seg)
        }
    }

    /// 统一处理 seek：调用 onSeek + 锁住 auto-scroll 600ms 防止抖动回弹
    private func performSeek(to seg: RawTranscriptSegment) {
        onSeek(seg.start)
        isUserScrolling = false
        seekLockedToID = seg.id
        seekLockTask?.cancel()
        seekLockTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            if !Task.isCancelled {
                await MainActor.run { seekLockedToID = nil }
            }
        }
    }

    // 把英文按词拆开，每个词都是独立可点的 view（Pro 模式）。
    // 非焦点行用实色灰（不是 white opacity），避免在黑底上看起来像"被蒙住的字"。
    // 当 segment 携带 words 词级时间戳时，启用 Karaoke 模式：当前正在说的词高亮黄色。
    @ViewBuilder
    private func wordTaggedLine(_ seg: RawTranscriptSegment, isFocused: Bool, isActive: Bool) -> some View {
        if let timedWords = seg.words, !timedWords.isEmpty {
            karaokeWordLine(seg, words: timedWords, isFocused: isFocused, isActive: isActive)
        } else {
            // Fallback：老数据没有词级时间戳，用 regex 拆词，无 karaoke
            legacyWordLine(seg, isFocused: isFocused)
        }
    }

    /// Karaoke 模式：每个词独立 view，用真实词级时间戳判定当前是否正在说
    private func karaokeWordLine(
        _ seg: RawTranscriptSegment,
        words: [WordTimestamp],
        isFocused: Bool,
        isActive: Bool
    ) -> some View {
        let baseColor: Color = isFocused ? .white : Color(white: 0.55)
        // 哪个词正在说？只在 isActive（音频正落在该段）时计算，否则全段同色
        let activeWordIdx: Int? = isActive ? currentWordIndex(in: words, at: currentTime) : nil
        return WordFlowLayout(spacing: 5, lineSpacing: 4) {
            ForEach(words.indices, id: \.self) { i in
                let timed = words[i]
                let isCurrent = (i == activeWordIdx)
                Button {
                    let plain = stripPunct(timed.w).lowercased()
                    if !plain.isEmpty { onTapWord(plain, seg) }
                } label: {
                    Text(timed.w)
                        .font(.system(size: 16, weight: isCurrent ? .bold : .medium))
                        .foregroundStyle(isCurrent ? Color(hex: "FFD60A") : baseColor)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.15), value: activeWordIdx)
    }

    /// Fallback：老数据无词级时间戳时的渲染（regex 拆词，无 karaoke）
    private func legacyWordLine(_ seg: RawTranscriptSegment, isFocused: Bool) -> some View {
        let tokens = tokenize(seg.en)
        let color: Color = isFocused ? .white : Color(white: 0.55)
        return WordFlowLayout(spacing: 5, lineSpacing: 4) {
            ForEach(tokens.indices, id: \.self) { i in
                let token = tokens[i]
                if token.isWord {
                    Button {
                        onTapWord(token.text.lowercased(), seg)
                    } label: {
                        Text(token.text)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(color)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(token.text)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(color)
                }
            }
        }
    }

    /// 二分查找当前时间落在哪个词。返回 nil 表示在词与词之间的间隙
    private func currentWordIndex(in words: [WordTimestamp], at time: Double) -> Int? {
        var lo = 0, hi = words.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let w = words[mid]
            if time < w.s {
                hi = mid - 1
            } else if time >= w.e {
                lo = mid + 1
            } else {
                return mid
            }
        }
        // 落在词缝里：返回最近过去的词，让高亮"粘"住而不是闪
        return hi >= 0 ? hi : nil
    }

    /// 去掉单词尾部标点（"hello," → "hello"）用于查词
    private func stripPunct(_ s: String) -> String {
        var out = s
        while let last = out.last, ".,!?;:\"'()[]".contains(last) {
            out.removeLast()
        }
        while let first = out.first, ".,!?;:\"'()[]".contains(first) {
            out.removeFirst()
        }
        return out
    }

    /// 把句子分词为「词 / 非词（标点 / 数字）」的有序列表
    private func tokenize(_ s: String) -> [Token] {
        var out: [Token] = []
        var current = ""
        var currentIsWord: Bool? = nil

        func flush() {
            if !current.isEmpty, let isWord = currentIsWord {
                out.append(Token(text: current, isWord: isWord))
            }
            current = ""
            currentIsWord = nil
        }

        for ch in s {
            let isLetter = ch.isLetter || ch == "'" || ch == "-"
            if currentIsWord == nil {
                currentIsWord = isLetter
                current.append(ch)
            } else if currentIsWord == isLetter {
                current.append(ch)
            } else {
                flush()
                currentIsWord = isLetter
                current.append(ch)
            }
        }
        flush()
        return out
    }

    private struct Token {
        let text: String
        let isWord: Bool
    }
}

// MARK: - WordFlowLayout（手写简单流式布局，逐词换行）

private struct WordFlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return measure(width: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = measure(width: bounds.width, subviews: subviews)
        for (idx, point) in result.points.enumerated() {
            let s = subviews[idx].sizeThatFits(.unspecified)
            subviews[idx].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: s.width, height: s.height)
            )
        }
    }

    private func measure(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > width && x > 0 {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
            maxWidth = max(maxWidth, x - spacing)
        }
        return (size: CGSize(width: maxWidth, height: y + lineHeight), points: points)
    }
}
