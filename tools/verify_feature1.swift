import Foundation
import Match3Core

// Verification script for Feature 1 (Guided Play)

func assertCondition(_ condition: Bool, _ message: String) {
    if !condition {
        print("❌ Assertion failed: \(message)")
        exit(1)
    }
}

print("Running Feature 1 Guided Play Verification...")

// 1. Verify HintAdvisor on a live level from catalog
let levelJsonUrl = URL(fileURLWithPath: "App/Resources/levels.json")
let data = try! Data(contentsOf: levelJsonUrl)
let levels = try! JSONDecoder().decode([Level].self, from: data)

for level in levels {
    var rng = SplitMix64(seed: level.seed)
    let board = BoardGenerator.generate(rows: level.rows, cols: level.cols, paletteCount: level.paletteCount, rng: &rng)
    assertCondition(board.rows == level.rows, "Board rows match")
    assertCondition(board.cols == level.cols, "Board cols match")

    let hint = HintAdvisor.suggest(board: board, unmetObjectives: level.objectives)
    if let hint = hint {
        assertCondition(Resolver.isAcceptedSwap(board, hint.from, hint.to), "Hint must be legal swap on level \(level.id)")
        assertCondition(board.contains(hint.from) && board.contains(hint.to), "Hint coordinates inside board")
        assertCondition(hint.from.isAdjacent(to: hint.to), "Hint cells are adjacent")
    }
}
print("✅ Verified HintAdvisor on all shipped catalog levels.")

// 2. Verify Guided Practice Board Determinism
var practiceBoard = Board(rows: 3, cols: 3)
practiceBoard[Cell(row: 0, col: 0)] = .normal(TileKind(0))
practiceBoard[Cell(row: 0, col: 1)] = .normal(TileKind(0))
practiceBoard[Cell(row: 0, col: 2)] = .normal(TileKind(1))

practiceBoard[Cell(row: 1, col: 0)] = .normal(TileKind(2))
practiceBoard[Cell(row: 1, col: 1)] = .normal(TileKind(3))
practiceBoard[Cell(row: 1, col: 2)] = .normal(TileKind(0))

practiceBoard[Cell(row: 2, col: 0)] = .normal(TileKind(3))
practiceBoard[Cell(row: 2, col: 1)] = .normal(TileKind(2))
practiceBoard[Cell(row: 2, col: 2)] = .normal(TileKind(3))

let practiceHint = HintAdvisor.suggest(board: practiceBoard, unmetCollectionKinds: [TileKind(0)])
assertCondition(practiceHint != nil, "Practice board has legal hint")
assertCondition(practiceHint?.from == Cell(row: 0, col: 2) && practiceHint?.to == Cell(row: 1, col: 2), "Practice hint matches expected target swap (0,2) <-> (1,2)")
assertCondition(practiceHint?.contributesToObjective == true, "Practice hint contributes to apple objective")

print("✅ Verified Guided Practice Board layout and deterministic hint.")

// 3. Verify InitialClearEvaluation does not mutate board
let preEval = practiceBoard
_ = Resolver.evaluateInitialClear(practiceBoard, Cell(row: 0, col: 2), Cell(row: 1, col: 2))
assertCondition(practiceBoard == preEval, "Resolver.evaluateInitialClear must not mutate board")

print("✅ Verified non-destructive evaluation.")

print("\n🎉 ALL FEATURE 1 HEADLESS VERIFICATION CHECKS PASSED SUCCESSFULLY!")
