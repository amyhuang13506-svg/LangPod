import SwiftUI

/// Top content area of PlayerView when the current PlayItem is a pattern.
/// Intentionally visually distinct from EpisodePlayerContent — beige serif card,
/// not a colorful cover image, to signal "教学" vs "磨耳朵".
struct PatternPlayerContent: View {
    let pattern: Pattern
    let currentTime: Double

    var body: some View {
        VStack(spacing: 18) {
            // Beige template card — the visual anchor of the pattern screen
            templateCard
                .frame(width: 260, height: 260)

            // Translation + scene
            VStack(spacing: 8) {
                Text(pattern.translationZh)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 11))
                    Text(pattern.scene)
                        .font(.system(size: 13))
                }
                .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 24)

            // Section progress dots + current section content
            sectionIndicator
                .padding(.horizontal, 24)
        }
    }

    static func currentLine(in pattern: Pattern, at time: Double) -> PatternScriptLine? {
        pattern.explainerScript.first { line in
            guard let start = line.start, let end = line.end else { return false }
            return time >= start && time <= end
        }
    }

    // MARK: - Template Card

    private var templateCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(cardBackgroundColor)

            VStack(spacing: 10) {
                Spacer()
                Text(pattern.template)
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(white: 0.15))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .lineLimit(4)
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "headphones")
                        .font(.system(size: 11))
                    Text("今日句型讲解")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color(white: 0.35))
                .padding(.bottom, 20)
            }
        }
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
    }

    private var cardBackgroundColor: Color {
        if let hex = pattern.thumbnailColor, let color = Color(hexValue: hex) {
            return color
        }
        return Color(hex: "E8DCC4")
    }

    // MARK: - Section Indicator

    private var currentSection: PatternSection? {
        let line = pattern.explainerScript.first { line in
            guard let start = line.start, let end = line.end else { return false }
            return currentTime >= start && currentTime <= end
        }
        return line?.section
    }

    private var sectionIndicator: some View {
        let sections = pattern.explainerScript.map(\.section)
        let current = currentSection

        return VStack(spacing: 12) {
            // Dots — fixed 10pt so the row never changes height
            HStack(spacing: 8) {
                ForEach(sections, id: \.self) { section in
                    let isActive = section == current
                    Circle()
                        .fill(isActive ? Color.appPrimary : Color.border)
                        .frame(width: 10, height: 10)
                        .scaleEffect(isActive ? 1.0 : 0.7)
                        .animation(.easeInOut(duration: 0.25), value: isActive)
                }
            }

            // Current-section label — always reserves its vertical slot so the
            // progress bar / controls below don't jump when section changes.
            HStack(spacing: 8) {
                if let current {
                    Image(systemName: current.icon)
                        .font(.system(size: 13, weight: .semibold))
                    Text(current.label)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .frame(height: 28)
            .foregroundStyle(Color.appPrimary)
            .padding(.horizontal, current == nil ? 0 : 14)
            .background(
                current == nil ? Color.clear : Color.primaryLight,
                in: Capsule()
            )
            .animation(.easeInOut(duration: 0.2), value: current)
        }
    }
}

/// Subtitle overlay pinned to the bottom of the screen. Shows only the
/// Chinese explanation text (the actual narration the user is hearing);
/// the English sample is intentionally omitted so captions don't drift
/// ahead of / behind the voiceover.
///
/// Placed as an overlay in PlayerView (alignment: .bottom) — never pushes
/// the layout above, so buttons / progress bar positions stay fixed.
struct PatternSubtitleFloat: View {
    let pattern: Pattern
    let currentTime: Double

    private var line: PatternScriptLine? {
        PatternPlayerContent.currentLine(in: pattern, at: currentTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let line {
                // Both Chinese narration and any English examples (drill / examples)
                // render in the SAME font/style — no separate italic English block.
                // This matches how native subtitles look when a narrator quotes an
                // English phrase mid-sentence.
                if !line.textZh.isEmpty {
                    Text(line.textZh)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(5)
                        .truncationMode(.tail)
                }
                if !line.textEn.isEmpty {
                    Text(line.textEn)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.divider.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }
}

// Local Color helper — the existing Color(hex:) in Theme works from a non-prefixed hex,
// but we want to accept a possibly-"#"-prefixed string from JSON without crashing.
private extension Color {
    init?(hexValue: String) {
        var s = hexValue
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255.0,
            green: Double((v >> 8) & 0xFF) / 255.0,
            blue: Double(v & 0xFF) / 255.0
        )
    }
}
