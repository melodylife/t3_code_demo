import Foundation

public enum DailyChallengeError: Error, Equatable {
    case invalidDate
    case unsupportedVersion(Int)
}

/// A civil Gregorian date in UTC, independent of the device's calendar and zone.
public struct DailyChallengeID: Hashable, Codable, Sendable, Comparable {
    public let date: String
    public let version: Int

    public init(date: String, version: Int = DailyChallenge.currentVersion) throws {
        guard version > 0 else { throw DailyChallengeError.unsupportedVersion(version) }
        let parts = date.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              date.utf8.allSatisfy({ (48...57).contains($0) || $0 == 45 }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let instant = Self.calendar.date(from: DateComponents(year: year, month: month, day: day)),
              Self.calendar.component(.year, from: instant) == year,
              Self.calendar.component(.month, from: instant) == month,
              Self.calendar.component(.day, from: instant) == day else {
            throw DailyChallengeError.invalidDate
        }
        self.date = date
        self.version = version
    }

    public init(instant: Date, version: Int = DailyChallenge.currentVersion) throws {
        guard instant.timeIntervalSince1970.isFinite else { throw DailyChallengeError.invalidDate }
        let parts = Self.calendar.dateComponents([.era, .year, .month, .day], from: instant)
        guard parts.era == 1, let year = parts.year, let month = parts.month, let day = parts.day else {
            throw DailyChallengeError.invalidDate
        }
        try self.init(date: String(format: "%04d-%02d-%02d", year, month, day), version: version)
    }

    public static var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        result.locale = Locale(identifier: "en_US_POSIX")
        return result
    }

    public var nextReset: Date {
        let parts = date.split(separator: "-").map { Int($0)! }
        let midnight = Self.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
        return Self.calendar.date(byAdding: .day, value: 1, to: midnight)!
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.date == rhs.date ? lhs.version < rhs.version : lhs.date < rhs.date
    }

    private enum CodingKeys: String, CodingKey { case date, version }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(date: values.decode(String.self, forKey: .date), version: values.decode(Int.self, forKey: .version))
    }
}

/// Immutable launch capture. Retry this value, not `today()`, across UTC reset.
public struct DailyChallenge: Equatable, Sendable, Identifiable {
    public static let currentVersion = 1
    public let id: DailyChallengeID
    public let seed: UInt64

    public init(id: DailyChallengeID) throws {
        guard id.version == Self.currentVersion else { throw DailyChallengeError.unsupportedVersion(id.version) }
        self.id = id
        seed = Self.seed(for: id)
    }

    public static func today(clock: () -> Date = Date.init) throws -> Self {
        try Self(id: DailyChallengeID(instant: clock()))
    }

    /// FNV-1a-64 over UTF-8 "EmojiMatch/daily/v<decimal-version>/<YYYY-MM-DD>".
    /// Offset 14695981039346656037, prime 1099511628211, wrapping multiplication.
    /// This mapping is portable; generator/resolver stdlib sampling is NOT promised
    /// portable. See GameConfiguration's integration notes before toolchain changes.
    public static func seed(for id: DailyChallengeID) -> UInt64 {
        "EmojiMatch/daily/v\(id.version)/\(id.date)".utf8.reduce(14_695_981_039_346_656_037) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
    }

    /// Engine adapter only: id 0 is not a campaign identity. Always route saves by
    /// GameConfiguration.mode, NEVER this adapter's id. No daily catalog entry exists.
    public var level: Level {
        Level(id: 0, rows: 8, cols: 8, moves: 20,
              palette: ["🍎", "🍋", "🍇", "🍊", "🍒", "🥝"],
              objectives: [Objective(type: .score, target: 1500)],
              starThresholds: [1500, 2500, 4000], seed: seed)
    }
}
