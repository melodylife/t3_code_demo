import Foundation
import XCTest
@testable import Match3Core

final class CampaignProgressTests: XCTestCase {
    private struct LegacyProgress: Codable {
        var unlockedLevel: Int
        var stars: [Int: Int]
        var bestScores: [Int: Int]
    }

    private enum TestFailure: Error {
        case write
    }

    func testLegacyMigrationInfersOnlyProvableCompletions() throws {
        let url = try temporaryProgressURL()
        let legacy = LegacyProgress(unlockedLevel: 4,
                                    stars: [1: 1, 3: 2],
                                    bestScores: [1: 120, 3: 450, 4: 20])
        try JSONEncoder().encode(legacy).write(to: url)

        let store = CampaignProgressStore(url: url)

        XCTAssertEqual(store.data.version, CampaignProgress.currentVersion)
        XCTAssertEqual(store.data.completedLevelIDs, [1, 2, 3])
        XCTAssertFalse(store.data.isCompleted(levelID: 4),
                       "A legacy zero-star clear of the final unlocked level cannot be proven")
        XCTAssertEqual(store.data.bestScores[4], 20)
        XCTAssertEqual(store.data.unlockedLevel, 4)
    }

    func testDuplicateAndLowerResultsAreMonotonic() throws {
        let url = try temporaryProgressURL()
        let store = CampaignProgressStore(url: url)

        XCTAssertNoThrow(try store.record(levelID: 1,
                                          score: 500,
                                          stars: 2,
                                          unlockedLevel: 2,
                                          completed: true).get())
        XCTAssertNoThrow(try store.record(levelID: 1,
                                          score: 100,
                                          stars: 1,
                                          unlockedLevel: 2,
                                          completed: true).get())
        XCTAssertNoThrow(try store.record(levelID: 1,
                                          score: 500,
                                          stars: 2,
                                          unlockedLevel: 2,
                                          completed: true).get())

        XCTAssertEqual(store.data.bestScores[1], 500)
        XCTAssertEqual(store.data.stars[1], 2)
        XCTAssertEqual(store.data.completedLevelIDs, [1])
        XCTAssertEqual(store.data.unlockedLevel, 2)

        let reloaded = CampaignProgressStore(url: url)
        XCTAssertEqual(reloaded.data, store.data)
    }

    func testCompletedResultPersistsAtLeastOneStar() throws {
        let store = CampaignProgressStore(url: try temporaryProgressURL())

        _ = store.record(levelID: 1,
                         score: 10,
                         stars: 0,
                         unlockedLevel: 2,
                         completed: true)

        XCTAssertEqual(store.data.stars[1], 1)
        XCTAssertTrue(store.data.isCompleted(levelID: 1))
    }

    func testIncompleteResultCannotUnlockOrEarnStars() throws {
        let store = CampaignProgressStore(url: try temporaryProgressURL())

        _ = store.record(levelID: 1,
                         score: 999,
                         stars: 3,
                         unlockedLevel: 10,
                         completed: false)

        XCTAssertEqual(store.data.unlockedLevel, 1)
        XCTAssertEqual(store.data.stars[1], 0)
        XCTAssertFalse(store.data.isCompleted(levelID: 1))
    }

    func testWriteFailureKeepsInMemoryProgressAndReportsError() throws {
        let url = try temporaryProgressURL()
        let store = CampaignProgressStore(url: url,
                                          fileManager: .default) { _, _ in
            throw TestFailure.write
        }

        let result = store.record(levelID: 1,
                                  score: 150,
                                  stars: 1,
                                  unlockedLevel: 2,
                                  completed: true)

        guard case .failure(.writeFailed) = result else {
            return XCTFail("Expected an injectable write failure")
        }
        XCTAssertEqual(store.data.bestScores[1], 150)
        XCTAssertTrue(store.data.isCompleted(levelID: 1))
        XCTAssertNotNil(store.lastError)
    }

    func testCorruptSaveFallsBackAndReportsLoadFailure() throws {
        let url = try temporaryProgressURL()
        try Data("not json".utf8).write(to: url)

        let store = CampaignProgressStore(url: url)

        XCTAssertEqual(store.data, .empty)
        guard case .loadFailed = store.lastError else {
            return XCTFail("Expected corrupt data to be reported")
        }
    }

    func testContinueSelectsUnlockedUncompletedLevel() {
        let progress = CampaignProgress(unlockedLevel: 4,
                                        completedLevelIDs: [1, 3])

        XCTAssertEqual(progress.nextUncompletedLevelID(from: [1, 2, 3, 4, 5]), 2)
        XCTAssertNil(CampaignProgress(unlockedLevel: 3,
                                      completedLevelIDs: [1, 2, 3])
            .nextUncompletedLevelID(from: [1, 2, 3, 4]))
    }

    private func temporaryProgressURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CampaignProgressTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("progress.json")
    }
}
