import Match3Core
import SwiftUI

struct LevelIntroOverlay: View {
    let level: Level
    let onStart: () -> Void
    let onSkipTips: () -> Void

    init(level: Level, onStart: @escaping () -> Void, onSkipTips: @escaping () -> Void) {
        self.level = level
        self.onStart = onStart
        self.onSkipTips = onSkipTips
    }

    private var objectiveDescription: String {
        var lines: [String] = []
        for obj in level.objectives {
            switch obj.type {
            case .collect:
                let fruit = level.palette[safe: obj.tileKind ?? 0] ?? "Fruit"
                lines.append("Collect \(obj.target) \(fruit)")
            case .score:
                lines.append("Score \(obj.target) points")
            }
        }
        return lines.joined(separator: " and ")
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("LEVEL \(level.id) GOAL")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.yellow)
                        .tracking(1.5)

                    Text(objectiveDescription)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Text("👉")
                            .font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("How to Move")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            Text("Swipe any tile toward an adjacent neighbor, or tap two neighbors one after another.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider().background(Color.white.opacity(0.15))

                    HStack(alignment: .top, spacing: 10) {
                        Text("🎯")
                            .font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Winning Condition")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            Text("Complete the goal before running out of moves (\(level.moves) moves available).")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))

                VStack(spacing: 10) {
                    Button {
                        onStart()
                    } label: {
                        Text("Start")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.yellow))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("startLevelButton")

                    Button {
                        onSkipTips()
                    } label: {
                        Text("Skip Tips")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("skipTipsButton")
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(UIColor.systemGray6).opacity(0.96))
                    .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
            )
            .padding(.horizontal, 28)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Level \(level.id) Goal: \(objectiveDescription)")
    }
}
