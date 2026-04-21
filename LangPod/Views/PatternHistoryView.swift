import SwiftUI

/// Browse all past patterns, grouped by episode date (descending).
/// Historical patterns (parent episode date < today) are locked for free users.
struct PatternHistoryView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AudioPlayer.self) private var audioPlayer
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var showPlayer = false
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(groupedByDate, id: \.date) { group in
                            section(for: group)
                        }

                        if groupedByDate.isEmpty {
                            emptyState
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 60)
                }
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(subscriptionManager)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.divider, in: Circle())
            }
            Spacer()
            Text("往期句型回顾")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            playAllButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    /// Play all Pro-accessible patterns in chronological order (oldest first).
    /// Free users only get today's patterns. Button is hidden when there's nothing to play.
    private var playAllButton: some View {
        let accessible = collectAccessiblePatterns()
        return Button {
            guard let first = accessible.first,
                  case .pattern(let pattern, let parent) = first else {
                showPaywall = true
                return
            }
            audioPlayer.playPattern(pattern, parentEpisode: parent, in: accessible)
            showPlayer = true
            Analytics.track(.patternOpen, params: [
                "pattern_id": pattern.id,
                "episode_id": parent.id,
                "source": "history_play_all",
            ])
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    accessible.isEmpty ? Color.textTertiary : Color.appPrimary,
                    in: Circle()
                )
        }
        .disabled(accessible.isEmpty)
    }

    private func collectAccessiblePatterns() -> [PlayItem] {
        var items: [PlayItem] = []
        for group in groupedByDate.reversed() {
            let locked = !PatternAccessGate.isToday(group.date) && !subscriptionManager.isProUser
            if locked { continue }
            for pair in group.items {
                items.append(.pattern(pair.pattern, parentEpisode: pair.parent))
            }
        }
        return items
    }

    // MARK: - Grouping

    private struct PatternGroup {
        let date: String                // episode date "2026-04-19"
        let dateDisplay: String         // "4月19日"
        let items: [(pattern: Pattern, parent: Episode)]
    }

    private var groupedByDate: [PatternGroup] {
        // Collect all (pattern, parent) pairs, group by parent.date, sort dates desc
        var byDate: [String: [(Pattern, Episode)]] = [:]
        for ep in dataStore.episodes {
            guard let patterns = ep.patterns, !patterns.isEmpty else { continue }
            byDate[ep.date, default: []].append(contentsOf: patterns.map { ($0, ep) })
        }
        let sorted = byDate.keys.sorted(by: >)  // newest first
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return sorted.map { date in
            let items = byDate[date] ?? []
            let display: String = {
                if let d = DateFormatter.episodeDate.date(from: date) {
                    return formatter.string(from: d)
                }
                return date
            }()
            return PatternGroup(date: date, dateDisplay: display, items: items)
        }
    }

    // MARK: - Section

    @ViewBuilder
    private func section(for group: PatternGroup) -> some View {
        let locked = !PatternAccessGate.isToday(group.date) && !subscriptionManager.isProUser

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(group.dateDisplay)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                if PatternAccessGate.isToday(group.date) {
                    Text("今日")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.warning)
                }
            }

            ForEach(group.items, id: \.pattern.id) { item in
                patternRow(pattern: item.pattern, parent: item.parent, locked: locked)
            }
        }
    }

    // MARK: - Row

    private func patternRow(pattern: Pattern, parent: Episode, locked: Bool) -> some View {
        Button {
            if locked {
                Analytics.track(.patternPaywallView, params: [
                    "pattern_id": pattern.id,
                    "parent_episode_date": parent.date,
                ])
                showPaywall = true
            } else {
                // Queue: every accessible pattern in history order starting from this one
                let items = allAccessibleItems(startFrom: pattern)
                audioPlayer.playPattern(pattern, parentEpisode: parent, in: items)
                showPlayer = true
                Analytics.track(.patternOpen, params: [
                    "pattern_id": pattern.id,
                    "episode_id": parent.id,
                    "source": "history",
                ])
            }
        } label: {
            HStack(spacing: 12) {
                // Colored swatch (card background preview)
                RoundedRectangle(cornerRadius: 10)
                    .fill(cardColor(pattern: pattern))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "quote.bubble.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(white: 0.35))
                    )
                    .opacity(locked ? 0.5 : 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(pattern.template)
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(pattern.scene)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                        Text(pattern.durationDisplay)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Spacer()

                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.warning)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.appPrimary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 36))
                .foregroundStyle(Color.textTertiary)
            Text("暂无往期句型")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            Text("随着每日播客更新，句型讲解会陆续积累")
                .font(.system(size: 12))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Helpers

    /// Build a PlayItem queue of all Pro-accessible patterns in history order,
    /// starting from the given pattern. For free users this is just today's patterns.
    private func allAccessibleItems(startFrom startingPattern: Pattern) -> [PlayItem] {
        var all: [PlayItem] = []
        for group in groupedByDate.reversed() {  // oldest first for sequential play
            let parentLocked = !PatternAccessGate.isToday(group.date) && !subscriptionManager.isProUser
            if parentLocked { continue }
            for item in group.items {
                all.append(.pattern(item.pattern, parentEpisode: item.parent))
            }
        }
        // Rotate so the chosen pattern is first
        if let idx = all.firstIndex(where: {
            if case .pattern(let p, _) = $0 { return p.id == startingPattern.id }
            return false
        }) {
            return Array(all[idx...]) + Array(all[..<idx])
        }
        return all
    }

    private func cardColor(pattern: Pattern) -> Color {
        if let hex = pattern.thumbnailColor, let c = colorFromHex(hex) {
            return c
        }
        return colorFromHex("#E8DCC4") ?? Color.warningLight
    }

    private func colorFromHex(_ hex: String) -> Color? {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        return Color(
            red: Double((v >> 16) & 0xFF) / 255.0,
            green: Double((v >> 8) & 0xFF) / 255.0,
            blue: Double(v & 0xFF) / 255.0
        )
    }
}

#Preview {
    PatternHistoryView()
        .environment(DataStore())
        .environment(AudioPlayer())
        .environment(SubscriptionManager())
}
