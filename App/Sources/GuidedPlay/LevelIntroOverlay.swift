import Match3Core
import SwiftUI

struct LevelIntroOverlay: View {
    let level: Level
    let onStart: () -> Void
    let onSkipTips: () -> Void

    private var objectiveDescription: String {
        level.objectives.map { objective in
            switch objective.type {
            case .collect:
                return "Collect \(objective.target) \(level.palette[safe: objective.tileKind ?? 0] ?? "fruit")"
            case .score:
                return "Score \(objective.target) points"
            }
        }.joined(separator: " and ")
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            ViewThatFits(in: .vertical) {
                card
                ScrollView { card }
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 24).fill(Theme.backgroundTop))
            .padding(24)
        }
        .accessibilityAddTraits(.isModal)
    }

    private var card: some View {
        VStack(spacing: 18) {
            Text(level.id == 0 ? "DAILY GOAL" : "LEVEL \(level.id) GOAL")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accentSecondary)
            Text(objectiveDescription)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Label("Swipe a tile toward a neighbor, or tap two neighboring tiles in sequence.", systemImage: "hand.draw")
                .font(.body)
            Text("Complete every goal within \(level.moves) moves. Invalid swaps do not use a move.")
                .font(.body)
                .foregroundStyle(.secondary)
            Button("Start", action: onStart)
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .accessibilityIdentifier("startLevelButton")
            Button("Skip Tips", action: onSkipTips)
                .font(.subheadline)
                .accessibilityIdentifier("skipTipsButton")
        }
    }
}
