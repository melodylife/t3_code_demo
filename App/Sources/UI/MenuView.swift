import Match3Core
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var app: AppModel
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    private var nextLevel: Level? {
        app.nextCampaignLevel ?? app.levels.last
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                if let nextLevel {
                    playButton(for: nextLevel)
                }
                levelGrid
                settings
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("🍎🍊🍋")
                .font(.system(size: 46))
            Text("EmojiMatch")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [Theme.accentSecondary, Theme.accent],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
            Text("match three, pop emoji")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private func playButton(for level: Level) -> some View {
        Button {
            app.start(level)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                Text(app.isCompleted(level) ? "Replay Level \(level.id)" : "Play Level \(level.id)")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accentSecondary],
                                         startPoint: .leading,
                                         endPoint: .trailing))
            )
            .foregroundStyle(Color.black.opacity(0.82))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("continueButton")
    }

    private var levelGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LEVELS")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(app.levels) { level in
                    LevelTile(level: level)
                }
            }
        }
    }

    private var settings: some View {
        VStack(spacing: 4) {
            Toggle(isOn: $soundEnabled) {
                Label("Sound", systemImage: "speaker.wave.2.fill")
                    .font(.subheadline.weight(.medium))
            }
            Divider().overlay(Theme.cardStroke)
            Toggle(isOn: $hapticsEnabled) {
                Label("Haptics", systemImage: "hand.tap.fill")
                    .font(.subheadline.weight(.medium))
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(CardBackground(cornerRadius: 16))
    }
}

private struct LevelTile: View {
    @EnvironmentObject private var app: AppModel
    let level: Level

    private var unlocked: Bool { app.isUnlocked(level) }
    private var stars: Int { app.stars(for: level) }

    var body: some View {
        Button {
            guard unlocked else { return }
            app.start(level)
        } label: {
            VStack(spacing: 5) {
                Group {
                    if unlocked {
                        Text("\(level.id)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                    } else {
                        Image(systemName: "lock.fill").font(.system(size: 15, weight: .bold))
                    }
                }
                .frame(height: 24)
                .foregroundStyle(unlocked ? Color.primary : Color.secondary)

                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: index < stars ? "star.fill" : "star")
                            .font(.system(size: 7))
                            .foregroundStyle(index < stars ? Theme.accentSecondary : Color.secondary.opacity(0.5))
                    }
                }
                .overlay(alignment: .trailing) {
                    if app.isCompleted(level) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.accentSecondary)
                            .offset(x: 10)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(CardBackground(cornerRadius: 14))
            .opacity(unlocked ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityIdentifier("level_\(level.id)")
    }
}
