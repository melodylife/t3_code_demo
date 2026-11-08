import Combine
import Foundation
import Match3Core

final class GameEngine: ObservableObject, GameSceneDelegate {
    typealias Phase = StarChasePhase

    struct SettledCampaignOutcome: Equatable {
        let level: Level
        let score: Int
        let stars: Int
        let completed: Bool
    }

    struct ClearFeedback: Equatable, Identifiable {
        let id = UUID()
        let points: Int
        let multiplier: Double
        let spawnedSpecial: Bool
    }

    let sessionID = UUID()
    let level: Level
    let scene: GameScene

    @Published private(set) var score = 0
    @Published private(set) var movesLeft: Int
    @Published private(set) var phase: Phase = .playing
    @Published private(set) var isResolving = false
    @Published private(set) var clearFeedback: ClearFeedback?

    var onSettledCampaignOutcome: ((SettledCampaignOutcome) -> Void)?

    private var tracker = ObjectiveTracker()
    private var chaseState = StarChaseState()
    private var feedbackDismissal: DispatchWorkItem?

    /// Campaign-compatible entry point. The seed overload is a small injection
    /// seam for future session configurations without changing campaign seeds.
    convenience init(level: Level) {
        self.init(level: level, seed: level.seed)
    }

    init(level: Level, seed: UInt64) {
        self.level = level
        movesLeft = level.moves

        var generator = SplitMix64(seed: seed)
        let board = BoardGenerator.generate(rows: level.rows,
                                           cols: level.cols,
                                           paletteCount: level.paletteCount,
                                           rng: &generator)
        scene = GameScene(level: level, board: board, rng: generator)
        scene.gameDelegate = self
    }

    deinit {
        feedbackDismissal?.cancel()
    }

    var canAcceptMoves: Bool { phase.canAcceptMoves && !isResolving }
    var showsFinalResult: Bool { phase.showsFinalResult }
    var hasGuaranteedClear: Bool { phase.hasGuaranteedClear }
    var canChaseStars: Bool { phase == .goalReached && movesLeft > 0 && earnedStars < 3 }
    var canFinishChase: Bool { phase == .starChase && !isResolving }

    var earnedStars: Int {
        level.campaignStars(for: score, objectivesCompleted: hasGuaranteedClear)
    }

    var scoreTier: Int { level.stars(for: score) }

    var nextStarThreshold: Int? {
        StarRating.nextCampaignThreshold(score: score,
                                         thresholds: level.starThresholds,
                                         objectivesCompleted: hasGuaranteedClear)
    }

    var pointsToNextStar: Int? {
        nextStarThreshold.map { max(0, $0 - score) }
    }

    func current(for objective: Objective) -> Int {
        tracker.current(for: objective)
    }

    func progress(for objective: Objective) -> Double {
        tracker.progress(for: objective)
    }

    func chooseStarChase() {
        let oldPhase = phase
        phase = chaseState.chooseStarChase(movesLeft: movesLeft, stars: earnedStars)
        scene.inputEnabled = phase.canAcceptMoves
        if phase == .won && oldPhase != .won {
            publishSettledOutcome()
            playWinFeedback()
        }
    }

    func requestFinish() {
        let oldPhase = phase
        phase = chaseState.requestFinish()
        scene.inputEnabled = phase.canAcceptMoves
        if phase == .won && oldPhase != .won {
            publishSettledOutcome()
            playWinFeedback()
        }
    }

    /// Feature 1's scene callback can forward exact resolver metadata here.
    /// Scoring remains exclusively in `sceneDidClear`, preventing double count.
    func receiveClearFeedback(points: Int, multiplier: Double, spawnedSpecial: Bool) {
        guard points > 0, multiplier > 0 else { return }
        feedbackDismissal?.cancel()
        clearFeedback = ClearFeedback(points: points,
                                      multiplier: multiplier,
                                      spawnedSpecial: spawnedSpecial)
        let dismissal = DispatchWorkItem { [weak self] in
            self?.clearFeedback = nil
        }
        feedbackDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: dismissal)
    }

    func resetTransientState() {
        feedbackDismissal?.cancel()
        feedbackDismissal = nil
        clearFeedback = nil
    }

    // MARK: - GameSceneDelegate

    func sceneDidConsumeMove() {
        guard phase.canAcceptMoves else { return }
        chaseState.didBeginMove()
        isResolving = true
        movesLeft = max(0, movesLeft - 1)
    }

    func sceneDidClear(points: Int, kinds: [TileKind], spawnedSpecial: Bool) {
        tracker.apply(points: points, cleared: kinds)
        score = tracker.score
    }

    func sceneDidSettle(board: Board) {
        guard phase.canAcceptMoves else { return }
        let previousPhase = phase
        isResolving = false
        let objectivesSatisfied = tracker.isSatisfied(level.objectives)
        let rating = level.campaignStars(for: score,
                                         objectivesCompleted: objectivesSatisfied || hasGuaranteedClear)
        phase = chaseState.didSettle(objectivesSatisfied: objectivesSatisfied,
                                     movesLeft: movesLeft,
                                     stars: rating)
        scene.inputEnabled = phase.canAcceptMoves

        if phase.hasGuaranteedClear {
            // GoalReached is saved here, before either optional player choice.
            publishSettledOutcome()
        }

        if previousPhase == .playing && phase == .goalReached {
            Haptics.success()
        } else if phase == .won && previousPhase != .won {
            playWinFeedback()
        }
    }

    func sceneRejectedSwap() {}

    private func publishSettledOutcome() {
        onSettledCampaignOutcome?(
            SettledCampaignOutcome(level: level,
                                   score: score,
                                   stars: level.campaignStars(for: score, objectivesCompleted: true),
                                   completed: true)
        )
    }

    private func playWinFeedback() {
        Haptics.success()
        SoundPlayer.shared.play(.win)
    }
}
