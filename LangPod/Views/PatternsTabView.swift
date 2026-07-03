import SwiftUI

/// 句型 tab = 口语表达库。结构仿首页探索分类：
/// 4 个大组 chips → 分类 = 封面插画网格卡（图片 + 标题在下）→
/// 点卡片进分类详情页（封面图在顶部 + 表达列表行，点行展开）。
/// 右上「我的」= 我的句子收藏。
struct PatternsTabView: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(SentenceStore.self) private var sentenceStore

    @State private var expressionStore = ExpressionStore()
    @State private var showMySentences = false
    @State private var showPaywall = false
    @State private var selectedCategory: ExpressionCategoryIndexItem?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

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
                    if let group = expressionStore.selectedGroup {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(group.categories) { category in
                                ExpressionCoverCard(
                                    item: category,
                                    locked: isLocked(category)
                                ) {
                                    open(category)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 60)
                    } else {
                        emptyState
                    }
                }
            }
        }
        .onAppear { expressionStore.loadIfNeeded() }
        .fullScreenCover(item: $selectedCategory) { item in
            ExpressionCategoryView(item: item, store: expressionStore)
                .environment(sentenceStore)
                .environment(subscriptionManager)
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
                        HStack(spacing: 5) {
                            Image(systemName: group.icon)
                                .font(.system(size: 11))
                            Text(group.zh)
                                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                        }
                        .foregroundColor(selected ? .white : Color.textSecondary)
                        .padding(.horizontal, 12)
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

    private func isLocked(_ item: ExpressionCategoryIndexItem) -> Bool {
        !item.isFree && !subscriptionManager.isProUser
    }

    private func open(_ item: ExpressionCategoryIndexItem) {
        if isLocked(item) {
            Analytics.track(.patternPaywallView, params: [
                "category": item.id, "source": "patterns_tab",
            ])
            showPaywall = true
        } else {
            expressionStore.loadGroupDetails(expressionStore.selectedGroupId)
            selectedCategory = item
        }
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

// MARK: - 分类封面网格卡（图片 + 标题在下，同课堂封面卡样式）

struct ExpressionCoverCard: View {
    let item: ExpressionCategoryIndexItem
    let locked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    CachedAsyncImage(url: item.cover ?? "") {
                        ZStack {
                            Rectangle().fill(Color.primaryLighter)
                            Image(systemName: "quote.bubble.fill")
                                .font(.system(size: 24))
                                .foregroundColor(Color.appPrimary.opacity(0.5))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
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
                    Text(item.zh)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(item.count) 句\(item.isFree ? " · 免费" : "")")
                        .font(.system(size: 11))
                        .foregroundColor(item.isFree ? Color.success : Color.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 分类详情页（封面图在顶 + 表达列表）

struct ExpressionCategoryView: View {
    let item: ExpressionCategoryIndexItem
    let store: ExpressionStore

    @Environment(\.dismiss) private var dismiss
    @Environment(SentenceStore.self) private var sentenceStore
    /// 手风琴：全页同时只展开一条
    @State private var expandedId: String?

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroCover

                    content
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 60)
                }
            }
            .ignoresSafeArea(edges: .top)

            closeButton
        }
        .task {
            _ = await store.categoryDetail(id: item.id)
        }
    }

    /// 顶部封面：主页网格卡同一张图放大作 hero，底部渐变压标题
    private var heroCover: some View {
        CachedAsyncImage(url: item.cover ?? "") {
            ZStack {
                Rectangle().fill(Color.primaryLighter)
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 40))
                    .foregroundColor(Color.appPrimary.opacity(0.4))
            }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(
            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottomLeading) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.zh)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(item.count) 句")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                if item.isFree {
                    Text("免费")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.success))
                }
            }
            .padding(16)
        }
    }

    private var closeButton: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let detail = store.details[item.id] {
            VStack(spacing: 0) {
                ForEach(Array(detail.expressions.enumerated()), id: \.element.id) { index, expression in
                    ExpressionRow(
                        expression: expression,
                        categoryZh: detail.zh,
                        number: index + 1,
                        expanded: expandedId == expression.id
                    ) {
                        withAnimation(.spring(duration: 0.3)) {
                            expandedId = expandedId == expression.id ? nil : expression.id
                        }
                    }
                    if expression.id != detail.expressions.last?.id {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
        } else {
            HStack {
                ProgressView().tint(Color.appPrimary).scaleEffect(0.8)
                Text("加载中…")
                    .font(.system(size: 12))
                    .foregroundColor(Color.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
        }
    }
}

// MARK: - 表达行（列表行样式，点击展开）

/// 折叠态 = 编号 + 表达 + 中文意思（一行）；展开态 = 发音/收藏 + 语感注释 + 国家差异 + 例句 + 场景插画卡
struct ExpressionRow: View {
    let expression: Expression
    let categoryZh: String
    let number: Int
    let expanded: Bool
    var locked: Bool = false
    let onToggle: () -> Void

    @Environment(SentenceStore.self) private var sentenceStore

    private var saved: Bool {
        sentenceStore.isSaved(expression.english)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            collapsedHeader

            if expanded {
                expandedContent
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - 折叠行

    private var collapsedHeader: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 10) {
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(expanded ? .white : Color.appPrimary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(expanded ? Color.appPrimary : Color.primaryLight))

                VStack(alignment: .leading, spacing: 2) {
                    Text(expression.english)
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(locked ? Color.textTertiary : Color.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(expression.meaningZh)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(expanded ? nil : 1)
                }
                Spacer()
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.warning)
                } else {
                    if saved && !expanded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.success)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textQuaternary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 展开内容

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    LessonAudioPlayer.shared.play(expression.audio) {
                        WordSpeaker.shared.speakSentence(expression.english.replacingOccurrences(of: "___", with: "something"))
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 11))
                        Text("发音").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.appPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.primaryLight))
                }
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
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: saved ? "checkmark" : "plus").font(.system(size: 11, weight: .semibold))
                        Text(saved ? "已加入我的句子" : "加入我的句子").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(saved ? Color.success : .white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(saved ? Color.successLight : Color.appPrimary))
                }
                Spacer()
            }

            Text(expression.usageZh)
                .font(.system(size: 13))
                .foregroundStyle(Color.bodyText)
                .fixedSize(horizontal: false, vertical: true)

            if expression.hasCountryNote, let note = expression.countryNoteZh {
                HStack(alignment: .top, spacing: 5) {
                    Text("🌍").font(.system(size: 11))
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.gold)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.warningLight, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(spacing: 6) {
                ForEach(expression.examples) { example in
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
                        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let scene = expression.scene {
                sceneBlock(scene)
            }
        }
    }

    // MARK: - 场景示例

    @ViewBuilder
    private func sceneBlock(_ scene: ExpressionScene) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "theatermasks.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.gold)
                Text("场景示例")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.gold)
            }
            Text(scene.setupZh)
                .font(.system(size: 13))
                .foregroundStyle(Color.bodyText)
                .fixedSize(horizontal: false, vertical: true)

            if let image = scene.image, !image.isEmpty {
                sceneImageCard(scene, imageUrl: image)
            } else {
                sceneDialogueList(scene)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.warningLight.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    /// 场景插画卡：gpt-image-1 场景图（A 左 B 右、上方留白），对话气泡由 App 叠加在
    /// 图片上方留白区（文字零拼错、点气泡播该句音频）。
    private func sceneImageCard(_ scene: ExpressionScene, imageUrl: String) -> some View {
        CachedAsyncImage(url: imageUrl) {
            Rectangle().fill(Color.primaryLighter)
        }
        .aspectRatio(3.0 / 2.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                ForEach(scene.dialogue) { line in
                    dialogueBubble(line)
                        .frame(maxWidth: .infinity, alignment: line.speaker == "A" ? .leading : .trailing)
                }
            }
            .padding(8)
        }
    }

    /// 叠加在插画上的对话气泡（A 靠左紫头像，B 靠右橙头像）
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
            .frame(maxWidth: 260, alignment: line.speaker == "A" ? .leading : .trailing)
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

    /// 无插画时的纯文字对话列表（老数据回落）
    private func sceneDialogueList(_ scene: ExpressionScene) -> some View {
        VStack(spacing: 6) {
            ForEach(scene.dialogue) { line in
                Button {
                    LessonAudioPlayer.shared.play(line.audio) {
                        WordSpeaker.shared.speakSentence(line.en)
                    }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text(line.speaker)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(line.speaker == "A" ? Color.accentPurple : Color.hardOrange))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.en)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                                .multilineTextAlignment(.leading)
                            Text(line.zh)
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
                }
                .buttonStyle(.plain)
            }
        }
    }
}
