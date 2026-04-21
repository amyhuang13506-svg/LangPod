import SwiftUI

struct SubtitleOverlay: View {
    let script: [ScriptLine]
    let currentTime: Double
    let phase: PlaybackPhase
    let showTranslation: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if let line = currentLine {
                VStack(spacing: 8) {
                    // Speaker name
                    Text(line.speaker)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.appPrimary)

                    // English text — cap at 3 lines so it doesn't dominate the card
                    Text(line.text)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .truncationMode(.tail)

                    // Chinese translation (only during translation round or if toggled)
                    // — cap at 2 lines. Combined with EN: ≤ 5 lines total.
                    if showTranslation || phase == .translationRound {
                        Text(line.translationZh)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer().frame(height: 24)
        }
        .animation(.easeInOut(duration: 0.3), value: currentLine?.start)
    }

    private var currentLine: ScriptLine? {
        script.last { ($0.start ?? 0) <= currentTime && currentTime <= ($0.end ?? .infinity) }
    }
}
