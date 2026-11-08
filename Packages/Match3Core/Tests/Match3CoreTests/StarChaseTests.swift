import XCTest
@testable import Match3Core

final class StarChaseTests: XCTestCase {
    func testCampaignClearGuaranteesOneStarBelowFirstThreshold() {
        XCTAssertEqual(StarRating.campaign(score: 10,
                                           thresholds: [100, 200, 300],
                                           objectivesCompleted: true), 1)
        XCTAssertEqual(StarRating.campaign(score: 10_000,
                                           thresholds: [100, 200, 300],
                                           objectivesCompleted: false), 0)
        XCTAssertEqual(StarRating.nextCampaignThreshold(score: 10,
                                                        thresholds: [100, 200, 300],
                                                        objectivesCompleted: true), 200)
    }

    func testFinalMoveObjectiveCompletionWinsOverExhaustion() {
        var state = StarChaseState()
        state.didBeginMove()

        XCTAssertEqual(state.didSettle(objectivesSatisfied: true,
                                       movesLeft: 0,
                                       stars: 1), .won)
        XCTAssertTrue(state.phase.hasGuaranteedClear)
    }

    func testFinalMoveWithoutObjectiveLoses() {
        var state = StarChaseState()
        state.didBeginMove()

        XCTAssertEqual(state.didSettle(objectivesSatisfied: false,
                                       movesLeft: 0,
                                       stars: 0), .lost)
        XCTAssertFalse(state.phase.hasGuaranteedClear)
    }

    func testGoalReachedOffersChaseAndEarlyFinish() {
        var chase = StarChaseState()
        XCTAssertEqual(chase.didSettle(objectivesSatisfied: true,
                                       movesLeft: 4,
                                       stars: 1), .goalReached)
        XCTAssertEqual(chase.chooseStarChase(movesLeft: 4, stars: 1), .starChase)
        XCTAssertEqual(chase.requestFinish(), .won)

        var finish = StarChaseState()
        _ = finish.didSettle(objectivesSatisfied: true, movesLeft: 4, stars: 1)
        XCTAssertEqual(finish.requestFinish(), .won)
    }

    func testThreeStarsFinishAtSettledBoundary() {
        var state = StarChaseState()
        XCTAssertEqual(state.didSettle(objectivesSatisfied: true,
                                       movesLeft: 5,
                                       stars: 3), .won)
    }

    func testChaseExhaustionCanNeverLose() {
        var state = StarChaseState()
        _ = state.didSettle(objectivesSatisfied: true, movesLeft: 2, stars: 1)
        _ = state.chooseStarChase(movesLeft: 2, stars: 1)
        state.didBeginMove()

        XCTAssertEqual(state.didSettle(objectivesSatisfied: true,
                                       movesLeft: 0,
                                       stars: 1), .won)
    }

    func testFinishDuringPlaybackQueuesUntilSettle() {
        var state = StarChaseState()
        _ = state.didSettle(objectivesSatisfied: true, movesLeft: 2, stars: 1)
        _ = state.chooseStarChase(movesLeft: 2, stars: 1)
        state.didBeginMove()

        XCTAssertEqual(state.requestFinish(), .starChase)
        XCTAssertTrue(state.finishIsQueued)
        XCTAssertEqual(state.didSettle(objectivesSatisfied: true,
                                       movesLeft: 1,
                                       stars: 1), .won)
        XCTAssertFalse(state.finishIsQueued)
    }
}
