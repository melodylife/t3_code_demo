import XCTest
@testable import Match3Core

final class BoardGeneratorTests: XCTestCase {

    func testGeneratedBoardsAreStableAndPlayable() {
        for seed in 0..<200 {
            var generator = SplitMix64(seed: UInt64(seed))
            let board = BoardGenerator.generate(rows: 8, cols: 8, paletteCount: 6, rng: &generator)
            XCTAssertEqual(board.rows, 8)
            XCTAssertEqual(board.occupiedCells.count, 64)
            XCTAssertTrue(MatchDetector.groups(in: board).isEmpty, "seed \(seed) dealt a match")
            XCTAssertTrue(Resolver.hasAnyMove(board), "seed \(seed) dealt a dead board")
        }
    }

    func testGeneratedBoardIsFullyPopulated() {
        var generator = SplitMix64(seed: 99)
        let board = BoardGenerator.generate(rows: 5, cols: 7, paletteCount: 5, rng: &generator)
        XCTAssertEqual(board.tiles.compactMap { $0 }.count, 35)
        let kinds = Set(board.tiles.compactMap { $0?.kind?.index })
        XCTAssertTrue(kinds.isSubset(of: Set(0..<5)))
    }

    func testShuffleResolvesADeadBoard() {
        // No adjacent swap in this board can make a run: four distinct kinds in
        // every 2x2 window, laid out so that each row is a rotation of the last.
        let dead = makeBoard([
            "01230123",
            "12301230",
            "23012301",
            "30123012",
            "01230123",
            "12301230",
            "23012301",
            "30123012",
        ])
        XCTAssertFalse(Resolver.hasAnyMove(dead))

        var generator = SplitMix64(seed: 5)
        let shuffled = BoardGenerator.shuffled(dead, paletteCount: 8, rng: &generator)
        XCTAssertTrue(MatchDetector.groups(in: shuffled).isEmpty)
        XCTAssertTrue(Resolver.hasAnyMove(shuffled))
        XCTAssertEqual(shuffled.tiles.compactMap { $0 }.count, 64)
    }
}
