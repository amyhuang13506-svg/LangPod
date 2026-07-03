import SwiftUI

/// 句型 tab = 口语表达库。交互与首页探索分类同构：
/// 4 个大组 chips → 每个分类一个区块（标题 + 右侧「查看更多」+ 单行横滑场景插画卡）。
/// 每张卡 = 一条表达（封面 = 它的场景插画）；点卡进翻页详情（左右滑切表达，无页码）；
/// 「查看更多」= 该分类全部卡片的网格页。右上「我的」= 我的句子收藏。
struct PatternsTabView: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(SentenceStore.self) private var sentenceStore

    @State private var expressionStore = ExpressionStore()
    @State private var showMySentences = false
    @State private var showPaywall = false
    @State private var pagerTarget: ExpressionPagerTarget?
    @State private var allTarget: ExpressionCategoryIndexItem?

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.bottom, 10)

                groupChips
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        if let group = expressionStore.selectedGroup {
                            ForEach(group.categories) { category in
                                categorySection(category)
                            }
                        } else {
                            emptyState
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 60)
                }
            }
        }
        .onAppear { expressionStore.loadIfNeeded() }
        .fullScreenCover(item: $pagerTarget) { target in
            ExpressionPagerView(
                item: target.category,
                startIndex: target.index,
                store: expressionStore
            )
            .environment(sentenceStore)
        }
        .fullScreenCover(item: $allTarget) { item in
            ExpressionCategoryAllView(item: item, store: expressionStore) { index in
                pagerTarget = ExpressionPagerTarget(category: item, index: index)
            }
            .environment(sentenceStore)
        }
        .fullScreenCover(isPresented: $showMySentences) {
            MySentencesView()
                .environment(sentenceStore)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(subscriptionManager)
        }
    }

    // MARK: - Header（居中标题 + 右上我的）

    private var header: some View {
        ZStack {
            Text("句型")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .tracking(-0.3)

            HStack {
                Spacer()
                Button { showMySentences = true } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 16))
                        Text("我的")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Color.appPrimary)
                }
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 24)
        .padding(.top, 16)
    }

    // MARK: - 大组 chips

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(expressionStore.groups) { group in
                    let selected = group.id == expressionStore.selectedGroupId
                    Button {
                        guard !selected else { return }
                        expressionStore.selectedGroupId = group.id
                        expressionStore.loadGroupDetails(group.id)
                    } label: {
                        Text(group.zh)
                            .font(.system(size: 13, weight: selected ? .semibold : .medium))
                            .foregroundColor(selected ? .white : Color.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                        .background(
                            Capsule().fill(selected ? Color.appPrimary : Color.white)
                        )
                        .overlay(
                            Capsule().stroke(selected ? Color.clear : Color.border, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    // MARK: - 分类区块（标题 + 查看更多 + 单行横滑卡）

    @ViewBuilder
    private func categorySection(_ item: ExpressionCategoryIndexItem) -> some View {
        let locked = isLocked(item)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.zh)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color.textPrimary)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.warning)
                } else if item.isFree {
                    Text("免费")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.success)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.successLight))
                }
                Spacer()
                Button {
                    if locked {
                        trackPaywall(item)
                        showPaywall = true
                    } else {
                        allTarget = item
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("查看更多")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.appPrimary)
                }
            }

            if let detail = expressionStore.details[item.id] {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(detail.expressions.enumerated()), id: \.element.id) { index, expression in
                            ExpressionSceneCard(
                                expression: expression,
                                fallbackCover: item.cover ?? "",
                                locked: locked
                            ) {
                                if locked {
                                    trackPaywall(item)
                                    showPaywall = true
                                } else {
                                    pagerTarget = ExpressionPagerTarget(category: item, index: index)
                                }
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white)
                                .frame(width: 200, height: 166)
                                .overlay(ProgressView().tint(Color.appPrimary).scaleEffect(0.7))
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private func isLocked(_ item: ExpressionCategoryIndexItem) -> Bool {
        !item.isFree && !subscriptionManager.isProUser
    }

    private func trackPaywall(_ item: ExpressionCategoryIndexItem) {
        Analytics.track(.patternPaywallView, params: [
            "category": item.id, "source": "patterns_tab",
        ])
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            if expressionStore.isLoading {
                ProgressView().tint(Color.appPrimary)
            } else {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 30))
                    .foregroundColor(Color.textQuaternary)
                Text("表达库即将上线")
                    .font(.system(size: 14))
                    .foregroundColor(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

/// 翻页详情的打开目标（分类 + 起始下标）
struct ExpressionPagerTarget: Identifiable {
    let category: ExpressionCategoryIndexItem
    let index: Int
    var id: String { "\(category.id)_\(index)" }
}

// MARK: - 表达场景卡（横滑区块 + 查看更多网格共用：场景插画 + 表达在下）

struct ExpressionSceneCard: View {
    let expression: Expression
    let fallbackCover: String
    let locked: Bool
    let onTap: () -> Void
    var width: CGFloat? = 200

    private var coverUrl: String {
        if let img = expression.scene?.image, !img.isEmpty { return img }
        return fallbackCover
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    CachedAsyncImage(url: coverUrl) {
                        ZStack {
                            Rectangle().fill(Color.primaryLighter)
                            Image(systemName: "quote.bubble.fill")
                                .font(.system(size: 22))
                                .foregroundColor(Color.appPrimary.opacity(0.5))
                        }
                    }
                    .frame(width: width)
                    .frame(maxWidth: width == nil ? .infinity : nil)
                    .frame(height: 120)
                    .clipped()

                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(.black.opacity(0.55)))
                            .padding(6)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(expression.english)
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)
                    Text(expression.meaningZh)
                        .font(.system(size: 11))
                        .foregroundColor(Color.textTertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(width: width, alignment: .leading)
                .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 查看更多：分类全部表达网格页

struct ExpressionCategoryAllView: View {
    let item: ExpressionCategoryIndexItem
    let store: ExpressionStore
    /// 点卡片回调（父级负责打开翻页详情，避免双层 fullScreenCover 叠加崩溃）
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    if let detail = store.details[item.id] {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Array(detail.expressions.enumerated()), id: \.element.id) { index, expression in
                                ExpressionSceneCard(
                                    expression: expression,
                                    fallbackCover: item.cover ?? "",
                                    locked: false,
                                    onTap: {
                                        dismiss()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                            onSelect(index)
                                        }
                                    },
                                    width: nil
                                )
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 60)
                    } else {
                        ProgressView().tint(Color.appPrimary).padding(.top, 60)
                    }
                }
            }
        }
        .task {
            _ = await store.categoryDetail(id: item.id)
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(item.zh)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text("\(item.count) 句")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - 翻页详情（左右滑切表达，无页码）

struct ExpressionPagerView: View {
    let item: ExpressionCategoryIndexItem
    let startIndex: Int
    let store: ExpressionStore

    @Environment(\.dismiss) private var dismiss
    @Environment(SentenceStore.self) private var sentenceStore
    @State private var pageIndex: Int = 0
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if let detail = store.details[item.id] {
                    TabView(selection: $pageIndex) {
                        ForEach(Array(detail.expressions.enumerated()), id: \.element.id) { index, expression in
                            ExpressionPageView(expression: expression, categoryZh: detail.zh)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                } else {
                    Spacer()
                    ProgressView().tint(Color.appPrimary)
                    Spacer()
                }
            }
        }
        .onAppear {
            guard !appeared else { return }
            appeared = true
            pageIndex = startIndex
        }
        .task {
            _ = await store.categoryDetail(id: item.id)
        }
    }

    private var header: some View {
        ZStack {
            Text(item.zh)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

// MARK: - 单条表达页（场景插画 + 气泡 + 讲解）

struct ExpressionPageView: View {
    let expression: Expression
    let categoryZh: String

    @Environment(SentenceStore.self) private var sentenceStore
    @State private var toast: String?

    private var saved: Bool {
        sentenceStore.isSaved(expression.english)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                if let scene = expression.scene {
                    sceneCard(scene)
                    Text(scene.setupZh)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 标题行：表达 + 意思，右上角 🔊 发音 / ＋ 加入我的句子（去掉文字按钮）
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(expression.english)
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(Color.textPrimary)
                        Text(expression.meaningZh)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    speakButton
                    saveButton
                }

                Text(expression.usageZh)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.bodyText)
                    .fixedSize(horizontal: false, vertical: true)

                if expression.hasCountryNote, let note = expression.countryNoteZh {
                    HStack(alignment: .top, spacing: 5) {
                        Text("🌍").font(.system(size: 12))
                        Text(note)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.gold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.warningLight, in: RoundedRectangle(cornerRadius: 10))
                }

                if !expression.examples.isEmpty {
                    Text("例句")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                    VStack(spacing: 8) {
                        ForEach(expression.examples) { example in
                            exampleRow(example)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 50)
        }
        // 顶部小横条反馈（与首页视频字幕加词同款）
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.appPrimary.opacity(0.92), in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - 场景插画 + 叠加气泡

    /// gpt-image-1 场景图（A 左 B 右、上方留白），对话气泡由 App 叠加（文字零拼错、
    /// 点气泡播该句音频）。无插画时回落为纯文字对话卡。
    @ViewBuilder
    private func sceneCard(_ scene: ExpressionScene) -> some View {
        if let image = scene.image, !image.isEmpty {
            CachedAsyncImage(url: image) {
                Rectangle().fill(Color.primaryLighter)
            }
            .aspectRatio(3.0 / 2.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .bottom) {
                // 气泡贴图片底部，不挡人物脸部
                VStack(spacing: 6) {
                    ForEach(scene.dialogue) { line in
                        dialogueBubble(line)
                            .frame(maxWidth: .infinity, alignment: line.speaker == "A" ? .leading : .trailing)
                    }
                }
                .padding(10)
            }
        } else {
            VStack(spacing: 8) {
                ForEach(scene.dialogue) { line in
                    dialogueBubble(line)
                        .frame(maxWidth: .infinity, alignment: line.speaker == "A" ? .leading : .trailing)
                }
            }
            .padding(12)
            .background(Color.warningLight.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func dialogueBubble(_ line: ExpressionDialogueLine) -> some View {
        Button {
            LessonAudioPlayer.shared.play(line.audio) {
                WordSpeaker.shared.speakSentence(line.en)
            }
        } label: {
            HStack(alignment: .top, spacing: 5) {
                if line.speaker == "A" { speakerDot(line.speaker) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(line.en)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(line.zh)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.appPrimary.opacity(0.7))
                    .padding(.top, 3)
                if line.speaker != "A" { speakerDot(line.speaker) }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(.white.opacity(0.96))
                    .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
            )
            .frame(maxWidth: 270, alignment: line.speaker == "A" ? .leading : .trailing)
        }
        .buttonStyle(.plain)
    }

    private func speakerDot(_ speaker: String) -> some View {
        Text(speaker)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(Circle().fill(speaker == "A" ? Color.accentPurple : Color.hardOrange))
            .padding(.top, 1)
    }

    // MARK: - 图标按钮（🔊 发音 / ＋ 加入我的句子）+ 例句

    private var speakButton: some View {
        Button {
            LessonAudioPlayer.shared.play(expression.audio) {
                WordSpeaker.shared.speakSentence(expression.english.replacingOccurrences(of: "___", with: "something"))
            }
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.appPrimary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.primaryLight))
        }
    }

    private var saveButton: some View {
        Button {
            guard !saved else { return }
            let added = sentenceStore.add(SavedSentence(
                english: expression.english,
                chinese: expression.meaningZh,
                scene: categoryZh,
                source: "pattern",
                sourceLabel: categoryZh,
                audioUrl: expression.audio,
                audioStart: nil,
                audioEnd: nil,
                savedDate: Date()
            ))
            if added {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    toast = "已加入句型库"
                }
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    withAnimation { toast = nil }
                }
            }
        } label: {
            Image(systemName: saved ? "checkmark" : "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(saved ? Color.success : .white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(saved ? Color.successLight : Color.appPrimary))
        }
    }

    private func exampleRow(_ example: ExpressionExample) -> some View {
        Button {
            LessonAudioPlayer.shared.play(example.audio) {
                WordSpeaker.shared.speakSentence(example.en)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(example.en)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(example.zh)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.appPrimary.opacity(0.7))
                    .padding(.top, 3)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
