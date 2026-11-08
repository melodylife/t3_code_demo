import XCTest
import Match3Core
@testable import EmojiMatch

@MainActor
final class GuidedPlayIntegrationTests: XCTestCase {
    func testStartTeachesOnceAndPracticeUsesInjectedLearningStore() throws {
        let store = try learningStore()
        let engine = GameEngine(level: level())
        let learning = GuidedPlayCoordinator(scene: engine.scene, store: store)
        XCTAssertTrue(learning.showsLevelIntro)
        XCTAssertTrue(engine.scene.isInputGated)
        learning.dismissLevelIntro()
        XCTAssertTrue(store.hasSeenTips)
        XCTAssertTrue(learning.showsPractice)
        let practice = GuidedPracticeCoordinator(store: store)
        practice.skipPractice()
        learning.closePractice()
        XCTAssertTrue(store.hasCompletedTutorial)
        XCTAssertFalse(engine.scene.isInputGated)
        let replay = GuidedPlayCoordinator(scene: GameEngine(level: level()).scene, store: store)
        XCTAssertFalse(replay.showsLevelIntro)
        XCTAssertFalse(replay.showsPractice)
    }

    func testSkippingFirstTipsNeverChangesGameProgress() throws {
        let store = try learningStore()
        let engine = GameEngine(level: level())
        let learning = GuidedPlayCoordinator(scene: engine.scene, store: store)
        learning.dismissLevelIntro(skipTips: true)
        XCTAssertTrue(store.hasSeenTips)
        XCTAssertTrue(store.hasCompletedTutorial)
        XCTAssertFalse(learning.blocksInput)
        XCTAssertEqual(engine.score, 0)
        XCTAssertEqual(engine.movesLeft, level().moves)
    }

    func testSpecialTipWaitsForSessionChoiceAndIsIntroducedOnce() throws {
        let store = try learningStore()
        store.markTipsSeen()
        var mayPresent = false
        let engine = GameEngine(level: level())
        let learning = GuidedPlayCoordinator(scene: engine.scene, store: store) { mayPresent }
        engine.scene.onSpecialSpawned?(.rocket(TileKind(0), .horizontal))
        engine.scene.onBoardSettled?(engine.scene.board)
        XCTAssertNil(learning.activeSpecialIntro)
        mayPresent = true
        learning.refreshPresentation()
        XCTAssertEqual(learning.activeSpecialIntro, .rocket)
        XCTAssertTrue(engine.scene.isInputGated)
        learning.dismissSpecialIntro()
        XCTAssertTrue(store.hasIntroducedSpecial("rocket"))
        XCTAssertFalse(engine.scene.isInputGated)
        engine.scene.onSpecialSpawned?(.rocket(TileKind(0), .vertical))
        learning.refreshPresentation()
        XCTAssertNil(learning.activeSpecialIntro)
    }

    func testLearningDismissalCannotRemoveExitOrResultInputGate() throws {
        let store = try learningStore()
        let engine = GameEngine(level: level())
        let learning = GuidedPlayCoordinator(scene: engine.scene, store: store)
        engine.setInputBlocked(true)
        learning.dismissLevelIntro(skipTips: true)
        XCTAssertFalse(engine.scene.inputEnabled)
        let pair = try XCTUnwrap(Resolver.firstAvailableMove(engine.scene.board))
        XCTAssertFalse(engine.scene.commitSwap(from: pair.0, to: pair.1))
        XCTAssertEqual(engine.movesLeft, level().moves)
    }

    func testPracticeBoardIsDeterministicAndTeachingPairIsLegal() throws {
        let store = try learningStore()
        let first = GuidedPracticeCoordinator(store: store)
        let second = GuidedPracticeCoordinator(store: store)
        XCTAssertEqual(first.scene.board, second.scene.board)
        XCTAssertTrue(Resolver.isAcceptedSwap(first.scene.board, first.targetPair.0, first.targetPair.1))
        let hint = first.scene.showTeachingHint(from: first.targetPair.0, to: first.targetPair.1)
        XCTAssertEqual(hint?.from, first.targetPair.0)
        XCTAssertEqual(hint?.to, first.targetPair.1)
        first.completePractice()
        XCTAssertFalse(store.hasCompletedTutorial, "An unfinished lesson cannot be marked completed")
    }

    func testRejectedSwapLocksInputUntilItsReturnAnimationFinishes() throws {
        let scene = GameEngine(level: level()).scene
        var rejection: (Cell, Cell)?
        for cell in scene.board.cells {
            let neighbor = cell.offset(col: 1)
            if scene.board.contains(neighbor), !Resolver.isAcceptedSwap(scene.board, cell, neighbor) {
                rejection = (cell, neighbor)
                break
            }
        }
        let rejected = try XCTUnwrap(rejection)
        let accepted = try XCTUnwrap(Resolver.firstAvailableMove(scene.board))
        let original = scene.board
        XCTAssertFalse(scene.commitSwap(from: rejected.0, to: rejected.1))
        XCTAssertFalse(scene.isSettled)
        XCTAssertFalse(scene.commitSwap(from: accepted.0, to: accepted.1))
        XCTAssertEqual(scene.board, original)
        for frame in 0..<6 { scene.update(Double(frame) * 0.1) }
        XCTAssertTrue(scene.isSettled)
    }

    private func level() -> Level {
        Level(id: 1, rows: 8, cols: 8, moves: 20,
              palette: ["🍎", "🍊", "🍋", "🍇", "🍓"],
              objectives: [Objective(type: .score, target: 1500)],
              starThresholds: [1500, 2500, 4000], seed: 1001)
    }

    private func learningStore() throws -> LearningStore {
        let name = "GuidedPlayTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return LearningStore(defaults: defaults)
    }
}
