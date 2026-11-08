import XCTest
@testable import Match3Core

final class ResolverTests: XCTestCase {

    private func rng(_ seed: UInt64 = 42) -> SplitMix64 { SplitMix64(seed: seed) }

    // MARK: - Rejection

    func testRejectedSwapLeavesBoardUntouched() {
        let board = makeBoard(["0123", "1230", "2301", "3012"])
        var generator = rng()
        let a = Cell(row: 0, col: 0)
        let b = Cell(row: 0, col: 1)

        let resolution = Resolver.resolveSwap(board, a, b, paletteCount: 4, rng: &generator)

        XCTAssertFalse(resolution.wasAccepted)
        XCTAssertEqual(resolution.steps, [.swap(a, b, .rejected)])
        XCTAssertEqual(resolution.finalBoard, board)
        XCTAssertEqual(resolution.totalPoints, 0)
    }

    func testDiagonalSwapIsRejected() {
        var board = makeBoard(["0123", "1230", "2301", "3012"])
        board[Cell(row: 1, col: 1)] = .normal(TileKind(0))
        var generator = rng()
        let resolution = Resolver.resolveSwap(board,
                                              Cell(row: 0, col: 0),
                                              Cell(row: 1, col: 1),
                                              paletteCount: 4,
                                              rng: &generator)
        XCTAssertFalse(resolution.wasAccepted)
    }

    // MARK: - Acceptance

    func testAcceptedSwapClearsThreeAndRefills() {
        let board = makeBoard(["0012", "0120", "3012"])
        var generator = rng()
        let a = Cell(row: 1, col: 1)
        let b = Cell(row: 1, col: 0)

        let resolution = Resolver.resolveSwap(board, a, b, paletteCount: 4, rng: &generator)

        XCTAssertTrue(resolution.wasAccepted)
        XCTAssertGreaterThan(resolution.totalPoints, 0)
        guard case let .clear(cells, _, _, _)? = firstClear(resolution) else {
            return XCTFail("expected a clear step")
        }
        XCTAssertEqual(Set(cells), [Cell(row: 0, col: 1), Cell(row: 1, col: 1), Cell(row: 2, col: 1)])
        XCTAssertEqual(applySteps(resolution.steps, to: board), resolution.finalBoard)
        XCTAssertTrue(MatchDetector.groups(in: resolution.finalBoard).isEmpty)
    }

    /// The advisory case: a rainbow swapped with a normal tile must be accepted
    /// even though the swap forms no run.
    func testRainbowSwapIsAcceptedWithoutAnyRun() {
        let board = makeBoard(["W123", "3012", "1230"])
        XCTAssertTrue(MatchDetector.groups(in: makeBoard(["W123", "3012", "1230"])).isEmpty)
        var generator = rng()
        let a = Cell(row: 0, col: 0)
        let b = Cell(row: 0, col: 1)

        XCTAssertTrue(Resolver.isAcceptedSwap(board, a, b))
        let resolution = Resolver.resolveSwap(board, a, b, paletteCount: 4, rng: &generator)

        XCTAssertTrue(resolution.wasAccepted)
        XCTAssertEqual(resolution.clearedKinds[TileKind(1)], 3, "every kind-1 tile is cleared")
        // The swap itself forms no run, so acceptance came only from the rainbow.
        XCTAssertTrue(MatchDetector.groups(in: board).isEmpty)
    }

    /// Regression: seeds were collected on the pre-swap board, so after the swap the
    /// rainbow sat on a colour cell that was in the seed set. It was then detonated a
    /// second time for the most common kind, clearing most of the board instead of the
    /// chosen colour plus the rainbow.
    func testRainbowSwapClearsExactlyTheChosenColourPlusTheRainbow() {
        let board = makeBoard(["W102", "2030", "0203"])
        let a = Cell(row: 0, col: 0)
        let b = Cell(row: 0, col: 1)
        XCTAssertTrue(MatchDetector.groups(in: board).isEmpty)

        for (from, to) in [(a, b), (b, a)] {
            var generator = rng()
            let resolution = Resolver.resolveSwap(board, from, to, paletteCount: 4, rng: &generator)
            XCTAssertTrue(resolution.wasAccepted)
            guard case let .clear(cells, _, _, _)? = firstClear(resolution) else {
                return XCTFail("expected a clear step")
            }
            XCTAssertEqual(Set(cells), [a, b], "from \(from) to \(to)")
            XCTAssertEqual(resolution.clearedKinds[TileKind(1)], 1, "from \(from) to \(to)")
        }
    }

    /// A special swapped with a rainbow must detonate, not be skipped as "already resolved".
    func testRainbowPlusRocketSwapDetonatesTheRocket() {
        let board = makeBoard(["WR12", "1231", "2312"])
        let rainbow = Cell(row: 0, col: 0)
        let rocket = Cell(row: 0, col: 1)

        var generator = rng()
        let resolution = Resolver.resolveSwap(board, rainbow, rocket, paletteCount: 4, rng: &generator)
        XCTAssertTrue(resolution.wasAccepted)
        guard case let .clear(cells, _, _, _)? = firstClear(resolution) else {
            return XCTFail("expected a clear step")
        }
        XCTAssertEqual(Set(cells), Set((0..<4).map { Cell(row: 0, col: $0) }),
                       "the horizontal rocket takes its whole row")
    }

    func testRainbowSwapWithNoRunStillValidatesForHasAnyMove() {
        let board = makeBoard(["W123", "3012", "1230"])
        XCTAssertTrue(Resolver.hasAnyMove(board))
        XCTAssertNotNil(Resolver.firstAvailableMove(board))
    }

    func testRocketPlusRocketIsAcceptedWithoutAnyRun() {
        let board = makeBoard(["RC13", "0123", "2010"])
        var generator = rng()
        let a = Cell(row: 0, col: 0)
        let b = Cell(row: 0, col: 1)

        XCTAssertTrue(MatchDetector.groups(in: board).isEmpty)
        XCTAssertTrue(Resolver.isAcceptedSwap(board, a, b))

        let resolution = Resolver.resolveSwap(board, a, b, paletteCount: 4, rng: &generator)
        XCTAssertTrue(resolution.wasAccepted)
        guard case let .clear(cells, _, _, _)? = firstClear(resolution) else {
            return XCTFail("expected a clear step")
        }
        // Row 0 (4 cells) union column 0 (3 cells) = 6 distinct cells.
        XCTAssertEqual(cells.count, 6)
        XCTAssertEqual(applySteps(resolution.steps, to: board), resolution.finalBoard)
    }

    // MARK: - Specials

    func testRunOfFourSpawnsRocketAtSwapCell() {
        let board = makeBoard(["1023", "0200", "2131"])
        var generator = rng()
        let a = Cell(row: 1, col: 1)
        let b = Cell(row: 0, col: 1)

        let resolution = Resolver.resolveSwap(board, a, b, paletteCount: 4, rng: &generator)
        guard case let .clear(_, spawned, _, _)? = firstClear(resolution) else {
            return XCTFail("expected a clear step")
        }
        XCTAssertEqual(spawned, [TileSpawn(cell: Cell(row: 1, col: 1),
                                           tile: .rocket(TileKind(0), .horizontal))])
    }

    func testRunOfFiveSpawnsRainbow() {
        let board = makeBoard(["10230", "02000", "21311"])
        var generator = rng()
        let resolution = Resolver.resolveSwap(board,
                                              Cell(row: 1, col: 1),
                                              Cell(row: 0, col: 1),
                                              paletteCount: 4,
                                              rng: &generator)
        guard case let .clear(_, spawned, _, _)? = firstClear(resolution) else {
            return XCTFail("expected a clear step")
        }
        XCTAssertEqual(spawned.map(\.tile), [.rainbow])
    }

    func testVerticalRocketClearsItsColumn() {
        let board = makeBoard(["020C", "0023", "2031"])
        var generator = rng()
        let resolution = Resolver.resolveSwap(board,
                                              Cell(row: 0, col: 1),
                                              Cell(row: 1, col: 1),
                                              paletteCount: 4,
                                              rng: &generator)
        guard case let .clear(cells, _, _, _)? = firstClear(resolution) else {
            return XCTFail("expected a clear step")
        }
        // 4 matched cells in row 0 plus the two remaining cells of column 3.
        XCTAssertEqual(cells.count, 6)
        XCTAssertTrue(cells.contains(Cell(row: 1, col: 3)))
        XCTAssertTrue(cells.contains(Cell(row: 2, col: 3)))
    }

    func testBombClearsThreeByThree() {
        let board = makeBoard(["1213", "21B3", "2131"])
        var generator = rng()
        let resolution = Resolver.resolveSwap(board,
                                              Cell(row: 0, col: 0),
                                              Cell(row: 1, col: 0),
                                              paletteCount: 4,
                                              rng: &generator)
        guard case let .clear(cells, _, _, _)? = firstClear(resolution) else {
            return XCTFail("expected a clear step")
        }
        // 3x3 around the bomb (9) plus the matched cell at column 0, outside the blast.
        XCTAssertEqual(cells.count, 10)
    }

    // MARK: - Scoring

    func testMultiplierRamp() {
        XCTAssertEqual(Rules.multiplier(cascadeIndex: 0), 1.0)
        XCTAssertEqual(Rules.multiplier(cascadeIndex: 1), 1.5)
        XCTAssertEqual(Rules.multiplier(cascadeIndex: 2), 2.0)
        XCTAssertEqual(Rules.multiplier(cascadeIndex: 3), 2.5)
        XCTAssertEqual(Rules.multiplier(cascadeIndex: 9), 3.0)
    }

    func testScoringTable() {
        var score = Rules.points(clearedCount: 3, groups: [], detonations: 0, multiplier: 1)
        XCTAssertEqual(score, 180)

        score = Rules.points(clearedCount: 4, groups: [], detonations: 0, multiplier: 1)
        XCTAssertEqual(score, 240)

        score = Rules.points(clearedCount: 3, groups: [], detonations: 1, multiplier: 1)
        XCTAssertEqual(score, 280)

        score = Rules.points(clearedCount: 3, groups: [], detonations: 0, multiplier: 2)
        XCTAssertEqual(score, 360)
    }

    // MARK: - Cascade contract

    func testApplyingStepsReconstructsFinalBoard() {
        let board = makeBoard(["0012", "0120", "3012", "2301"])
        var generator = rng(7)
        var accepted = 0

        for row in 0..<board.rows {
            for col in 0..<board.cols {
                for delta in [Cell(row: 0, col: 1), Cell(row: 1, col: 0)] {
                    let a = Cell(row: row, col: col)
                    let b = a.offset(row: delta.row, col: delta.col)
                    guard board.contains(b) else { continue }
                    let resolution = Resolver.resolveSwap(board, a, b, paletteCount: 4, rng: &generator)
                    XCTAssertEqual(applySteps(resolution.steps, to: board), resolution.finalBoard,
                                   "step replay diverged for \(a) -> \(b)")
                    if resolution.wasAccepted { accepted += 1 }
                }
            }
        }
        XCTAssertGreaterThan(accepted, 0)
    }

    func testRandomSwapsAlwaysTerminateAndStayStable() {
        var generator = rng(2024)
        for seed in 0..<60 {
            generator = SplitMix64(seed: UInt64(seed) &+ 1)
            let board = BoardGenerator.generate(rows: 8, cols: 8, paletteCount: 6, rng: &generator)
            for _ in 0..<20 {
                let a = Cell(row: Int.random(in: 0..<8, using: &generator),
                             col: Int.random(in: 0..<8, using: &generator))
                var direction = Cell(row: 0, col: 1)
                if Int.random(in: 0..<2, using: &generator) == 1 { direction = Cell(row: 1, col: 0) }
                let b = a.offset(row: direction.row, col: direction.col)
                guard board.contains(b) else { continue }
                let resolution = Resolver.resolveSwap(board, a, b, paletteCount: 6, rng: &generator)
                XCTAssertLessThan(resolution.steps.count, 200)
                XCTAssertFalse(resolution.hitStepCap)
                XCTAssertTrue(MatchDetector.groups(in: resolution.finalBoard).isEmpty)
                XCTAssertTrue(Resolver.hasAnyMove(resolution.finalBoard))
                XCTAssertEqual(applySteps(resolution.steps, to: board), resolution.finalBoard)
            }
        }
    }

    // MARK: - Gravity + refill

    func testCollapseFillsHolesPerColumn() {
        var board = makeBoard(["012", "3..", "4.."])
        let moves = Resolver.collapse(&board)
        XCTAssertEqual(moves.count, 2, "one tile falls in each of columns 1 and 2")
        XCTAssertNil(board[Cell(row: 0, col: 1)])
        XCTAssertNil(board[Cell(row: 1, col: 1)])
        XCTAssertEqual(board[Cell(row: 2, col: 1)], .normal(TileKind(1)))
        XCTAssertEqual(board[Cell(row: 2, col: 2)], .normal(TileKind(2)))
    }

    func testRefillFillsExactlyTheEmptyCells() {
        var board = makeBoard(["012", "3..", "4.."])
        _ = Resolver.collapse(&board)
        var generator = rng()
        let spawns = Resolver.refill(&board, paletteCount: 4, rng: &generator)
        XCTAssertEqual(spawns.count, 4)
        XCTAssertEqual(board.tiles.compactMap { $0 }.count, 9)
        for spawn in spawns {
            XCTAssertEqual(board[spawn.cell], spawn.tile)
        }
    }
}
