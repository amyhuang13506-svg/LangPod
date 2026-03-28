import SwiftUI

struct AllEpisodesView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AudioPlayer.self) private var audioPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var showPlayer = false

    var body: some View {
        ZStack {
            Color(hex: "F7F8FC").ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color(hex: "94A3B8"))
                    }
                    Text("往期回顾")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(hex: "1E293B"))
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "94A3B8"))
                    TextField("搜索话题...", text: $searchText)
                        .font(.system(size: 15))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: "F1F5F9"), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

                // Episode list grouped by date
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(groupedEpisodes, id: \.0) { dateLabel, episodes in
                            Text(dateLabel)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: "94A3B8"))
                                .padding(.top, 8)

                            ForEach(episodes) { episode in
                                episodeRow(episode)
                            }
                        }

                        if filteredEpisodes.isEmpty {
                            Text("没有找到相关内容")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "94A3B8"))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 40)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
        }
    }

    // MARK: - Data

    private var allEpisodes: [Episode] {
        MockDataLoader.loadAllEpisodes()
    }

    private var filteredEpisodes: [Episode] {
        if searchText.isEmpty { return allEpisodes }
        let query = searchText.lowercased()
        return allEpisodes.filter {
            $0.title.lowercased().contains(query) ||
            $0.vocabulary.contains(where: { $0.word.lowercased().contains(query) })
        }
    }

    private var groupedEpisodes: [(String, [Episode])] {
        let grouped = Dictionary(grouping: filteredEpisodes) { $0.date }
        return grouped.sorted { $0.key > $1.key }.map { date, episodes in
            let label = formatDateLabel(date)
            return (label, episodes)
        }
    }

    private func formatDateLabel(_ dateString: String) -> String {
        let parts = dateString.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return dateString
        }
        return "\(month)月\(day)日"
    }

    // MARK: - Row

    private func episodeRow(_ episode: Episode) -> some View {
        Button {
            audioPlayer.playEpisode(episode)
            showPlayer = true
        } label: {
            HStack(spacing: 14) {
                EpisodeThumbnail(episode: episode, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "1E293B"))
                    HStack(spacing: 6) {
                        Text(episode.podcastLevel?.tabName ?? "")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(levelColor(episode.level))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(levelBgColor(episode.level), in: RoundedRectangle(cornerRadius: 4))
                        Text("\(episode.durationSeconds / 60) 分钟 · \(episode.vocabulary.count) 个生词")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "94A3B8"))
                    }
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "3B82F6"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func levelColor(_ level: String) -> Color {
        switch level {
        case "easy": Color(hex: "22C55E")
        case "medium": Color(hex: "3B82F6")
        case "hard": Color(hex: "F97316")
        default: Color(hex: "94A3B8")
        }
    }

    private func levelBgColor(_ level: String) -> Color {
        switch level {
        case "easy": Color(hex: "DCFCE7")
        case "medium": Color(hex: "EFF6FF")
        case "hard": Color(hex: "FEF3C7")
        default: Color(hex: "F1F5F9")
        }
    }
}

#Preview {
    AllEpisodesView()
        .environment(DataStore())
        .environment(AudioPlayer())
}
