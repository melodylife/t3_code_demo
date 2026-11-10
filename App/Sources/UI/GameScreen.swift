import Match3Core
import SwiftUI

struct GameScreen: View {
    @ObservedObject var engine: GameEngine
    @EnvironmentObject private var app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDailyExit = false
    @StateObject private var learning: GuidedPlayCoordinator

    init(engine: GameEngine) {
        self.engine = engine
        _learning = StateObject(wrappedValue: GuidedPlayCoordinator(scene: engine.scene) {
            engine.phase.canAcceptMoves && !engine.isResolving && !engine.inputBlocked
        })
    }

    var body: some View {
        VStack(spacing: 10) {
            HUDView(engine: engine, exit: requestExit, restart: restart,
                    requestHint: { learning.requestHint(unmetKinds: engine.unmetCollectionKinds) },
                    openHelp: { learning.openHowToPlay() },
                    learningBlocksInput: learning.blocksInput)
            Spacer(minLength: 8)
            SpriteBoardView(scene: engine.scene)
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 8)
            Spacer(minLength: 8)
        }
        .padding(.top, 6)
        .accessibilityHidden(learning.blocksInput || showingDailyExit
                             || engine.phase == .goalReached || engine.showsFinalResult)
        .modifier(DailyPuzzleExitConfirmation(isPresented: $showingDailyExit,
                                              leave: { app.exitGame() }))
        .onChange(of: showingDailyExit) { _, shown in
            engine.setInputBlocked(shown)
        }
        .overlay {
            if engine.phase == .goalReached || engine.showsFinalResult {
                ResultOverlay(engine: engine)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let feedback = engine.clearFeedback, engine.phase.canAcceptMoves, !learning.blocksInput {
                    ClearFeedbackView(feedback: feedback)
                        .transition(.scale.combined(with: .opacity))
                }
                if let warning = app.saveWarning {
                    SaveWarningView(message: warning) {
                        app.saveWarning = nil
                    }
                }
            }
            .padding(.top, 92)
        }
        .overlay(alignment: .bottom) {
            if let hint = learning.activeHint, !learning.blocksInput, engine.phase.canAcceptMoves {
                HintBannerView(hint: hint, palette: engine.level.palette) { learning.dismissHint() }
                    .padding(.bottom, 12)
            }
        }
        .overlay {
            if learning.showsLevelIntro {
                LevelIntroOverlay(level: engine.level,
                                  onStart: { learning.dismissLevelIntro() },
                                  onSkipTips: { learning.dismissLevelIntro(skipTips: true) })
            } else if let special = learning.activeSpecialIntro {
                SpecialIntroOverlay(type: special) { learning.dismissSpecialIntro() }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { learning.showsPractice }, set: { shown in
            if !shown { learning.closePractice() }
        })) {
            GuidedPracticeView(store: learning.store) { learning.closePractice() }
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: Binding(get: { learning.showsHowToPlay }, set: { shown in
            if !shown { learning.closeHowToPlay() }
        })) {
            HowToPlayView()
        }
        .onAppear { engine.scene.reduceMotionOverride = reduceMotion }
        .onChange(of: reduceMotion) { _, value in
            engine.scene.reduceMotionOverride = value
            learning.dismissHint()
        }
        .onChange(of: engine.phase) { _, _ in learning.refreshPresentation() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: engine.phase)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: engine.clearFeedback?.id)
    }

    private func requestExit() {
        guard !engine.isResolving else { return }
        if engine.configuration.mode == .daily && !engine.showsFinalResult {
            engine.setInputBlocked(true)
            showingDailyExit = true
        } else {
            app.exitGame()
        }
    }

    private func restart() {
        guard !engine.isResolving else { return }
        app.start(engine.configuration)
    }
}

struct HUDView: View {
    @ObservedObject var engine: GameEngine
    let exit: () -> Void
    let restart: () -> Void
    let requestHint: () -> Void
    let openHelp: () -> Void
    let learningBlocksInput: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button(action: exit) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.card))
                }
                .buttonStyle(.plain)
                .disabled(engine.isResolving)
                .accessibilityLabel("Back to level select")
                .accessibilityIdentifier("exitGameButton")

                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.configuration.mode == .daily ? "DAILY PUZZLE" : "LEVEL \(engine.level.id)")
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
            starProgress
            HStack {
                Button(action: { engine.undoLastMove() }) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!engine.canUndo)
                .accessibilityLabel("Undo last move")
                .accessibilityIdentifier("undoButton")
                Button(action: requestHint) { Label("Hint", systemImage: "lightbulb") }
                    .disabled(!engine.canAcceptMoves || learningBlocksInput)
                    .accessibilityIdentifier("hintButton")
                Spacer()
                Button(action: restart) { Label("Restart", systemImage: "arrow.counterclockwise") }
                    .disabled(engine.isResolving)
                    .accessibilityIdentifier("restartButton")
                Spacer()
                Button(action: openHelp) { Label("How to Play", systemImage: "questionmark.circle") }
                    .disabled(!engine.canAcceptMoves || learningBlocksInput)
                    .accessibilityIdentifier("gameHelpButton")
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .padding(.horizontal, 16)
        }
    }

    private var starProgress: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundStyle(Theme.accentSecondary)
            if let threshold = engine.nextStarThreshold,
               let remaining = engine.pointsToNextStar {
                Text("Next star: \(threshold) · \(remaining) points")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            } else {
                Text(engine.hasGuaranteedClear ? "All stars earned" : "Top score tier reached")
                    .font(.caption.weight(.semibold))
            }
            Spacer(minLength: 4)
            if engine.phase == .starChase {
                Button("Finish") {
                    engine.requestFinish()
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!engine.canFinishChase)
                .accessibilityIdentifier("finishChaseButton")
            }
        }
        .padding(.horizontal, 16)
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

private struct ClearFeedbackView: View {
    let feedback: GameEngine.ClearFeedback

    var body: some View {
        Text("+\(feedback.points)  ×\(String(format: "%g", feedback.multiplier))\(feedback.spawnedSpecial ? "  ✨" : "")")
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.card))
            .accessibilityLabel("\(feedback.points) points, multiplier \(feedback.multiplier)")
    }
}

private struct SaveWarningView: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(.caption)
                .lineLimit(3)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Dismiss save warning")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
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
