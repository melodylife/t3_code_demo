import Combine
import Foundation
import Match3Core
import SpriteKit

enum GuidedPracticeState: Equatable {
    case instructional
    case completed
}

/// Coordinates a deterministic practice board outside campaign scoring.
final class GuidedPracticeCoordinator: ObservableObject {
    @Published private(set) var state: GuidedPracticeState = .instructional
    @Published private(set) var swapCompleted = false

    let scene: GameScene
    let targetPair: (Cell, Cell) = (Cell(row: 0, col: 2), Cell(row: 1, col: 2))

    var onFinished: (() -> Void)?

    init() {
        // Deterministic 3x3 practice layout
        // Row 0: 🍎 🍎 🍌  (0, 0, 1)
        // Row 1: 🍇 🍊 🍎  (2, 3, 0)
        // Row 2: 🍊 🍇 🍊  (3, 2, 3)
        // Swapping (0,2) and (1,2) creates a horizontal match of 3 apples in row 0
        var board = Board(rows: 3, cols: 3)
        board[Cell(row: 0, col: 0)] = .normal(TileKind(0))
        board[Cell(row: 0, col: 1)] = .normal(TileKind(0))
        board[Cell(row: 0, col: 2)] = .normal(TileKind(1))

        board[Cell(row: 1, col: 0)] = .normal(TileKind(2))
        board[Cell(row: 1, col: 1)] = .normal(TileKind(3))
        board[Cell(row: 1, col: 2)] = .normal(TileKind(0))

        board[Cell(row: 2, col: 0)] = .normal(TileKind(3))
        board[Cell(row: 2, col: 1)] = .normal(TileKind(2))
        board[Cell(row: 2, col: 2)] = .normal(TileKind(3))

        let practiceLevel = Level(
            id: 0,
            rows: 3,
            cols: 3,
            moves: 10,
            palette: ["🍎", "🍌", "🍇", "🍊"],
            objectives: [Objective(type: .collect, target: 3, tileKind: 0)],
            starThresholds: [100, 200, 300],
            seed: 42
        )

        let rng = SplitMix64(seed: 42)
        self.scene = GameScene(level: practiceLevel, board: board, rng: rng)

        setupScene()
    }

    private func setupScene() {
        // Display initial hint pointing to the target swap
        scene.onBoardSettled = { [weak self] _ in
            guard let self else { return }
            self.swapCompleted = true
            self.state = .completed
        }

        // Highlight the teaching swap immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.state == .instructional else { return }
            self.scene.requestHint(unmetCollectionKinds: [TileKind(0)])
        }
    }

    func completePractice() {
        LearningStore.shared.markTutorialCompleted()
        onFinished?()
    }

    func skipPractice() {
        LearningStore.shared.skipTutorial()
        onFinished?()
    }
}
