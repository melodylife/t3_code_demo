import Match3Core
import SwiftUI

struct ResultOverlay: View {
    @ObservedObject var engine: GameEngine
    @EnvironmentObject private var app: AppModel

    private var won: Bool { engine.phase == .won }
    private var stars: Int { engine.level.stars(for: engine.score) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()

            VStack(spacing: 18) {
                Text(won ? "Level Clear" : "Out of Moves")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(won ? Theme.accentSecondary : Color.primary)
                    .accessibilityIdentifier("resultTitle")

                starRow

                VStack(spacing: 2) {
                    Text("SCORE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(engine.score)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .accessibilityIdentifier("finalScoreValue")
                }

                VStack(spacing: 10) {
                    if won, let next = app.level(withID: engine.level.id + 1) {
                        overlayButton(title: "Next Level", filled: true) {
                            app.start(next)
                        }
                    }
                    overlayButton(title: won ? "Replay" : "Retry", filled: !won) {
                        app.start(engine.level)
                    }
                    overlayButton(title: "Level Select", filled: false) {
                        app.exitGame()
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 26)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Theme.backgroundTop)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Theme.cardStroke, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 28)
        }
    }

    private var starRow: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < stars ? "star.fill" : "star")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(index < stars ? Theme.accentSecondary : Color.secondary.opacity(0.45))
                    .scaleEffect(won && index < stars ? 1.0 : 0.85)
            }
        }
    }

    private func overlayButton(title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(filled
                              ? AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.accentSecondary],
                                                             startPoint: .leading,
                                                             endPoint: .trailing))
                              : AnyShapeStyle(Theme.card))
                )
                .foregroundStyle(filled ? Color.black.opacity(0.82) : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
