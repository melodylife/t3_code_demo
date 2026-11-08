import Match3Core
import SwiftUI

struct GameScreen: View {
    @ObservedObject var engine: GameEngine
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(spacing: 10) {
            HUDView(engine: engine)
            Spacer(minLength: 8)
            SpriteBoardView(scene: engine.scene)
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 8)
            Spacer(minLength: 8)
        }
        .padding(.top, 6)
        .onChange(of: engine.phase) { _, phase in
            guard phase == .won else { return }
            app.recordResult(level: engine.level,
                             score: engine.score,
                             stars: engine.level.stars(for: engine.score))
        }
        .overlay {
            if engine.phase != .playing {
                ResultOverlay(engine: engine)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: engine.phase)
    }
}

struct HUDView: View {
    @ObservedObject var engine: GameEngine
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    app.exitGame()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.card))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 1) {
                    Text("LEVEL \(engine.level.id)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(engine.score)")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .accessibilityIdentifier("scoreValue")
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("MOVES")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(engine.movesLeft)")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(engine.movesLeft <= 3 ? Theme.accent : Color.primary)
                        .accessibilityIdentifier("movesValue")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.card))
            }
            .padding(.horizontal, 16)

            objectives
        }
    }

    private var objectives: some View {
        HStack(spacing: 8) {
            ForEach(Array(engine.level.objectives.enumerated()), id: \.offset) { _, objective in
                ObjectiveChip(engine: engine, objective: objective)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
}

private struct ObjectiveChip: View {
    @ObservedObject var engine: GameEngine
    let objective: Objective

    private var icon: String {
        switch objective.type {
        case .score:
            return "⭐️"
        case .collect:
            return engine.level.palette[safe: objective.tileKind ?? 0] ?? "🎯"
        }
    }

    var body: some View {
        let current = engine.current(for: objective)
        let fraction = engine.progress(for: objective)
        HStack(spacing: 7) {
            Text(icon).font(.system(size: 16))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(current)/\(objective.target)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                ProgressView(value: fraction)
                    .tint(Theme.accentSecondary)
                    .frame(width: 64)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(CardBackground(cornerRadius: 12))
    }
}
