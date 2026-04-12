import SwiftUI

struct EpisodeThumbnail: View {
    let episode: Episode
    var size: CGFloat = 44

    var body: some View {
        if let thumbnail = episode.thumbnail {
            if thumbnail.hasPrefix("bundle://") {
                // Local bundle image
                let name = String(thumbnail.dropFirst("bundle://".count))
                if let uiImage = UIImage(named: name) ?? loadBundleImage(name) {
                    Image(uiImage: uiImage)
                        .resizable().scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: size > 60 ? 20 : 10))
                } else {
                    fallbackView
                }
            } else {
                // Remote thumbnail with persistent cache
                CachedAsyncImage(url: thumbnail) {
                    fallbackView
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size > 60 ? 20 : 10))
            }
        } else {
            fallbackView
        }
    }

    private func loadBundleImage(_ name: String) -> UIImage? {
        for ext in ["jpg", "png", "webp", "jpeg"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                if let data = try? Data(contentsOf: url) {
                    return UIImage(data: data)
                }
            }
        }
        return nil
    }

    // Color-coded placeholder based on topic keywords
    private var fallbackView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size > 60 ? 20 : 10)
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            Image(systemName: topicIcon)
                .font(.system(size: size * 0.35))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var gradientColors: [Color] {
        let title = episode.title.lowercased()
        if title.contains("coffee") || title.contains("food") || title.contains("milk") || title.contains("order") {
            return [Color.warning, Color(hex: "D97706")]
        } else if title.contains("ai") || title.contains("tech") || title.contains("regulation") {
            return [Color(hex: "6366F1"), Color(hex: "4F46E5")]
        } else if title.contains("travel") || title.contains("weather") || title.contains("nature") {
            return [Color.success, Color(hex: "16A34A")]
        } else if title.contains("health") || title.contains("sport") || title.contains("fitness") {
            return [Color.danger, Color(hex: "DC2626")]
        } else if title.contains("work") || title.contains("business") || title.contains("economy") {
            return [Color.appPrimary, Color(hex: "2563EB")]
        } else if title.contains("store") || title.contains("shop") || title.contains("buy") {
            return [Color(hex: "EC4899"), Color(hex: "DB2777")]
        } else if title.contains("housing") || title.contains("home") || title.contains("city") {
            return [Color(hex: "8B5CF6"), Color(hex: "7C3AED")]
        } else {
            // Default based on level
            switch episode.level {
            case "easy": return [Color(hex: "34D399"), Color(hex: "10B981")]
            case "medium": return [Color(hex: "60A5FA"), Color.appPrimary]
            case "hard": return [Color.hardOrange, Color(hex: "EA580C")]
            default: return [Color.textTertiary, Color.textSecondary]
            }
        }
    }

    private var topicIcon: String {
        let title = episode.title.lowercased()
        if title.contains("coffee") || title.contains("order") { return "cup.and.saucer.fill" }
        if title.contains("food") || title.contains("milk") { return "fork.knife" }
        if title.contains("ai") || title.contains("tech") { return "brain.head.profile" }
        if title.contains("regulation") || title.contains("law") { return "building.columns.fill" }
        if title.contains("weather") { return "cloud.sun.fill" }
        if title.contains("travel") { return "airplane" }
        if title.contains("store") || title.contains("shop") { return "bag.fill" }
        if title.contains("health") { return "heart.fill" }
        if title.contains("work") || title.contains("business") { return "briefcase.fill" }
        if title.contains("housing") || title.contains("home") { return "house.fill" }
        if title.contains("music") { return "music.note" }
        return "headphones"
    }
}
