import XCTest
@testable import Match3Core

final class MatchDetectorTests: XCTestCase {

    func testHorizontalRunOfThree() {
        let board = makeBoard(["000", "121", "212"])
        let groups = MatchDetector.groups(in: board)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].length, 3)
        XCTAssertEqual(groups[0].shape, .line(3))
        XCTAssertEqual(groups[0].cells, [Cell(row: 0, col: 0), Cell(row: 0, col: 1), Cell(row: 0, col: 2)])
    }

    func testVerticalRunOfThree() {
        let board = makeBoard(["011", "210", "210"])
        let groups = MatchDetector.groups(in: board)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].shape, .line(3))
        XCTAssertEqual(groups[0].cells, [Cell(row: 0, col: 1), Cell(row: 1, col: 1), Cell(row: 2, col: 1)])
    }

    func testRunOfFour() {
        let board = makeBoard(["0000", "1212", "2121", "1212"])
        let groups = MatchDetector.groups(in: board)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].shape, .line(4))
        XCTAssertEqual(Rules.special(for: groups[0]), .rocket(TileKind(0), .horizontal))
    }

    func testRunOfFiveSpawnsRainbow() {
        let board = makeBoard(["00000", "12121", "21212", "12121", "21212"])
        let groups = MatchDetector.groups(in: board)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].shape, .line(5))
        XCTAssertEqual(Rules.special(for: groups[0]), .rainbow)
    }

    func testLShapeIsOneGroupOfFive() {
        let board = makeBoard(["000", "0..", "0.."])
        let groups = MatchDetector.groups(in: board)
        XCTAssertEqual(groups.count, 1, "an L is one group, not two matches of three")
        XCTAssertEqual(groups[0].length, 5)
        XCTAssertEqual(groups[0].shape, .corner)
        XCTAssertEqual(groups[0].pivot, Cell(row: 0, col: 0))
        XCTAssertEqual(Rules.special(for: groups[0]), .bomb(TileKind(0)))
    }

    func testTShapeIsOneGroupOfFive() {
        let board = makeBoard(["000", ".0.", ".0."])
        let groups = MatchDetector.groups(in: board)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].length, 5)
        XCTAssertEqual(groups[0].shape, .corner)
        XCTAssertEqual(groups[0].pivot, Cell(row: 0, col: 1))
    }

    func testTwoDisjointGroups() {
        let board = makeBoard(["0000", "1234", "0000"])
        let groups = MatchDetector.groups(in: board)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.length), [4, 4])
    }

    func testRainbowNeverJoinsARun() {
        let board = makeBoard(["0W0", "121", "212"])
        XCTAssertTrue(MatchDetector.groups(in: board).isEmpty)
    }

    func testSpecialKeepsItsKindForMatching() {
        let board = makeBoard(["RR0", "121", "212"])
        let groups = MatchDetector.groups(in: board)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].length, 3)
    }

    func testStableBoardHasNoGroups() {
        let board = makeBoard(["0123", "1230", "2301", "3012"])
        XCTAssertTrue(MatchDetector.groups(in: board).isEmpty)
    }
}
