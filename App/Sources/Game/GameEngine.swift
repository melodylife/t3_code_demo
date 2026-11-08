import Combine
import Foundation
import Match3Core

final class GameEngine: ObservableObject, GameSceneDelegate {
    enum Phase: Equatable {
        case playing
        case won
        case lost
    }

    let level: Level
    let scene: GameScene

    @Published private(set) var score = 0
    @Published private(set) var movesLeft: Int
    @Published private(set) var phase: Phase = .playing

    private var tracker = ObjectiveTracker()

    init(level: Level) {
        self.level = level
        self.movesLeft = level.moves

        var generator = SplitMix64(seed: level.seed)
        let board = BoardGenerator.generate(rows: level.rows,
                                           cols: level.cols,
                                           paletteCount: level.paletteCount,
                                           rng: &generator)
        scene = GameScene(level: level, board: board, rng: generator)
        scene.gameDelegate = self
    }

    func current(for objective: Objective) -> Int {
        tracker.current(for: objective)
    }

    func progress(for objective: Objective) -> Double {
        tracker.progress(for: objective)
    }

    // MARK: - GameSceneDelegate

    func sceneDidConsumeMove() {
        movesLeft = max(0, movesLeft - 1)
    }

    func sceneDidClear(points: Int, kinds: [TileKind], spawnedSpecial: Bool) {
        tracker.apply(points: points, cleared: kinds)
        score = tracker.score
    }

    func sceneDidSettle(board: Board) {
        guard phase == .playing else { return }
        if tracker.isSatisfied(level.objectives) {
            phase = .won
            scene.inputEnabled = false
            Haptics.success()
            SoundPlayer.shared.play(.win)
        } else if movesLeft == 0 {
            phase = .lost
            scene.inputEnabled = false
        }
    }

    func sceneRejectedSwap() {}
}
