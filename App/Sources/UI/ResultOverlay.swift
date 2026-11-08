import Match3Core
import SwiftUI

struct ResultOverlay: View {
    @ObservedObject var engine: GameEngine
    @EnvironmentObject private var app: AppModel

    private var isChoice: Bool { engine.phase == .goalReached }
    private var won: Bool { engine.phase == .won || isChoice }
    private var stars: Int { won ? engine.earnedStars : 0 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()

            VStack(spacing: 18) {
                Text(title)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(won ? Theme.accentSecondary : Color.primary)
                    .accessibilityIdentifier("resultTitle")

                if isChoice {
                    Text(app.saveWarning == nil
                         ? "Your clear is saved. Finish now or spend the remaining moves improving it."
                         : "Your clear is kept for this session. Finish now or keep improving it; device storage could not be updated.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                } else {
                    Text(won ? "Objective complete" : "Objective incomplete")
                        .font(.subheadline.weight(.semibold))
                }

                VStack(spacing: 6) {
                    Text("EARNED STARS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    starRow
                }

                HStack(spacing: 26) {
                    scoreValue(label: "SCORE", value: engine.score, identifier: "finalScoreValue")
                    scoreValue(label: "BEST CLEARED",
                               value: app.bestScore(for: engine.configuration),
                               identifier: "personalBestValue")
                }

                buttons
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 26)
            .frame(maxWidth: 340)
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

    private var title: String {
        switch engine.phase {
        case .goalReached: "Goal complete!"
        case .won: engine.configuration.mode == .daily ? "Daily Clear" : "Level Clear"
        case .lost: "Out of Moves"
        case .playing, .starChase: ""
        }
    }

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 10) {
            if isChoice {
                overlayButton(title: "Finish", filled: true,
                              identifier: "finishGoalButton") {
                    engine.requestFinish()
                }
                if engine.canChaseStars {
                    overlayButton(title: "Chase Stars", filled: false,
                                  identifier: "chaseStarsButton") {
                        engine.chooseStarChase()
                    }
                }
            } else if let result = engine.dailyShareResult {
                DailyPuzzleResultActions(result: result,
                                         retry: { app.start($0) },
                                         levelSelect: { app.exitGame() },
                                         saveWarning: app.dailyPuzzle?.warning,
                                         showsSummary: false)
            } else {
                if won,
                   let next = app.level(withID: engine.level.id + 1),
                   app.isUnlocked(next) {
                    overlayButton(title: "Next Level", filled: true,
                                  identifier: "nextLevelButton") {
                        app.start(next)
                    }
                }
                overlayButton(title: won ? "Replay" : "Retry",
                              filled: !won,
                              identifier: "replayButton") {
                    app.start(engine.level)
                }
                overlayButton(title: "Level Select", filled: false,
                              identifier: "levelSelectButton") {
                    app.exitGame()
                }
            }
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
        .accessibilityLabel("\(stars) earned stars")
    }

    private func scoreValue(label: String, value: Int, identifier: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .accessibilityIdentifier(identifier)
        }
    }

    private func overlayButton(title: String,
                               filled: Bool,
                               identifier: String,
                               action: @escaping () -> Void) -> some View {
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
        .accessibilityIdentifier(identifier)
    }
}
