import SwiftUI

enum VocabFilter: String, CaseIterable {
    case all
    case strong
    case fading
    case new
}

/// 词汇 tab 主页 = 词汇小课堂：
/// 居中大标题 + 右上角「我的词汇」入口（统计/词表/练习都在那个页面里）。
/// 顶部「日常词汇 | 生活场景」双区块：
/// - 日常词汇：主题分类 chips + 主题课网格（OSS lessons/daily/）
/// - 生活场景：国家 chips + 分类课堂横滑（原样保留）
struct VocabularyView: View {
    @Environment(VocabularyStore.self) private var store
    @Environment(AudioPlayer.self) private var audioPlayer
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(SentenceStore.self) private var sentenceStore
    @Environment(LessonStore.self) private var lessonStore

    @State private var selectedLesson: LessonOpenTarget?
    @State private var showPaywall = false
    @State private var showMyVocabulary = false
    @State private var allTarget: LessonCategoryTarget?

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.bottom, 10)

                sectionSwitcher
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                if lessonStore.section == .daily {
                    themeSection
                } else {
                    sceneSection
                }
            }
        }
        .onAppear {
            lessonStore.loadIfNeeded()
            lessonStore.loadTodayIfNeeded()
            lessonStore.loadThemeIfNeeded()
        }
        .fullScreenCover(item: $selectedLesson) { target in
            LessonDetailView(item: target.item, country: target.country)
                .environment(store)
                .environment(lessonStore)
                .environment(sentenceStore)
        }
        .fullScreenCover(isPresented: $showMyVocabulary) {
            MyVocabularyView()
                .environment(store)
                .environment(audioPlayer)
                .environment(subscriptionManager)
        }
        .fullScreenCover(item: $allTarget) { target in
            LessonCategoryAllView(
                title: target.title,
                lessons: target.lessons,
                isLocked: { isLocked($0) },
                isFree: { !subscriptionManager.isProUser && lessonStore.isFreeSample($0) },
                isCompleted: { lessonStore.isCompleted($0.id) }
            ) { item in
                open(item)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(subscriptionManager)
        }
    }

    // MARK: - Header（居中大标题 + 右上角我的词汇入口）

    private var header: some View {
        ZStack {
            Text("词汇小课堂")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .tracking(-0.3)

            HStack {
                Spacer()
                Button { showMyVocabulary = true } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "book.fill")
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

    // MARK: - 双区块切换（日常词汇 | 生活场景，左右等宽）

    private var sectionSwitcher: some View {
        HStack(spacing: 10) {
            sectionButton(.daily, title: "日常词汇")
            sectionButton(.scene, title: "生活场景")
        }
    }

    private func sectionButton(_ section: LessonSection, title: String) -> some View {
        let selected = lessonStore.section == section
        return Button {
            guard !selected else { return }
            lessonStore.section = section
            Analytics.track(.vocabSectionSwitch, params: ["section": section.rawValue])
        } label: {
            Text(title)
                .font(.system(size: 15, weight: selected ? .bold : .semibold))
                .foregroundColor(selected ? .white : Color.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected ? Color.appPrimary : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color.clear : Color.border, lineWidth: 1)
            )
        }
    }

    // MARK: - 生活场景区（原有内容原样：国家 chips + 分类横滑）

    private var sceneSection: some View {
        Group {
            CountryChipsRow()
                .environment(lessonStore)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(lessonStore.byCategory, id: \.category) { group in
                        categorySection(group.category, lessons: group.lessons)
                    }

                    if lessonStore.lessons.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 100)
            }
        }
    }

    // MARK: - 日常词汇区（主题分类 chips + 主题课网格）

    private let themeColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    @ViewBuilder
    private var themeSection: some View {
        if lessonStore.themeLessons.isEmpty {
            VStack(spacing: 10) {
                if lessonStore.isLoadingThemeIndex {
                    ProgressView().tint(Color.appPrimary)
                    Text("加载中…")
                        .font(.system(size: 13))
                        .foregroundColor(Color.textTertiary)
                } else {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 30))
                        .foregroundColor(Color.textQuaternary)
                    Text("日常词汇即将上线")
                        .font(.system(size: 14))
                        .foregroundColor(Color.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
            Spacer()
        } else {
            themeCategoryChips
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: themeColumns, spacing: 12) {
                    ForEach(lessonStore.themeLessonsInSelectedCategory) { item in
                        LessonCoverCard(
                            item: item,
                            locked: isLocked(item),
                            free: !subscriptionManager.isProUser && lessonStore.isFreeSample(item),
                            completed: lessonStore.isCompleted(item.id),
                            onTap: {
                                Analytics.track(.themeLessonOpen, params: [
                                    "lesson_id": item.id, "category": item.category,
                                ])
                                open(item, country: LessonStore.themeCountry)
                            },
                            width: nil
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 100)
            }
        }
    }

    private var themeCategoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(lessonStore.themeCategories, id: \.id) { cat in
                    let selected = cat.id == lessonStore.selectedThemeCategory
                    Button {
                        guard !selected else { return }
                        lessonStore.selectedThemeCategory = cat.id
                        Analytics.track(.themeCategoryFilter, params: ["category": cat.id])
                    } label: {
                        Text(cat.zh)
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

    // MARK: - Lessons

    /// 分类区块：标题 + 右侧「查看更多」+ 单行横滑封面卡（与首页探索分类同构）
    private func categorySection(_ title: String, lessons: [SceneLessonIndexItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color.textPrimary)
                Spacer()
                Button {
                    allTarget = LessonCategoryTarget(title: title, lessons: lessons)
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
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(lessons) { item in
                        LessonCoverCard(
                            item: item,
                            locked: isLocked(item),
                            free: !subscriptionManager.isProUser && lessonStore.isFreeSample(item),
                            completed: lessonStore.isCompleted(item.id),
                            onTap: { open(item) }
                        )
                    }
                }
                .scrollTargetLayout()
            }
            .scrollClipDisabled()
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            if lessonStore.isLoadingIndex {
                ProgressView().tint(Color.appPrimary)
                Text("加载中…")
                    .font(.system(size: 13))
                    .foregroundColor(Color.textTertiary)
            } else {
                Image(systemName: "book.closed")
                    .font(.system(size: 30))
                    .foregroundColor(Color.textQuaternary)
                Text("该国家的课堂即将上线")
                    .font(.system(size: 14))
                    .foregroundColor(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func isLocked(_ item: SceneLessonIndexItem) -> Bool {
        if subscriptionManager.isProUser { return false }
        // 今日每日课当天免费（与 LessonAccessGate.canAccess 一致）
        if item.isDaily && LessonAccessGate.isToday(item.date) { return false }
        return !lessonStore.isFreeSample(item)
    }

    /// 打开课堂。country 缺省用当前所选国家；今日全局卡/主题课传各自的国家。
    private func open(_ item: SceneLessonIndexItem, country: LessonCountry? = nil) {
        if isLocked(item) {
            Analytics.track(.lessonPaywallView, params: [
                "lesson_id": item.id,
                "country": (country ?? lessonStore.currentCountry).id,
            ])
            showPaywall = true
        } else {
            selectedLesson = LessonOpenTarget(item: item, country: country ?? lessonStore.currentCountry)
        }
    }
}

/// 打开课堂详情的目标（课堂条目 + 所属国家，支持跨国家打开今日全局卡）
struct LessonOpenTarget: Identifiable {
    let item: SceneLessonIndexItem
    let country: LessonCountry
    var id: String { item.id }
}

/// 「查看更多」的打开目标（分类标题 + 该分类全部课堂）
struct LessonCategoryTarget: Identifiable {
    let title: String
    let lessons: [SceneLessonIndexItem]
    var id: String { title }
}

/// 查看更多：分类全部课堂网格页
struct LessonCategoryAllView: View {
    let title: String
    let lessons: [SceneLessonIndexItem]
    let isLocked: (SceneLessonIndexItem) -> Bool
    let isFree: (SceneLessonIndexItem) -> Bool
    let isCompleted: (SceneLessonIndexItem) -> Bool
    /// 点卡片回调（父级负责打开课堂详情/付费墙，避免双层 fullScreenCover 叠加崩溃）
    let onSelect: (SceneLessonIndexItem) -> Void

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
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(lessons) { item in
                            LessonCoverCard(
                                item: item,
                                locked: isLocked(item),
                                free: isFree(item),
                                completed: isCompleted(item),
                                onTap: {
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                        onSelect(item)
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
                }
            }
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text("\(lessons.count) 个课堂")
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

#Preview {
    VocabularyView()
        .environment(VocabularyStore())
        .environment(AudioPlayer())
        .environment(SubscriptionManager())
}
