import XCTest
import Match3Core
@testable import EmojiMatch

/// Drives scene-delegate boundaries to verify real engine/app routing without
/// depending on touch coordinates or random cascades. Core replay is tested separately.
@MainActor
final class SessionIntegrationTests: XCTestCase {
    func testDailyClearAndChaseNeverChangeCampaignProgress() throws {
        let fixture = try makeFixture()
        let configuration = try fixture.daily.captureForLaunch()
        fixture.app.start(configuration)
        let engine = try XCTUnwrap(fixture.app.engine)

        settleMove(engine, points: 1500)
        XCTAssertEqual(engine.phase, .goalReached)
        XCTAssertEqual(fixture.history.records.first?.bestCompletedScore, 1500)
        XCTAssertEqual(fixture.history.records.first?.movesUsed, 1)
        XCTAssertEqual(fixture.app.progress, .empty)

        engine.chooseStarChase()
        settleMove(engine, points: 1100)
        XCTAssertEqual(fixture.history.records.first?.bestCompletedScore, 2600)
        XCTAssertEqual(fixture.history.records.first?.movesUsed, 2)
        engine.requestFinish()
        XCTAssertEqual(engine.phase, .won)
        XCTAssertEqual(fixture.app.progress, .empty)
        XCTAssertEqual(fixture.campaign.data, .empty)
        XCTAssertEqual(fixture.app.bestScore(for: configuration), 2600)
    }

    func testDailyLossRecordsPlayedWithoutACompletion() throws {
        let fixture = try makeFixture()
        fixture.app.start(try fixture.daily.captureForLaunch())
        let engine = try XCTUnwrap(fixture.app.engine)
        for _ in 0..<engine.level.moves { settleMove(engine, points: 0) }
        XCTAssertEqual(engine.phase, .lost)
        XCTAssertEqual(fixture.history.records.count, 1)
        XCTAssertEqual(fixture.history.records.first?.completed, false)
        XCTAssertNil(fixture.history.records.first?.bestCompletedScore)
        XCTAssertEqual(fixture.app.progress, .empty)
    }

    func testDailyRetryKeepsCapturedDateAfterMidnight() throws {
        var now = try XCTUnwrap(DailyChallengeID.calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 8, hour: 23, minute: 59)))
        let fixture = try makeFixture(clock: { now })
        let captured = try fixture.daily.captureForLaunch()
        fixture.app.start(captured)
        let firstID = try XCTUnwrap(fixture.app.engine).sessionID
        now.addTimeInterval(120)
        fixture.daily.refreshMenu()
        XCTAssertNotEqual(fixture.daily.menuChallenge.id, captured.dailyChallenge?.id)
        fixture.app.start(captured)
        XCTAssertEqual(fixture.app.engine?.configuration, captured)
        XCTAssertNotEqual(fixture.app.engine?.sessionID, firstID)
        XCTAssertNotEqual(try fixture.daily.captureForLaunch(), captured)
    }

    func testCollectionClearSavesBeforeChoiceAndGuaranteesOneStar() throws {
        let collection = level(objectives: [Objective(type: .collect, target: 1, tileKind: 0)])
        let fixture = try makeFixture(levels: [collection, level(id: 2)])
        fixture.app.start(collection)
        let engine = try XCTUnwrap(fixture.app.engine)
        settleMove(engine, points: 60, kinds: [TileKind(0)])
        XCTAssertEqual(engine.phase, .goalReached)
        XCTAssertEqual(engine.earnedStars, 1)
        XCTAssertTrue(fixture.app.isCompleted(collection))
        XCTAssertEqual(fixture.app.nextCampaignLevel?.id, 2)
        XCTAssertEqual(fixture.campaign.data.stars[1], 1)
        XCTAssertTrue(fixture.history.records.isEmpty)
        engine.requestFinish()
        XCTAssertEqual(engine.phase, .won)
    }

    func testFailedCampaignDoesNotRecordABestClearedScore() throws {
        let collection = level(objectives: [Objective(type: .collect, target: 1, tileKind: 0)])
        let fixture = try makeFixture(levels: [collection])
        fixture.app.start(collection)
        let engine = try XCTUnwrap(fixture.app.engine)
        for _ in 0..<collection.moves { settleMove(engine, points: 5000, kinds: [TileKind(1)]) }
        XCTAssertEqual(engine.phase, .lost)
        XCTAssertEqual(engine.earnedStars, 0)
        XCTAssertEqual(fixture.app.progress, .empty)
    }

    func testFinishDuringPlaybackWaitsForTheSettledOutcome() throws {
        let fixture = try makeFixture()
        fixture.app.start(fixture.app.levels[0])
        let engine = try XCTUnwrap(fixture.app.engine)
        settleMove(engine, points: 1500)
        engine.chooseStarChase()
        engine.sceneDidConsumeMove()
        engine.sceneDidClear(points: 270, kinds: [], spawnedSpecial: false)
        engine.requestFinish()
        XCTAssertEqual(engine.phase, .starChase)
        XCTAssertTrue(engine.isResolving)
        engine.sceneDidSettle(board: Board(rows: 1, cols: 1))
        XCTAssertEqual(engine.phase, .won)
        XCTAssertEqual(fixture.campaign.data.bestScores[1], 1770)
    }

    func testFractionalFeedbackNeverAwardsPointsTwice() {
        let engine = GameEngine(level: level())
        engine.receiveClearFeedback(points: 270, multiplier: 1.5, spawnedSpecial: false)
        XCTAssertEqual(engine.clearFeedback?.multiplier, 1.5)
        XCTAssertEqual(engine.score, 0)
        engine.resetTransientState()
        XCTAssertNil(engine.clearFeedback)
    }

    func testInputBlockSurvivesSettleAndReplayGetsANewIdentity() throws {
        let fixture = try makeFixture()
        let selected = fixture.app.levels[0]
        fixture.app.start(selected)
        let engine = try XCTUnwrap(fixture.app.engine)
        engine.setInputBlocked(true)
        engine.sceneDidSettle(board: Board(rows: 1, cols: 1))
        XCTAssertFalse(engine.scene.inputEnabled)
        engine.setInputBlocked(false)
        XCTAssertTrue(engine.scene.inputEnabled)
        fixture.app.start(selected)
        XCTAssertNotEqual(fixture.app.engine?.sessionID, engine.sessionID)
    }

    private func settleMove(_ engine: GameEngine, points: Int, kinds: [TileKind] = []) {
        engine.sceneDidConsumeMove()
        engine.sceneDidClear(points: points, kinds: kinds, spawnedSpecial: false)
        engine.sceneDidSettle(board: Board(rows: 1, cols: 1))
    }

    private func level(id: Int = 1, objectives: [Objective]? = nil) -> Level {
        Level(id: id, rows: 8, cols: 8, moves: 3,
              palette: ["🍎", "🍊", "🍋", "🍇", "🍓"],
              objectives: objectives ?? [Objective(type: .score, target: 1500)],
              starThresholds: [1500, 2500, 4000], seed: 1001)
    }

    private struct Fixture {
        let app: AppModel
        let campaign: CampaignProgressStore
        let daily: DailyPuzzleModel
        let history: DailyChallengeStore
    }

    private func makeFixture(levels: [Level]? = nil,
                             clock: @escaping () -> Date = Date.init) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let campaign = CampaignProgressStore(url: directory.appendingPathComponent("progress.json"))
        let history = DailyChallengeStore(url: directory.appendingPathComponent("daily.json"))
        let daily = try DailyPuzzleModel(store: history, clock: clock)
        let app = AppModel(store: campaign, dailyModel: daily, levels: levels ?? [level(), level(id: 2)])
        return Fixture(app: app, campaign: campaign, daily: daily, history: history)
    }
}
