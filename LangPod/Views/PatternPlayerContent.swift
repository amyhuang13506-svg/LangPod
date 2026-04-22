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
        // Frosted card matching the podcast SubtitleOverlay. Single Text renders
        // both narration (ZH) and embedded example (EN) so lineLimit(5) applies
        // to the COMBINED content — long English drill lines can flex past 2
        // lines without the ZH being forced to 3. Styling rules:
        //   • Pure ZH or pure EN  → 16pt primary (consistent hierarchy)
        //   • ZH + EN together    → ZH 16pt primary, EN 14pt secondary quote
        if let line {
            combinedText(for: line)
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .truncationMode(.tail)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func combinedText(for line: PatternScriptLine) -> Text {
        let zh = line.textZh
        let en = line.textEn
        let primary: (String) -> Text = { s in
            Text(s)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color.textPrimary)
        }
        if zh.isEmpty { return primary(en) }
        if en.isEmpty { return primary(zh) }
        let secondaryEn = Text(en)
            .font(.system(size: 14))
            .foregroundColor(Color.textSecondary)
        return primary(zh) + Text("\n") + secondaryEn
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
