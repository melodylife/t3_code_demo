import Foundation
import XCTest
@testable import Match3Core

final class DailyChallengeStoreTests: XCTestCase {
    private var directory: URL!
    private var url: URL { directory.appendingPathComponent("daily.json") }

    override func setUpWithError() throws {
        // Optional test-only root for restricted CI; production always injects its
        // own store URL. No dependency on a developer-specific absolute path.
        let root = ProcessInfo.processInfo.environment["DAILY_TEST_TMPDIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        directory = root.appendingPathComponent("DailyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func result(_ date: String = "2024-02-29", score: Int = 2000, moves: Int = 12, completed: Bool = true) throws -> DailyShareResult {
        let challenge = try DailyChallenge(id: DailyChallengeID(date: date))
        return try XCTUnwrap(DailyShareResult(challenge: challenge, completed: completed, score: score, movesUsed: moves))
    }

    func testMonotonicBestAndBestRunMoveAssociationAcrossRelaunch() throws {
        let store = DailyChallengeStore(url: url)
        let first = try result()
        XCTAssertTrue(store.record(first))
        let bytes = try Data(contentsOf: url)
        XCTAssertTrue(store.record(first))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertTrue(store.record(try result(score: 1700, moves: 4)))
        XCTAssertEqual(store.record(for: first.challenge.id)?.movesUsed, 12)
        XCTAssertTrue(store.record(try result(score: 0, moves: 20, completed: false)))
        XCTAssertEqual(store.record(for: first.challenge.id)?.bestCompletedScore, 2000)
        XCTAssertTrue(store.record(try result(score: 2000, moves: 10)))
        XCTAssertEqual(store.record(for: first.challenge.id)?.movesUsed, 10)
        XCTAssertTrue(store.record(try result(score: 2300, moves: 19)))
        let reopened = DailyChallengeStore(url: url)
        XCTAssertNil(reopened.warning)
        XCTAssertEqual(reopened.records.count, 1)
        XCTAssertEqual(reopened.records.first?.bestCompletedScore, 2300)
        XCTAssertEqual(reopened.records.first?.movesUsed, 19)
        XCTAssertTrue(reopened.records.first!.completed)
    }

    func testInMemoryMonotonicitySurvivesUnavailableDisk() throws {
        let store = DailyChallengeStore(url: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let first = try result()
        XCTAssertFalse(store.record(first))
        XCTAssertFalse(store.record(try result(score: 1700, moves: 3)))
        XCTAssertEqual(store.record(for: first.challenge.id)?.bestCompletedScore, 2000)
        XCTAssertEqual(store.record(for: first.challenge.id)?.movesUsed, 12)
        XCTAssertFalse(store.record(try result(score: 2000, moves: 10)))
        XCTAssertEqual(store.record(for: first.challenge.id)?.movesUsed, 10)
        XCTAssertFalse(store.record(try result(score: 2300, moves: 19)))
        XCTAssertFalse(store.record(try result(score: 0, moves: 20, completed: false)))
        XCTAssertEqual(store.record(for: first.challenge.id)?.bestCompletedScore, 2300)
        XCTAssertEqual(store.record(for: first.challenge.id)?.movesUsed, 19)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.warning, .writeFailed)
    }

    func testRetentionRemainsBoundedWhenDiskUnavailable() throws {
        let store = DailyChallengeStore(url: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let start = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!
        for offset in (0..<120).reversed() {
            let date = DailyChallengeID.calendar.date(byAdding: .day, value: offset, to: start)!
            let id = try DailyChallengeID(instant: date)
            XCTAssertFalse(store.record(try result(id.date)))
        }
        XCTAssertEqual(store.records.count, 90)
        XCTAssertEqual(store.records.first?.id.date, "2024-04-29")
        XCTAssertEqual(store.records.last?.id.date, "2024-01-31")
    }

    func testFailedAttemptNeverClaimsCompletionOrBest() throws {
        let store = DailyChallengeStore(url: url)
        XCTAssertTrue(store.record(try result(score: 300, moves: 20, completed: false)))
        let entry = try XCTUnwrap(DailyChallengeStore(url: url).records.first)
        XCTAssertFalse(entry.completed)
        XCTAssertNil(entry.bestCompletedScore)
        XCTAssertNil(entry.movesUsed)
    }

    func testRetentionUsesCivilDatesNotArrivalOrClockOrder() throws {
        let store = DailyChallengeStore(url: url)
        let start = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!
        // Insert newer dates first; delayed and rollback results must not evict them.
        for offset in (0..<120).reversed() {
            let instant = DailyChallengeID.calendar.date(byAdding: .day, value: offset, to: start)!
            let challenge = try DailyChallenge.today(clock: { instant })
            let outcome = try XCTUnwrap(DailyShareResult(challenge: challenge, completed: true, score: 2000, movesUsed: 10))
            XCTAssertTrue(store.record(outcome))
        }
        XCTAssertEqual(store.records.count, 90)
        XCTAssertEqual(store.records.first?.id.date, "2024-04-29")
        XCTAssertEqual(store.records.last?.id.date, "2024-01-31")
        let before = store.records
        XCTAssertTrue(store.record(try result("2023-01-01")))
        XCTAssertEqual(store.records, before)
        XCTAssertEqual(DailyChallengeStore(url: url).records, before)
    }

    func testMalformedIndividualRecordsAndDuplicateOrderAreSanitized() throws {
        let raw = #"""
        {"schemaVersion":1,"records":[
          {"id":{"date":"2024-02-29","version":1},"completed":true,"bestCompletedScore":2400,"movesUsed":18},
          {"id":{"date":"2024-02-29","version":1},"completed":true,"bestCompletedScore":1700,"movesUsed":3},
          {"id":{"date":"2024-02-29","version":2},"completed":false},
          {"id":{"date":"2023-02-29","version":1},"completed":false},
          {"id":{"date":"2024-03-01","version":1},"completed":true,"bestCompletedScore":10,"movesUsed":25},
          {"id":{"date":"2024-03-02","version":1},"completed":false,"bestCompletedScore":100},
          null,{}
        ]}
        """#
        try Data(raw.utf8).write(to: url)
        let store = DailyChallengeStore(url: url)
        XCTAssertEqual(store.warning, .malformedRecords)
        XCTAssertEqual(store.records.count, 2)
        let current = try DailyChallengeID(date: "2024-02-29")
        XCTAssertEqual(store.record(for: current)?.bestCompletedScore, 2400)
        XCTAssertEqual(store.record(for: current)?.movesUsed, 18)
        XCTAssertTrue(store.record(try result(score: 2600, moves: 20)))
        XCTAssertNil(store.warning)
        XCTAssertEqual(DailyChallengeStore(url: url).records.count, 2)
    }

    func testUnknownOldAndFutureSchemaIsPreservedRatherThanOverwritten() throws {
        for version in [0, 2] {
            let raw = Data("{\"schemaVersion\":\(version),\"futureRecordShape\":true}".utf8)
            try raw.write(to: url)
            let store = DailyChallengeStore(url: url)
            XCTAssertEqual(store.warning, .unsupportedSchema)
            XCTAssertFalse(store.record(try result()))
            XCTAssertEqual(try Data(contentsOf: url), raw)
        }
    }

    func testCorruptAndUnversionedFilesRecoverWithoutCampaignWrites() throws {
        let campaign = directory.appendingPathComponent("progress.json")
        let untouched = Data("campaign sentinel".utf8)
        try untouched.write(to: campaign)
        for raw in ["garbage", "{}", #"{"records":[]}"#] {
            try Data(raw.utf8).write(to: url)
            let store = DailyChallengeStore(url: url)
            XCTAssertEqual(store.warning, .unreadableFile)
            XCTAssertTrue(store.records.isEmpty)
            XCTAssertTrue(store.record(try result()))
            XCTAssertNil(store.warning)
            XCTAssertEqual(try Data(contentsOf: campaign), untouched)
        }
    }

    func testAtomicFailureSurfacesWarningAndDuplicateCanRetry() throws {
        let store = DailyChallengeStore(url: url)
        // Force the target to be a directory. Atomic file replacement must fail.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertFalse(store.record(try result()))
        XCTAssertEqual(store.warning, .writeFailed)
        XCTAssertEqual(store.records.count, 1)
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(store.record(try result()))
        XCTAssertNil(store.warning)
        XCTAssertEqual(DailyChallengeStore(url: url).records, store.records)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["daily.json"])
    }
}
