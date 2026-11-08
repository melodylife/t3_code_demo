import XCTest
@testable import Match3Core

final class HintAdvisorTests: XCTestCase {
    func testEqualCollectionCountsExplainLowestKindDeterministically() {
        let board = makeBoard(["WW01", "0101"])
        for _ in 0..<20 {
            let hint = HintAdvisor.suggest(board: board,
                                           unmetCollectionKinds: [TileKind(1), TileKind(0)])
            XCTAssertEqual(hint?.reason, .collectObjective(kind: TileKind(0), clearedCount: 3))
        }
    }

    func testNoLegalMoveReturnsNil() {
        // 3x3 board with no matches and no legal moves
        let board = makeBoard([
            "012",
            "201",
            "120"
        ])
        XCTAssertFalse(Resolver.hasAnyMove(board))
        let hint = HintAdvisor.suggest(board: board)
        XCTAssertNil(hint)
    }

    func testHintLegality() {
        let board = makeBoard([
            "0102",
            "2313",
            "2301",
            "3210"
        ])
        guard let hint = HintAdvisor.suggest(board: board) else {
            XCTFail("Expected a hint")
            return
        }
        XCTAssertTrue(board.contains(hint.from))
        XCTAssertTrue(board.contains(hint.to))
        XCTAssertTrue(hint.from.isAdjacent(to: hint.to))
        XCTAssertTrue(Resolver.isAcceptedSwap(board, hint.from, hint.to))
    }

    func testDeterministicTieBreaking() {
        // Board with two symmetric disjoint 3-matches on row 0 and row 3
        // Rows 1 and 2 use kinds 2, 3, 4, 5 so no vertical interference exists.
        let board = makeBoard([
            "0010",
            "2345",
            "5432",
            "1101"
        ])
        let hint1 = HintAdvisor.suggest(board: board)
        let hint2 = HintAdvisor.suggest(board: board)
        XCTAssertNotNil(hint1)
        XCTAssertEqual(hint1, hint2)
        // Row 0 match (swap (0,2) and (0,3)) wins deterministically over row 3 by row-major order
        XCTAssertEqual(hint1?.from.row, 0)
    }

    func testObjectivePriorityFavorsCollectionGoal() {
        // Board has a legal match for kind 0 at row 0, and a legal match for kind 1 at row 3
        let board = makeBoard([
            "0010",
            "2345",
            "5432",
            "1101"
        ])

        // When unmet collection goal is kind 1
        let hintKind1 = HintAdvisor.suggest(board: board, unmetCollectionKinds: [TileKind(1)])
        XCTAssertNotNil(hintKind1)
        XCTAssertEqual(hintKind1?.from.row, 3)
        if case let .collectObjective(kind, count)? = hintKind1?.reason {
            XCTAssertEqual(kind, TileKind(1))
            XCTAssertEqual(count, 3)
        } else {
            XCTFail("Expected collectObjective reason, got \(String(describing: hintKind1?.reason))")
        }
        XCTAssertTrue(hintKind1?.contributesToObjective == true)

        // When unmet collection goal is kind 0
        let hintKind0 = HintAdvisor.suggest(board: board, unmetCollectionKinds: [TileKind(0)])
        XCTAssertNotNil(hintKind0)
        XCTAssertEqual(hintKind0?.from.row, 0)
        if case let .collectObjective(kind, count)? = hintKind0?.reason {
            XCTAssertEqual(kind, TileKind(0))
            XCTAssertEqual(count, 3)
        } else {
            XCTFail("Expected collectObjective reason, got \(String(describing: hintKind0?.reason))")
        }
        XCTAssertTrue(hintKind0?.contributesToObjective == true)
    }

    func testObjectivePriorityFavorsHigherCollectionCount() {
        // Top: Move A forms a 4-match of kind 0 (swap (0,2) and (1,2))
        // Bottom: Move B forms a 3-match of kind 0 (swap (3,2) and (3,3))
        let board = makeBoard([
            "00102",
            "23034",
            "45252",
            "20012"
        ])

        let hint = HintAdvisor.suggest(board: board, unmetCollectionKinds: [TileKind(0)])
        XCTAssertNotNil(hint)
        XCTAssertEqual(hint?.from.row, 0)
        if case let .collectObjective(kind, count)? = hint?.reason {
            XCTAssertEqual(kind, TileKind(0))
            XCTAssertEqual(count, 4)
        } else {
            XCTFail("Expected collectObjective for 4 tiles")
        }
    }

    func testSpecialCreationPrioritizedOverNormalMatch() {
        // Without collection goals:
        // A match-4 that creates a Rocket is prioritized over a simple match-3
        let board = makeBoard([
            "00102", // 3-match: swap (0,2) and (0,3) forms 00012
            "23452",
            "54324",
            "11211"  // 4-match: swap (3,2) and (2,2) with a 1 at (2,2) -> let's make it explicit
        ])

        // Let's create an explicit match-4 setup on row 3:
        // Row 3: "11211" -> wait, swap (3,2) and (2,2)
        let board2 = makeBoard([
            "00102", // 3-match at top: swap (0,2) and (0,3)
            "23452",
            "54124", // (2,2) has kind 1
            "11213"  // swap (3,2) and (2,2) gives "11113" in row 3 (4 in a row!)
        ])

        let hint = HintAdvisor.suggest(board: board2)
        XCTAssertNotNil(hint)
        XCTAssertEqual(hint?.from.row, 2)
        XCTAssertEqual(hint?.to.row, 3)
        if case let .createSpecial(special)? = hint?.reason {
            if case .rocket = special {
                // Rocket created!
            } else {
                XCTFail("Expected rocket special, got \(special)")
            }
        } else {
            XCTFail("Expected createSpecial reason, got \(String(describing: hint?.reason))")
        }
    }

    func testRainbowCreationPrioritizedOverRocket() {
        // 5-match creates Rainbow, 4-match creates Rocket
        // Row 0 has 5-match setup: swap (0,2) with (1,2) where (1,2) is 0 -> "00000"
        // Row 3 has 4-match setup: swap (3,2) with (2,2) where (2,2) is 1 -> "11112"
        let board = makeBoard([
            "00100",
            "23034",
            "54124",
            "11212"
        ])

        let hint = HintAdvisor.suggest(board: board)
        XCTAssertNotNil(hint)
        XCTAssertEqual(hint?.from.row, 0)
        XCTAssertEqual(hint?.to.row, 1)
        XCTAssertEqual(hint?.createdSpecial, .rainbow)
        if case let .createSpecial(special)? = hint?.reason {
            XCTAssertEqual(special, .rainbow)
        } else {
            XCTFail("Expected rainbow creation")
        }
    }

    func testBombCreationPrioritizedOverNormalMatch() {
        // T-shape creates a Bomb at intersection (2,2)
        // Row 2: (2,1) has 0, (2,2) has 2, (2,3) has 0, (2,4) has 0
        // Col 2: (0,2)=0, (1,2)=0, (2,2)=2, (3,2)=5, (4,2)=5
        let board = makeBoard([
            "23023",
            "32032",
            "20200",
            "34543",
            "43534"
        ])
        // Swapping (2,1) with (2,2) puts 0 at (2,2), forming a corner of kind 0 (length 3 horizontal, length 3 vertical)
        let hint = HintAdvisor.suggest(board: board)
        XCTAssertNotNil(hint)
        XCTAssertEqual(hint?.createdSpecial, .bomb(TileKind(0)))
    }

    func testRainbowSwapActivatesSpecial() {
        let board = makeBoard([
            "W012",
            "3210",
            "1230",
            "2301"
        ])
        let hint = HintAdvisor.suggest(board: board)
        XCTAssertNotNil(hint)
        XCTAssertTrue(hint?.from == Cell(row: 0, col: 0) || hint?.to == Cell(row: 0, col: 0))
        XCTAssertTrue(hint?.activatesSpecial == true)
        XCTAssertEqual(hint?.reason, .activateSpecial)
    }

    func testSpecialPairComboPrioritized() {
        let board = makeBoard([
            "RB12",
            "3210",
            "1230",
            "2301"
        ])
        let hint = HintAdvisor.suggest(board: board)
        XCTAssertNotNil(hint)
        XCTAssertEqual(hint?.from, Cell(row: 0, col: 0))
        XCTAssertEqual(hint?.to, Cell(row: 0, col: 1))
        XCTAssertTrue(hint?.activatesSpecial == true)
        XCTAssertEqual(hint?.reason, .activateSpecial)
    }

    func testCompletedGoalFallsBackToUnmetGoal() {
        let board = makeBoard([
            "0010",
            "2345",
            "5432",
            "1101"
        ])

        let objectives = [
            Objective(type: .collect, target: 10, tileKind: 0),
            Objective(type: .collect, target: 10, tileKind: 1)
        ]

        var tracker = ObjectiveTracker()
        tracker.apply(points: 100, cleared: Array(repeating: TileKind(0), count: 10))

        let hint = HintAdvisor.suggest(board: board, objectives: objectives, tracker: tracker)
        XCTAssertNotNil(hint)
        // Should suggest kind 1 match (row 3) because kind 0 is already satisfied
        XCTAssertEqual(hint?.from.row, 3)
        if case let .collectObjective(kind, count)? = hint?.reason {
            XCTAssertEqual(kind, TileKind(1))
            XCTAssertEqual(count, 3)
        } else {
            XCTFail("Expected kind 1 collectObjective")
        }
    }

    func testBoardRemainsUnmodified() {
        let original = makeBoard([
            "0102",
            "2313",
            "2301",
            "3210"
        ])
        let copy = original
        _ = HintAdvisor.suggest(board: original, unmetCollectionKinds: [TileKind(0)])
        XCTAssertEqual(original, copy)
    }

    func testHintLegalityAcrossGeneratedBoards() {
        var rng = SplitMix64(seed: 12345)
        for _ in 0..<20 {
            let board = BoardGenerator.generate(rows: 8, cols: 8, paletteCount: 5, rng: &rng)
            if Resolver.hasAnyMove(board) {
                guard let hint = HintAdvisor.suggest(board: board) else {
                    XCTFail("Board has moves but hint returned nil")
                    continue
                }
                XCTAssertTrue(board.contains(hint.from))
                XCTAssertTrue(board.contains(hint.to))
                XCTAssertTrue(hint.from.isAdjacent(to: hint.to))
                XCTAssertTrue(Resolver.isAcceptedSwap(board, hint.from, hint.to))
            }
        }
    }

    func testRocketDirectionMatchesAlignment() {
        // Horizontal 4-match
        let hBoard = makeBoard([
            "0010",
            "2303",
            "4524",
            "5432"
        ])
        // Swapping (0,2) with (1,2) makes horizontal run of 4 at row 0
        let hHint = HintAdvisor.suggest(board: hBoard)
        XCTAssertNotNil(hHint)
        if case let .createSpecial(special)? = hHint?.reason {
            XCTAssertEqual(special, .rocket(TileKind(0), .horizontal))
        } else {
            XCTFail("Expected horizontal rocket")
        }

        // Vertical 4-match
        let vBoard = makeBoard([
            "0234",
            "0345",
            "1043",
            "0432"
        ])
        // Swapping (2,0) with (2,1) puts 0 into (2,0), making vertical run of 4 at col 0
        let vHint = HintAdvisor.suggest(board: vBoard)
        XCTAssertNotNil(vHint)
        if case let .createSpecial(special)? = vHint?.reason {
            XCTAssertEqual(special, .rocket(TileKind(0), .vertical))
        } else {
            XCTFail("Expected vertical rocket")
        }
    }

    func testChainReactionDetonationIncreasesClearedCount() {
        // Board with a Horizontal Rocket at (1,2)
        // Matching kind 0 into (0,2) detonates the rocket at (1,2)
        // Row 0: "0010" -> swap (0,2) and (1,2) where (1,2) is a rocket of kind 0!
        let board = makeBoard([
            "0020",
            "23R3",
            "4534",
            "5425"
        ])
        // Swapping (0,2) and (1,2) moves R into (0,2), completing a 3-match of kind 0 AND detonating R!
        // Rocket is horizontal, so it blasts all 4 columns of row 0!
        guard let eval = Resolver.evaluateInitialClear(board, Cell(row: 0, col: 2), Cell(row: 1, col: 2)) else {
            XCTFail("Expected valid initial clear")
            return
        }
        XCTAssertTrue(eval.activatesExistingSpecial)
        XCTAssertGreaterThanOrEqual(eval.detonations, 1)
        XCTAssertGreaterThan(eval.clearedCells.count, 3)
    }

    func testDoubleRainbowClearsEntireBoard() {
        let board = makeBoard([
            "WW12",
            "3421",
            "1234",
            "4321"
        ])
        let eval = Resolver.evaluateInitialClear(board, Cell(row: 0, col: 0), Cell(row: 0, col: 1))
        XCTAssertNotNil(eval)
        XCTAssertEqual(eval?.clearedCells.count, 16)
        XCTAssertTrue(eval?.activatesExistingSpecial == true)
    }
}
