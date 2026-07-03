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
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.zh)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("\(category.groupZh) · 按使用频率排序")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                }

                ForEach(category.expressions) { expression in
                    ExpressionRow(expression: expression, categoryZh: category.zh)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
    }
}

/// 一条表达的完整卡片：表达 + 意思 + 语感注释 + 国家差异 + 例句 + 发音/收藏
struct ExpressionRow: View {
    let expression: Expression
    let categoryZh: String

    @Environment(SentenceStore.self) private var sentenceStore

    private var saved: Bool {
        sentenceStore.isSaved(expression.english)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 表达本体
            HStack(alignment: .top, spacing: 10) {
                Button {
                    LessonAudioPlayer.shared.play(expression.audio) {
                        WordSpeaker.shared.speakSentence(expression.english.replacingOccurrences(of: "___", with: "something"))
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(expression.english)
                                .font(.system(size: 18, weight: .semibold, design: .serif))
                                .foregroundStyle(Color.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.appPrimary)
                                .padding(.top, 5)
                        }
                        Text(expression.meaningZh)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                    }
                }
                .buttonStyle(.plain)

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
                    Image(systemName: saved ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(saved ? Color.success : Color.textQuaternary)
                }
            }

            // 语感注释
            Text(expression.usageZh)
                .font(.system(size: 13))
                .foregroundStyle(Color.bodyText)
                .fixedSize(horizontal: false, vertical: true)

            // 国家差异
            if expression.hasCountryNote, let note = expression.countryNoteZh {
                HStack(alignment: .top, spacing: 5) {
                    Text("🌍")
                        .font(.system(size: 11))
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

            if saved {
                Text("✓ 已加入我的句子")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.success)
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.border, lineWidth: 1)
        )
    }
}
