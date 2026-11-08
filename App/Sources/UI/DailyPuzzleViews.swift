import Match3Core
import SwiftUI

/// Parent gates insertion with DailyPuzzleFeature.isEnabled(). This accessory
/// does not own navigation, the game engine, or campaign progress.
struct DailyPuzzleMenuCard: View {
    @ObservedObject var model: DailyPuzzleModel
    let start: (GameConfiguration) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var launchFailed = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 10) {
                Label("Daily Puzzle", systemImage: "calendar")
                    .font(.headline)
                Text("\(model.menuChallenge.id.date) UTC • v\(model.menuChallenge.id.version)")
                    .font(.subheadline)
                Text("Score \(model.menuChallenge.level.objectives[0].target) in \(model.menuChallenge.level.moves) moves")
                if let score = model.currentRecord?.bestCompletedScore,
                   let moves = model.currentRecord?.movesUsed {
                    Text("Best completed: \(score) • \(moves) moves used")
                } else {
                    Text(model.currentRecord == nil ? "No completed result yet" : "Played • not completed yet")
                }
                Text("Resets every day at 00:00 UTC. Fully offline; device date selects the puzzle.")
                    .font(.caption)
                if model.warning != nil {
                    Text("Daily history may not be saved on this device.").font(.caption)
                }
                Button("Play Daily Puzzle") {
                    do { start(try model.captureForLaunch()) }
                    catch { launchFailed = true }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("playDailyButton")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .onChange(of: context.date) { _, _ in model.refreshMenu() }
        }
        .onAppear { model.refreshMenu() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshMenu() }
        }
        .alert("Daily Puzzle unavailable", isPresented: $launchFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Check your device date and try again.")
        }
    }
}

/// Append to a settled final-result overlay (not the goalReached choice).
/// Retry receives the captured configuration even if today's date has changed.
struct DailyPuzzleResultActions: View {
    let result: DailyShareResult
    let retry: (GameConfiguration) -> Void
    let levelSelect: () -> Void
    var saveWarning: DailyStoreWarning? = nil
    var showsSummary = true

    var body: some View {
        VStack(spacing: 12) {
            Text("Daily Puzzle • \(result.challenge.id.date) UTC • v\(result.challenge.id.version)")
                .font(.subheadline)
            if showsSummary {
                Text(result.completed ? "Daily goal complete!" : "Daily goal not completed")
                Text("Score: \(result.score) • Moves used: \(result.movesUsed)")
            }
            if saveWarning != nil {
                Text("Result available here, but daily history may not be saved on this device.")
                    .font(.caption)
            }
            Button("Retry Daily") { retry(.daily(result.challenge)) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("retryDailyButton")
            ShareLink(item: result.text) {
                Label("Share Result", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("shareDailyButton")
            Button("Level Select", action: levelSelect)
                .accessibilityIdentifier("levelSelectButton")
        }
    }
}

/// Parent attaches this at its normal exit control. It must pause/gate board
/// input before presenting; this modifier intentionally knows no engine rules.
struct DailyPuzzleExitConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let leave: () -> Void

    func body(content: Content) -> some View {
        content.alert("Leave this Daily Puzzle?", isPresented: $isPresented) {
            Button("Leave Daily Puzzle", role: .destructive, action: leave)
            Button("Keep Playing", role: .cancel) { }
        } message: {
            Text("Unfinished runs are not saved or resumed. Previously saved completed bests are kept. Retry replays the captured date; a new menu entry uses today's UTC puzzle.")
        }
    }
}
