import SwiftUI

/// 「硅谷原声」全部内容浏览页。从首页「查看更多」进入。
/// - 顶部主题筛选 chips（横滑）
/// - 主区按日期分组的卡片列表（每行大缩略图 + 标题 + 演讲者 + 时长）
/// - 点击进入播放页（同首页）
struct RawPodcastFeedView: View {
    let podcasts: [RawPodcast]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTopic: String? = nil
    @State private var selectedPodcast: RawPodcast?
    @State private var searchText: String = ""

    private var topics: [String] {
        var set = Set<String>()
        for p in podcasts {
            // 主题字段可能含「· 分隔」，拆开成更细粒度
            for piece in p.topic.split(separator: "·").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                if !piece.isEmpty { set.insert(piece) }
            }
        }
        return ["全部"] + set.sorted()
    }

    private var filtered: [RawPodcast] {
        var list = podcasts
        if let topic = selectedTopic, topic != "全部" {
            list = list.filter { $0.topic.contains(topic) }
        }
        if !searchText.isEmpty {
            // BilingualSearch 中英双向匹配
            list = list.filter { p in
                let combined = "\(p.title) \(p.speaker) \(p.event) \(p.topic)"
                return BilingualSearch.matches(query: searchText, in: combined)
            }
        }
        return list.sorted { $0.publishedAt > $1.publishedAt }
    }

    /// 按发布日期分组（今天 / 本周 / 更早）
    private var grouped: [(label: String, items: [RawPodcast])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekAgo = cal.date(byAdding: .day, value: -7, to: today) ?? today
        let monthAgo = cal.date(byAdding: .month, value: -1, to: today) ?? today

        var todayItems: [RawPodcast] = []
        var weekItems: [RawPodcast] = []
        var monthItems: [RawPodcast] = []
        var olderItems: [RawPodcast] = []

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        for p in filtered {
            let d = f.date(from: p.publishedAt) ?? Date.distantPast
            if d >= today { todayItems.append(p) }
            else if d >= weekAgo { weekItems.append(p) }
            else if d >= monthAgo { monthItems.append(p) }
            else { olderItems.append(p) }
        }

        var groups: [(String, [RawPodcast])] = []
        if !todayItems.isEmpty { groups.append(("今天", todayItems)) }
        if !weekItems.isEmpty { groups.append(("本周", weekItems)) }
        if !monthItems.isEmpty { groups.append(("本月", monthItems)) }
        if !olderItems.isEmpty { groups.append(("更早", olderItems)) }
        return groups
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // 主题筛选
                        topicFilter
                            .padding(.top, 8)

                        if filtered.isEmpty {
                            emptyState
                        } else {
                            ForEach(grouped, id: \.label) { group in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(group.label)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.textTertiary)
                                        .padding(.horizontal, 16)
                                    ForEach(group.items) { p in
                                        feedRow(p)
                                            .onTapGesture { selectedPodcast = p }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 60)
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索演讲者 / 标题")
            .navigationTitle("硅谷原声")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("硅谷原声")
                            .font(.system(size: 16, weight: .semibold))
                        Text("\(filtered.count) 期")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .fullScreenCover(item: $selectedPodcast) { podcast in
                RawPodcastPlayerView(podcast: podcast)
            }
        }
    }

    private var topicFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(topics, id: \.self) { topic in
                    let isSelected = (selectedTopic ?? "全部") == topic
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            selectedTopic = (topic == "全部") ? nil : topic
                        }
                    } label: {
                        Text(topic)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isSelected ? .white : Color.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? Color.appPrimary : Color.divider,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func feedRow(_ p: RawPodcast) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 16:9 缩略图
            ZStack(alignment: .bottomTrailing) {
                if let thumb = p.displayThumbnailUrl {
                    CachedAsyncImage(url: thumb) {
                        Rectangle().fill(coverColor(p))
                    }
                    .scaledToFill()
                    .frame(width: 140, height: 79)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Rectangle()
                        .fill(coverColor(p))
                        .frame(width: 140, height: 79)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                // 时长徽章
                Text(p.durationDisplay)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                    .padding(5)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(p.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text(p.speaker)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                    Text("·")
                        .foregroundStyle(Color.textTertiary)
                    Text(p.dateDisplay)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }
                if !p.topic.isEmpty {
                    Text(p.topic)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.appPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primaryLight, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(Color.textTertiary)
            Text("没有匹配的内容")
                .font(.system(size: 14))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func coverColor(_ p: RawPodcast) -> Color {
        if let hex = p.thumbnailColor {
            var s = hex
            if s.hasPrefix("#") { s.removeFirst() }
            if s.count == 6, let v = UInt64(s, radix: 16) {
                return Color(
                    red: Double((v >> 16) & 0xFF) / 255.0,
                    green: Double((v >> 8) & 0xFF) / 255.0,
                    blue: Double(v & 0xFF) / 255.0
                )
            }
        }
        return Color(hex: "1A2540")
    }
}
