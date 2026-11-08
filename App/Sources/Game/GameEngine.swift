import Combine
import Foundation
import Match3Core

final class GameEngine: ObservableObject, GameSceneDelegate {
    typealias Phase = StarChasePhase

    struct SettledOutcome: Equatable {
        let configuration: GameConfiguration
        let score: Int
        let stars: Int
        let completed: Bool
        let movesUsed: Int
    }

    struct ClearFeedback: Equatable, Identifiable {
        let id = UUID()
        let points: Int
        let multiplier: Double
        let spawnedSpecial: Bool
    }

    let sessionID = UUID()
    let configuration: GameConfiguration
    let level: Level
    let scene: GameScene

    @Published private(set) var score = 0
    @Published private(set) var movesLeft: Int
    @Published private(set) var phase: Phase = .playing
    @Published private(set) var isResolving = false
    @Published private(set) var inputBlocked = false
    @Published private(set) var clearFeedback: ClearFeedback?

    var onSettledOutcome: ((SettledOutcome) -> Void)?

    private var tracker = ObjectiveTracker()
    private var chaseState = StarChaseState()
    private var feedbackDismissal: DispatchWorkItem?

    convenience init(level: Level) {
        self.init(configuration: .campaign(level))
    }

    init(configuration: GameConfiguration) {
        self.configuration = configuration
        let level = configuration.level
        self.level = level
        movesLeft = level.moves

        var generator = SplitMix64(seed: configuration.seed)
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

    var canAcceptMoves: Bool { phase.canAcceptMoves && !isResolving && !inputBlocked }
    var showsFinalResult: Bool { phase.showsFinalResult }
    var hasGuaranteedClear: Bool { phase.hasGuaranteedClear }
    var canChaseStars: Bool { phase == .goalReached && movesLeft > 0 && earnedStars < 3 }
    var canFinishChase: Bool { phase == .starChase && !isResolving }

    var earnedStars: Int {
        level.campaignStars(for: score, objectivesCompleted: hasGuaranteedClear)
    }

    var scoreTier: Int { level.stars(for: score) }

    var dailyShareResult: DailyShareResult? {
        guard let challenge = configuration.dailyChallenge, !isResolving else { return nil }
        return DailyShareResult(challenge: challenge,
                                completed: hasGuaranteedClear,
                                score: score,
                                movesUsed: level.moves - movesLeft)
    }

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
        refreshSceneInput()
        if phase == .won && oldPhase != .won {
            publishSettledOutcome()
            playWinFeedback()
        }
    }

    func requestFinish() {
        let oldPhase = phase
        phase = chaseState.requestFinish()
        refreshSceneInput()
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

    func setInputBlocked(_ blocked: Bool) {
        inputBlocked = blocked
        refreshSceneInput()
    }

    private func refreshSceneInput() {
        scene.inputEnabled = phase.canAcceptMoves && !inputBlocked
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
        refreshSceneInput()

        if phase.hasGuaranteedClear || phase == .lost {
            // Save a guaranteed clear before either optional choice. Failed daily
            // attempts are recorded separately and can never unlock the campaign.
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
        onSettledOutcome?(
            SettledOutcome(configuration: configuration,
                           score: score,
                           stars: earnedStars,
                           completed: hasGuaranteedClear,
                           movesUsed: level.moves - movesLeft)
        )
    }

    private func playWinFeedback() {
        Haptics.success()
        SoundPlayer.shared.play(.win)
    }
}
