import Foundation

public struct DailyRecord: Codable, Equatable, Sendable {
    public let id: DailyChallengeID
    public let completed: Bool
    public let bestCompletedScore: Int?
    public let movesUsed: Int?

    fileprivate var isValid: Bool {
        // v1 records must fit the shipped budget/goal. Unknown positive content
        // versions may coexist, but aren't interpreted using v1's rules.
        if completed {
            guard let score = bestCompletedScore, let moves = movesUsed,
                  score >= 0, moves > 0 else { return false }
            return id.version != 1 || (score >= 1500 && moves <= 20)
        }
        return bestCompletedScore == nil && movesUsed == nil
    }
}

public enum DailyStoreWarning: Equatable, Sendable {
    case unreadableFile
    case malformedRecords
    case unsupportedSchema
    case writeFailed
}

/// Separate, bounded, offline JSON store. Call from a single owner (the app uses
/// MainActor). Atomic replacement prevents partial files; concurrent multi-writer
/// merging and mid-board resume are intentionally unsupported.
public final class DailyChallengeStore {
    public static let schemaVersion = 1
    public static let maximumRecords = 90
    public private(set) var records: [DailyRecord] = []
    public private(set) var warning: DailyStoreWarning?
    public let url: URL
    private var preservesUnknownSchema = false

    private struct Envelope: Codable {
        let schemaVersion: Int
        let records: [DailyRecord]
    }

    private struct LossyRecord: Decodable {
        let value: DailyRecord?
        init(from decoder: Decoder) throws { value = try? DailyRecord(from: decoder) }
    }

    private struct ReadEnvelope: Decodable {
        let schemaVersion: Int
        let records: [LossyRecord]
    }

    public init(url: URL) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let raw = try Data(contentsOf: url)
            // Read the schema first so a future envelope cannot be accidentally
            // replaced merely because its record shape changed.
            struct Header: Decodable { let schemaVersion: Int }
            let header = try JSONDecoder().decode(Header.self, from: raw)
            guard header.schemaVersion == Self.schemaVersion else {
                preservesUnknownSchema = true
                warning = .unsupportedSchema
                return
            }
            let decoded = try JSONDecoder().decode(ReadEnvelope.self, from: raw)
            for entry in decoded.records {
                guard let record = entry.value, record.isValid else {
                    warning = .malformedRecords
                    continue
                }
                merge(record)
            }
            prune()
        } catch {
            warning = .unreadableFile
        }
    }

    public func record(for id: DailyChallengeID) -> DailyRecord? {
        records.first { $0.id == id }
    }

    /// Settled completed outcomes only establish best scores. Failed attempts
    /// may mark a date played, never downgrade a clear. Ties prefer fewer moves;
    /// lower-scoring runs never donate their move count to the best run.
    /// Returns false on save failure; in-memory results remain usable and a
    /// duplicate call retries the atomic write (do not imply disk durability).
    @discardableResult
    public func record(_ result: DailyShareResult) -> Bool {
        guard !preservesUnknownSchema else { return false }
        merge(DailyRecord(id: result.challenge.id, completed: result.completed,
                          bestCompletedScore: result.completed ? result.score : nil,
                          movesUsed: result.completed ? result.movesUsed : nil))
        prune()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(Envelope(schemaVersion: Self.schemaVersion, records: records)).write(to: url, options: .atomic)
            warning = nil
            return true
        } catch {
            warning = .writeFailed
            return false
        }
    }

    private func merge(_ incoming: DailyRecord) {
        guard let index = records.firstIndex(where: { $0.id == incoming.id }) else {
            records.append(incoming)
            return
        }
        let existing = records[index]
        guard incoming.completed else { return }
        if !existing.completed || incoming.bestCompletedScore! > existing.bestCompletedScore!
            || (incoming.bestCompletedScore == existing.bestCompletedScore && incoming.movesUsed! < existing.movesUsed!) {
            records[index] = incoming
        }
    }

    private func prune() {
        // Civil-date order, never insertion order or wall-clock-relative expiry.
        // Rollback and delayed results cannot evict a newer retained date.
        records.sort { $0.id > $1.id }
        records = Array(records.prefix(Self.maximumRecords))
    }
}
