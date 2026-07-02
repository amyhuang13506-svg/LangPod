import SwiftUI

/// 词汇页「词汇小课堂」入口区块：
/// 今日新场景大卡（跨国家置顶）→ 国家 chips（平级分类随时切）→ 课堂横滑小卡 → 查看全部
struct SceneLessonSection: View {
    @Environment(LessonStore.self) private var lessonStore
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(VocabularyStore.self) private var vocabularyStore

    @State private var selectedLesson: SceneLessonIndexItem?
    @State private var showLibrary = false
    @State private var showPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("词汇小课堂")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .tracking(-0.3)
                Spacer()
                Button { showLibrary = true } label: {
                    HStack(spacing: 3) {
                        Text("查看全部")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.appPrimary)
                }
            }
            .padding(.horizontal, 20)

            if let today = lessonStore.todayLesson {
                TodayLessonCard(item: today, country: lessonStore.currentCountry) {
                    open(today)
                }
                .padding(.horizontal, 20)
            }

            CountryChipsRow()
                .padding(.horizontal, 20)

            if lessonStore.lessons.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(lessonStore.lessons.filter { !$0.isDaily }) { item in
                            LessonCoverCard(
                                item: item,
                                locked: isLocked(item),
                                completed: lessonStore.isCompleted(item.id)
                            ) {
                                open(item)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .onAppear { lessonStore.loadIfNeeded() }
        .fullScreenCover(item: $selectedLesson) { item in
            LessonDetailView(item: item, country: lessonStore.currentCountry)
                .environment(vocabularyStore)
                .environment(lessonStore)
        }
        .fullScreenCover(isPresented: $showLibrary) {
            LessonLibraryView()
                .environment(lessonStore)
                .environment(subscriptionManager)
                .environment(vocabularyStore)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(subscriptionManager)
        }
    }

    private var emptyState: some View {
        HStack {
            if lessonStore.isLoadingIndex {
                ProgressView().tint(Color.appPrimary)
                Text("加载中…")
                    .font(.system(size: 13))
                    .foregroundColor(Color.textTertiary)
            } else {
                Text("该国家的课堂即将上线")
                    .font(.system(size: 13))
                    .foregroundColor(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
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

// MARK: - 国家 chips（平级分类，随时切换）

struct CountryChipsRow: View {
    @Environment(LessonStore.self) private var lessonStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(lessonStore.countries) { country in
                    let selected = country.id == lessonStore.selectedCountry
                    Button {
                        guard !selected else { return }
                        lessonStore.selectedCountry = country.id
                        Analytics.track(.lessonCountrySwitch, params: ["country": country.id])
                    } label: {
                        Text("\(country.flag) \(country.nameZh)")
                            .font(.system(size: 13, weight: selected ? .semibold : .medium))
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
}

// MARK: - 今日新场景大卡

struct TodayLessonCard: View {
    let item: SceneLessonIndexItem
    let country: LessonCountry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                CachedAsyncImage(url: item.cover) {
                    RoundedRectangle(cornerRadius: 12).fill(Color.primaryLighter)
                }
                .frame(width: 92, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("今日")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.hardOrange))
                        Text(country.flag)
                            .font(.system(size: 12))
                    }
                    Text(item.titleZh)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(item.wordCount) 词 · \(item.zoneCount) 个场景 · 今日免费")
                        .font(.system(size: 12))
                        .foregroundColor(Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.textQuaternary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.hardOrange.opacity(0.35), lineWidth: 1)
            )
        }
    }
}

// MARK: - 课堂封面小卡（入口横滑 + 课堂库网格共用）

struct LessonCoverCard: View {
    let item: SceneLessonIndexItem
    let locked: Bool
    let completed: Bool
    let onTap: () -> Void
    var width: CGFloat? = 158

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    CachedAsyncImage(url: item.cover) {
                        ZStack {
                            Rectangle().fill(Color.primaryLighter)
                            Image(systemName: item.icon.isEmpty ? "book.fill" : item.icon)
                                .font(.system(size: 24))
                                .foregroundColor(Color.appPrimary.opacity(0.5))
                        }
                    }
                    .frame(width: width)
                    .frame(maxWidth: width == nil ? .infinity : nil)
                    .frame(height: 96)
                    .clipped()

                    if locked {
                        badge(icon: "lock.fill", color: .black.opacity(0.55))
                    } else if completed {
                        badge(icon: "checkmark", color: Color.success)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.titleZh)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(item.wordCount) 词\(item.isFree ? " · 免费" : "")")
                        .font(.system(size: 11))
                        .foregroundColor(item.isFree ? Color.success : Color.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(width: width, alignment: .leading)
                .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func badge(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(color))
            .padding(6)
    }
}
