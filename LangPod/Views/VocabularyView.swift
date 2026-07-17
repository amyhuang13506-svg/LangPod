import SwiftUI

enum VocabFilter: String, CaseIterable {
    case all
    case strong
    case fading
    case new
}

/// 词汇 tab 主页 = 场景词汇小课堂：
/// 居中大标题 + 右上角「我的词汇」入口（统计/词表/练习都在那个页面里），
/// 内容为 今日新场景 + 国家 chips + 分类课堂网格。
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

                // 全局今日课置顶卡（跨国家）：今日课国家每天轮换，只靠分类网格
                // 展示的话，选中国家对不上就完全看不到 —— 免费用户唯一的当日免费
                // 内容必须一进来就可见。
                if let today = lessonStore.todayCard {
                    TodayLessonCard(item: today.item, country: today.country) {
                        open(today.item, country: today.country)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }

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
        .onAppear {
            lessonStore.loadIfNeeded()
            lessonStore.loadTodayIfNeeded()
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
                isFree: { !subscriptionManager.isProUser && lessonStore.isFreeSample($0.id) },
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
                            free: !subscriptionManager.isProUser && lessonStore.isFreeSample(item.id),
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
        return !lessonStore.isFreeSample(item.id)
    }

    /// 打开课堂。country 缺省用当前所选国家；今日全局卡传该课自己的国家。
    private func open(_ item: SceneLessonIndexItem, country: LessonCountry? = nil) {
        if isLocked(item) {
            Analytics.track(.lessonPaywallView, params: [
                "lesson_id": item.id, "country": lessonStore.selectedCountry,
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
