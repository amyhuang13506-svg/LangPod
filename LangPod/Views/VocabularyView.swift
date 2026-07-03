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

    @State private var lessonStore = LessonStore()
    @State private var selectedLesson: SceneLessonIndexItem?
    @State private var showPaywall = false
    @State private var showMyVocabulary = false

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

                CountryChipsRow()
                    .environment(lessonStore)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        if let today = lessonStore.todayLesson {
                            TodayLessonCard(item: today, country: lessonStore.currentCountry) {
                                open(today)
                            }
                        }

                        ForEach(lessonStore.byCategory, id: \.category) { group in
                            categorySection(group.category, lessons: group.lessons)
                        }

                        if !lessonStore.pastDailyLessons.isEmpty {
                            categorySection("📅 往期每日场景", lessons: lessonStore.pastDailyLessons)
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
        .onAppear { lessonStore.loadIfNeeded() }
        .fullScreenCover(item: $selectedLesson) { item in
            LessonDetailView(item: item, country: lessonStore.currentCountry)
                .environment(store)
                .environment(lessonStore)
        }
        .fullScreenCover(isPresented: $showMyVocabulary) {
            MyVocabularyView()
                .environment(store)
                .environment(audioPlayer)
                .environment(subscriptionManager)
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
                    HStack(spacing: 5) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 12))
                        Text("我的词汇")
                            .font(.system(size: 13, weight: .semibold))
                        if store.totalCount > 0 {
                            Text("\(store.totalCount)")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .foregroundStyle(Color.appPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.primaryLight, in: Capsule())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Lessons

    private func categorySection(_ title: String, lessons: [SceneLessonIndexItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Color.textPrimary)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(lessons) { item in
                    LessonCoverCard(
                        item: item,
                        locked: isLocked(item),
                        completed: lessonStore.isCompleted(item.id),
                        onTap: { open(item) },
                        width: nil
                    )
                    .frame(maxWidth: .infinity)
                }
            }
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
        !LessonAccessGate.canAccess(
            isFree: item.isFree, isDaily: item.isDaily, date: item.date,
            isPro: subscriptionManager.isProUser
        )
    }

    private func open(_ item: SceneLessonIndexItem) {
        if isLocked(item) {
            Analytics.track(.lessonPaywallView, params: [
                "lesson_id": item.id, "country": lessonStore.selectedCountry,
            ])
            showPaywall = true
        } else {
            selectedLesson = item
        }
    }
}

#Preview {
    VocabularyView()
        .environment(VocabularyStore())
        .environment(AudioPlayer())
        .environment(SubscriptionManager())
}
