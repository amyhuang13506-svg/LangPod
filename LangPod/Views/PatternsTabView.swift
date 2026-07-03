import SwiftUI

/// 句型 tab = 口语表达库：4 个大组 chips（日常反应/表达自己/会话技能/进阶地道），
/// 组内功能分类网格，点分类看表达列表（口语化 + 语感注释 + 国家差异 + 发音 + 收藏）。
/// 不分难度，按实用频率排序。右上「我的」= 我的句子收藏。
struct PatternsTabView: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(SentenceStore.self) private var sentenceStore

    @State private var expressionStore = ExpressionStore()
    @State private var selectedCategory: ExpressionCategoryIndexItem?
    @State private var showMySentences = false
    @State private var showPaywall = false

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
                    VStack(alignment: .leading, spacing: 14) {
                        if let group = expressionStore.selectedGroup {
                            Text(group.desc)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.textTertiary)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(group.categories) { category in
                                    categoryCard(category, groupIcon: group.icon)
                                }
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
        .sheet(item: $selectedCategory) { category in
            ExpressionListSheet(item: category)
                .environment(expressionStore)
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

    // MARK: - 大组 chips（4 个）

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(expressionStore.groups) { group in
                    let selected = group.id == expressionStore.selectedGroupId
                    Button {
                        guard !selected else { return }
                        expressionStore.selectedGroupId = group.id
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

    // MARK: - 分类卡

    private func categoryCard(_ category: ExpressionCategoryIndexItem, groupIcon: String) -> some View {
        let locked = isLocked(category)
        return Button {
            if locked {
                Analytics.track(.patternPaywallView, params: [
                    "category": category.id, "source": "patterns_tab",
                ])
                showPaywall = true
            } else {
                Analytics.track(.patternOpen, params: [
                    "category": category.id, "source": "patterns_tab",
                ])
                selectedCategory = category
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: groupIcon)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.appPrimary)
                    Spacer()
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.warning)
                    }
                }
                Text(category.zh)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(category.count) 条表达\(category.isFree ? " · 免费" : "")")
                    .font(.system(size: 11))
                    .foregroundStyle(category.isFree ? Color.success : Color.textTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func isLocked(_ category: ExpressionCategoryIndexItem) -> Bool {
        !category.isFree && !subscriptionManager.isProUser
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

// MARK: - 表达列表 sheet

struct ExpressionListSheet: View {
    let item: ExpressionCategoryIndexItem

    @Environment(ExpressionStore.self) private var expressionStore
    @Environment(SentenceStore.self) private var sentenceStore

    @State private var category: ExpressionCategory?
    @State private var loadFailed = false
    /// 折叠列表：默认只显示编号+表达，点开哪条展开哪条（手风琴式）
    @State private var expandedId: String?

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if let category {
                content(category)
            } else if loadFailed {
                VStack(spacing: 10) {
                    Text("加载失败").font(.system(size: 15)).foregroundStyle(Color.textSecondary)
                    Button("重试") { Task { await load() } }
                        .foregroundStyle(Color.appPrimary)
                }
            } else {
                ProgressView().tint(Color.appPrimary)
            }
        }
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    private func load() async {
        loadFailed = false
        if let loaded = await expressionStore.categoryDetail(id: item.id) {
            category = loaded
            LessonAudioPlayer.shared.prefetch(
                loaded.expressions.flatMap { [$0.audio] + $0.examples.map(\.audio) }.compactMap { $0 }
            )
        } else {
            loadFailed = true
        }
    }

    private func content(_ category: ExpressionCategory) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.zh)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("\(category.groupZh) · 按使用频率排序 · 点开看用法和场景")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.bottom, 4)

                ForEach(Array(category.expressions.enumerated()), id: \.element.id) { index, expression in
                    ExpressionRow(
                        expression: expression,
                        categoryZh: category.zh,
                        number: index + 1,
                        expanded: expandedId == expression.id
                    ) {
                        withAnimation(.spring(duration: 0.3)) {
                            expandedId = expandedId == expression.id ? nil : expression.id
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
    }
}

/// 一条表达：折叠态 = 编号 + 表达 + 中文意思；展开态 = 语感注释 + 国家差异 + 例句 + 场景示例
struct ExpressionRow: View {
    let expression: Expression
    let categoryZh: String
    let number: Int
    let expanded: Bool
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
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(expanded ? Color.appPrimary.opacity(0.4) : Color.border, lineWidth: 1)
        )
    }

    // MARK: - 折叠头（始终显示）

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
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(expression.meaningZh)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(expanded ? nil : 1)
                }
                Spacer()
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
        .buttonStyle(.plain)
    }

    // MARK: - 展开内容

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 发音 + 收藏操作行
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

            // 语感注释
            Text(expression.usageZh)
                .font(.system(size: 13))
                .foregroundStyle(Color.bodyText)
                .fixedSize(horizontal: false, vertical: true)

            // 国家差异
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

            // 例句
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

            // 场景示例（例句下面：具体场景 + 一来一回对话）
            if let scene = expression.scene {
                sceneBlock(scene)
            }
        }
    }

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
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.warningLight.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
