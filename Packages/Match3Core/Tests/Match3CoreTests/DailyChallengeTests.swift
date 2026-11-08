import Foundation
import XCTest
@testable import Match3Core

final class DailyChallengeTests: XCTestCase {
    private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testUTCDateBoundariesAndCapturedRetry() throws {
        let cases = [
            ("2024-02-28T23:59:59Z", "2024-02-28"),
            ("2024-02-29T00:00:00Z", "2024-02-29"),
            ("2024-03-01T00:00:00Z", "2024-03-01"),
            ("2025-01-01T00:00:00Z", "2025-01-01"),
            ("2024-03-10T01:59:59-08:00", "2024-03-10"),
            ("2024-03-10T03:00:00-07:00", "2024-03-10"),
            ("2024-11-03T01:30:00-07:00", "2024-11-03"),
            ("2024-11-03T01:30:00-08:00", "2024-11-03"),
            ("2024-01-01T00:00:00+14:00", "2023-12-31")
        ]
        for (text, date) in cases {
            XCTAssertEqual(try DailyChallenge.today(clock: { self.instant(text) }).id.date, date)
        }
        var now = instant("2024-02-29T23:59:59Z")
        let captured = try DailyChallenge.today(clock: { now })
        let configuration = GameConfiguration.daily(captured)
        now = instant("2024-03-01T00:00:00Z")
        XCTAssertNotEqual(try DailyChallenge.today(clock: { now }), captured)
        XCTAssertEqual(configuration.dailyChallenge, captured)
        XCTAssertEqual(captured.id.nextReset, now)
        now = instant("2024-02-28T00:00:00Z")
        XCTAssertEqual(try DailyChallenge.today(clock: { now }).id.date, "2024-02-28")
        XCTAssertEqual(configuration, .daily(captured))
    }

    func testUTCIdentityIgnoresDefaultTimeZone() throws {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        let now = instant("2024-12-31T23:59:59Z")
        for zone in ["Pacific/Kiritimati", "America/Los_Angeles", "Asia/Tokyo", "Europe/London"] {
            NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: zone))
            XCTAssertEqual(try DailyChallenge.today(clock: { now }).id.date, "2024-12-31")
            XCTAssertEqual(DailyChallengeID.calendar.identifier, .gregorian)
            XCTAssertEqual(DailyChallengeID.calendar.timeZone.secondsFromGMT(), 0)
        }
    }

    func testInvalidDatesAndVersionsCannotDecode() throws {
        for date in ["2023-02-29", "2024-02-30", "2024-13-01", "2024-00-01", "0000-01-01", "2024-1-01", "2024-01-1", "2024-01-01x"] {
            XCTAssertThrowsError(try DailyChallengeID(date: date))
        }
        XCTAssertThrowsError(try DailyChallengeID(date: "2024-01-01", version: 0))
        XCTAssertThrowsError(try DailyChallengeID(instant: Date(timeIntervalSince1970: .infinity)))
        let future = try DailyChallengeID(date: "2024-01-01", version: 2)
        XCTAssertThrowsError(try DailyChallenge(id: future))
        XCTAssertNotEqual(DailyChallenge.seed(for: future), DailyChallenge.seed(for: try DailyChallengeID(date: "2024-01-01")))
        let invalid = Data(#"{"date":"2023-02-29","version":1}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(DailyChallengeID.self, from: invalid))
        let valid = try DailyChallengeID(date: "2024-02-29")
        XCTAssertEqual(try JSONDecoder().decode(DailyChallengeID.self, from: JSONEncoder().encode(valid)), valid)
    }

    func testCampaignConfigurationPreservesEveryField() {
        let level = Level(id: 7, rows: 5, cols: 6, moves: 17, palette: ["a", "b", "c"],
                          objectives: [Objective(type: .collect, target: 20, tileKind: 1)],
                          starThresholds: [100, 300, 500], seed: 12345)
        let configuration = GameConfiguration.campaign(level)
        XCTAssertEqual(configuration.mode, .campaign)
        XCTAssertEqual(configuration.level, level)
        XCTAssertEqual(configuration.seed, level.seed)
        XCTAssertNil(configuration.dailyChallenge)
    }

    func testSeedAndSupportedBuildGoldens() throws {
        // Fixtures generated from current sources with Apple Swift 6.4 / Xcode 27.
        // A toolchain/generator/resolver change that alters these requires a daily
        // content version bump, not silently updating v1 expectations.
        struct Fixture {
            let date: String
            let seed: UInt64
            let initial: String
            let score: Int
            let final: String
        }
        let fixtures: [Fixture] = [
            Fixture(date: "2024-02-29", seed: 8324851845354223748,
                    initial: "5,0,5,5,0,1,1,4,5,5,0,1,1,2,0,0,3,4,3,4,1,5,1,0,2,2,1,1,3,3,2,4,5,5,2,1,1,3,0,5,2,5,2,0,0,4,4,1,1,2,1,4,1,5,1,0,5,4,2,0,3,4,2,0",
                    score: 1170,
                    final: "0,4,2,0,0,2,2,4,5,5,0,1,0,3,3,4,3,4,3,0,5,2,5,0,2,2,1,5,0,5,2,4,5,5,2,4,1,3,0,5,2,5,2,0,0,4,4,1,1,2,1,4,1,5,1,0,5,4,2,0,3,4,2,0"),
            Fixture(date: "2025-01-01", seed: 18138381358570489550,
                    initial: "1,2,1,4,2,5,2,5,0,3,1,2,3,1,4,3,3,3,5,1,0,5,5,2,2,0,4,5,0,0,2,0,4,2,5,2,3,0,5,4,5,4,5,5,3,3,5,2,4,1,3,1,0,4,1,4,5,3,4,5,3,1,4,3",
                    score: 1080,
                    final: "1,0,0,3,0,5,4,4,0,2,5,4,r2h,5,1,5,3,3,4,4,3,1,4,2,2,3,4,5,0,0,2,0,4,2,5,2,3,0,5,4,5,4,5,5,3,3,5,2,4,1,3,1,0,4,1,4,5,3,4,5,3,1,4,3"),
            Fixture(date: "2026-11-08", seed: 8622873116657369567,
                    initial: "2,1,1,5,3,3,5,5,3,4,4,2,0,0,5,1,0,1,5,3,2,5,4,2,3,5,5,0,2,0,0,1,5,0,2,1,3,0,4,3,5,0,4,2,3,2,4,2,0,5,2,5,1,1,5,3,4,2,5,5,0,1,5,4",
                    score: 1800,
                    final: "2,1,0,0,4,4,0,5,3,4,1,2,5,3,5,1,0,1,2,3,0,5,4,2,3,5,1,0,5,0,0,1,5,0,2,1,4,0,4,3,5,0,4,2,1,2,4,2,0,5,2,5,1,1,5,3,4,2,5,5,0,1,5,4")
        ]
        XCTAssertFalse(fixtures.isEmpty)
        for fixture in fixtures {
            let challenge = try DailyChallenge(id: DailyChallengeID(date: fixture.date))
            XCTAssertEqual(challenge.seed, fixture.seed)
            var rng = SplitMix64(seed: challenge.seed)
            let board = BoardGenerator.generate(rows: 8, cols: 8, paletteCount: 6, rng: &rng)
            XCTAssertEqual(fingerprint(board), fixture.initial)
            let replay = try play(challenge, objectiveAware: false, turns: 5)
            XCTAssertEqual(replay.score, fixture.score)
            XCTAssertEqual(fingerprint(replay.board), fixture.final)
        }
    }

    func testSharePayloadIsSpoilerFreeAndValidatesSettledCounters() throws {
        let challenge = try DailyChallenge(id: DailyChallengeID(date: "2024-02-29"))
        let result = try XCTUnwrap(DailyShareResult(challenge: challenge, completed: true, score: 2500, movesUsed: 17))
        XCTAssertEqual(result.text, "EmojiMatch Daily Puzzle • 2024-02-29 UTC • v1\nComplete • Score: 2500 • Moves used: 17/20")
        XCTAssertFalse(result.text.contains(String(challenge.seed)))
        XCTAssertFalse(result.text.contains("🍎"))
        XCTAssertNil(DailyShareResult(challenge: challenge, completed: true, score: 1499, movesUsed: 10))
        XCTAssertNil(DailyShareResult(challenge: challenge, completed: true, score: 1500, movesUsed: 0))
        XCTAssertNil(DailyShareResult(challenge: challenge, completed: false, score: -1, movesUsed: 1))
        XCTAssertNil(DailyShareResult(challenge: challenge, completed: false, score: 0, movesUsed: 21))
        XCTAssertTrue(try XCTUnwrap(DailyShareResult(challenge: challenge, completed: false, score: 300, movesUsed: 20)).text.contains("Not completed"))
    }

    func testDateCorpusStableReplayAndBothStrategies() throws {
        let start = instant("2024-01-01T00:00:00Z")
        for offset in 0..<366 {
            let date = DailyChallengeID.calendar.date(byAdding: .day, value: offset, to: start)!
            let challenge = try DailyChallenge.today(clock: { date })
            for aware in [false, true] {
                let first = try play(challenge, objectiveAware: aware, turns: challenge.level.moves)
                let second = try play(challenge, objectiveAware: aware, turns: challenge.level.moves)
                XCTAssertEqual(first.board, second.board, "\(challenge.id) aware=\(aware)")
                XCTAssertEqual(first.score, second.score)
            }
        }
    }

    private func play(_ challenge: DailyChallenge, objectiveAware: Bool, turns: Int) throws -> (board: Board, score: Int) {
        let level = challenge.level
        var rng = SplitMix64(seed: challenge.seed)
        var board = BoardGenerator.generate(rows: level.rows, cols: level.cols, paletteCount: level.paletteCount, rng: &rng)
        XCTAssertTrue(MatchDetector.groups(in: board).isEmpty)
        XCTAssertTrue(Resolver.hasAnyMove(board))
        var score = 0
        for _ in 0..<turns {
            let pair = try XCTUnwrap(objectiveAware ? scoreGoalMove(board) : Resolver.firstAvailableMove(board))
            let resolution = Resolver.resolveSwap(board, pair.0, pair.1, paletteCount: level.paletteCount, rng: &rng)
            XCTAssertTrue(resolution.wasAccepted)
            XCTAssertFalse(resolution.hitStepCap)
            var animated = board
            for step in resolution.steps { step.apply(to: &animated) }
            XCTAssertEqual(animated, resolution.finalBoard)
            board = resolution.finalBoard
            score += resolution.totalPoints
            XCTAssertTrue(MatchDetector.groups(in: board).isEmpty)
            XCTAssertTrue(Resolver.hasAnyMove(board))
        }
        return (board, score)
    }

    /// Score-objective heuristic: prefer more immediately matched cells, with
    /// stable row-major ties. No future refills or alternate RNG simulations.
    /// This is test strategy coverage, not a solver or human-balance claim.
    private func scoreGoalMove(_ board: Board) -> (Cell, Cell)? {
        var best: (Cell, Cell)?
        var bestCount = -1
        for cell in board.cells {
            for next in [cell.offset(row: 0, col: 1), cell.offset(row: 1, col: 0)] {
                guard Resolver.isAcceptedSwap(board, cell, next) else { continue }
                var probe = board
                probe.swap(cell, next)
                let count = Set(MatchDetector.groups(in: probe).flatMap(\.cells)).count
                if count > bestCount { best = (cell, next); bestCount = count }
            }
        }
        return best
    }

    private func fingerprint(_ board: Board) -> String {
        board.tiles.map { tile in
            guard let tile else { return "." }
            switch tile {
            case .normal(let kind): return String(kind.index)
            case .rocket(let kind, let axis): return "r\(kind.index)\(axis == .horizontal ? "h" : "v")"
            case .bomb(let kind): return "b\(kind.index)"
            case .rainbow: return "*"
            }
        }.joined(separator: ",")
    }
}
