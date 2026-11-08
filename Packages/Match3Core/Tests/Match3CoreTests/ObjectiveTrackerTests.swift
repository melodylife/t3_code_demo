import XCTest
@testable import Match3Core

final class ObjectiveTrackerTests: XCTestCase {

    func testScoreObjective() {
        var tracker = ObjectiveTracker()
        tracker.apply(points: 500, cleared: [TileKind(0), TileKind(1)])
        XCTAssertEqual(tracker.score, 500)
        XCTAssertEqual(tracker.progress(for: Objective(type: .score, target: 1000)), 0.5)
        XCTAssertFalse(tracker.isSatisfied([Objective(type: .score, target: 1000)]))
        tracker.apply(points: 600, cleared: [])
        XCTAssertTrue(tracker.isSatisfied([Objective(type: .score, target: 1000)]))
    }

    func testCollectObjective() {
        var tracker = ObjectiveTracker()
        tracker.apply(points: 0, cleared: [TileKind(2), TileKind(2), TileKind(0)])
        XCTAssertEqual(tracker.count(forKind: 2), 2)
        let objective = Objective(type: .collect, target: 2, tileKind: 2)
        XCTAssertTrue(tracker.isSatisfied([objective]))
        XCTAssertEqual(tracker.progress(for: objective), 1.0)
    }

    func testMultipleObjectivesAllRequired() {
        var tracker = ObjectiveTracker()
        tracker.apply(points: 5000, cleared: [TileKind(3)])
        let objectives = [
            Objective(type: .score, target: 4000),
            Objective(type: .collect, target: 2, tileKind: 3),
        ]
        XCTAssertFalse(tracker.isSatisfied(objectives))
        tracker.apply(points: 0, cleared: [TileKind(3)])
        XCTAssertTrue(tracker.isSatisfied(objectives))
    }

    func testStars() {
        let level = Level(id: 1, rows: 8, cols: 8, moves: 20, palette: ["a", "b", "c"],
                          objectives: [Objective(type: .score, target: 100)],
                          starThresholds: [100, 200, 300], seed: 1)
        XCTAssertEqual(level.stars(for: 0), 0)
        XCTAssertEqual(level.stars(for: 150), 1)
        XCTAssertEqual(level.stars(for: 250), 2)
        XCTAssertEqual(level.stars(for: 10_000), 3)
    }
}

final class LevelDataTests: XCTestCase {

    private var levelsURL: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("App/Resources/levels.json")
    }

    func testShippedLevelsDecode() throws {
        let data = try Data(contentsOf: levelsURL)
        let levels = try JSONDecoder().decode([Level].self, from: data)
        XCTAssertEqual(levels.count, 10)
        XCTAssertEqual(levels.map(\.id), Array(1...10))
        for level in levels {
            XCTAssertGreaterThanOrEqual(level.paletteCount, 3)
            XCTAssertGreaterThan(level.moves, 0)
            XCTAssertFalse(level.objectives.isEmpty)
            XCTAssertEqual(level.starThresholds.count, 3)
            for objective in level.objectives where objective.type == .collect {
                let kind = try XCTUnwrap(objective.tileKind)
                XCTAssertTrue((0..<level.paletteCount).contains(kind))
            }
        }
    }
}
