import SwiftUI

/// 词汇小课堂全部课堂页：吸顶国家 chips + 今日置顶 + 分类分组 2 列网格 + 往期每日场景。
struct LessonLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LessonStore.self) private var lessonStore
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(VocabularyStore.self) private var vocabularyStore

    @State private var selectedLesson: SceneLessonIndexItem?
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
                CountryChipsRow()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)

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
                    .padding(.bottom, 40)
                }
            }
        }
        .fullScreenCover(item: $selectedLesson) { item in
            LessonDetailView(item: item, country: lessonStore.currentCountry)
                .environment(vocabularyStore)
                .environment(lessonStore)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(subscriptionManager)
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white))
            }
            Spacer()
            Text("词汇小课堂")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Color.textPrimary)
            Spacer()
            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

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
