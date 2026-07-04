import SwiftUI

/// 词汇小课堂共用组件：国家 chips / 今日新场景大卡 / 课堂封面卡。
/// 主页面在 VocabularyView，详情在 LessonDetailView。

// MARK: - 国家 chips（平级分类，随时切换）

struct CountryChipsRow: View {
    @Environment(LessonStore.self) private var lessonStore

    var body: some View {
        // 单行横滑 chips（不带国旗）
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(lessonStore.countries) { country in
                    let selected = country.id == lessonStore.selectedCountry
                    Button {
                        guard !selected else { return }
                        lessonStore.selectedCountry = country.id
                        Analytics.track(.lessonCountrySwitch, params: ["country": country.id])
                    } label: {
                        Text(country.nameZh)
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
}

// MARK: - 今日新场景大卡

struct TodayLessonCard: View {
    let item: SceneLessonIndexItem
    let country: LessonCountry
    var locked: Bool = false
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
                    Text("\(item.wordCount) 词 · \(item.zoneCount) 个场景\(locked ? " · Pro" : "")")
                        .font(.system(size: 12))
                        .foregroundColor(Color.textSecondary)
                }
                Spacer()
                Image(systemName: locked ? "lock.fill" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(locked ? Color.warning : Color.textQuaternary)
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
    /// 是否免费样本（闸门收紧后不再读 item.isFree，由调用方按「第一国第一课」判定）
    var free: Bool = false
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
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.titleZh)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(item.wordCount) 词\(free ? " · 免费" : "")")
                        .font(.system(size: 11))
                        .foregroundColor(free ? Color.success : Color.textTertiary)
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
