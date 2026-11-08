import Foundation

public struct CampaignProgress: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var unlockedLevel: Int
    public var stars: [Int: Int]
    public var bestScores: [Int: Int]
    public var completedLevelIDs: Set<Int>

    public init(version: Int = Self.currentVersion,
                unlockedLevel: Int = 1,
                stars: [Int: Int] = [:],
                bestScores: [Int: Int] = [:],
                completedLevelIDs: Set<Int> = []) {
        self.version = version
        self.unlockedLevel = max(1, unlockedLevel)
        self.stars = stars
        self.bestScores = bestScores
        self.completedLevelIDs = completedLevelIDs
    }

    public static let empty = CampaignProgress()

    public func isCompleted(levelID: Int) -> Bool {
        completedLevelIDs.contains(levelID)
    }

    public func nextUncompletedLevelID(from levelIDs: [Int]) -> Int? {
        levelIDs.first { $0 <= unlockedLevel && !completedLevelIDs.contains($0) }
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case unlockedLevel
        case stars
        case bestScores
        case completedLevelIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        unlockedLevel = max(1, try container.decodeIfPresent(Int.self, forKey: .unlockedLevel) ?? 1)
        stars = try container.decodeIfPresent([Int: Int].self, forKey: .stars) ?? [:]
        bestScores = try container.decodeIfPresent([Int: Int].self, forKey: .bestScores) ?? [:]

        if let explicit = try container.decodeIfPresent(Set<Int>.self, forKey: .completedLevelIDs) {
            completedLevelIDs = explicit
        } else {
            // Legacy saves used stars and unlock position as implicit evidence.
            // They cannot prove a zero-star clear of the final unlocked level.
            let starred = Set(stars.compactMap { $0.value > 0 ? $0.key : nil })
            let previouslyUnlocked = Set(1..<unlockedLevel)
            completedLevelIDs = starred.union(previouslyUnlocked)
        }
        version = Self.currentVersion
    }
}

public enum CampaignProgressStoreError: Error, Equatable, Sendable {
    case directoryCreationFailed(String)
    case loadFailed(String)
    case encodingFailed(String)
    case writeFailed(String)

    public var message: String {
        switch self {
        case let .directoryCreationFailed(message),
             let .loadFailed(message),
             let .encodingFailed(message),
             let .writeFailed(message):
            return message
        }
    }
}

public final class CampaignProgressStore {
    public private(set) var data: CampaignProgress
    public private(set) var lastError: CampaignProgressStoreError?

    private let url: URL
    private let writeData: (Data, URL) throws -> Void

    public convenience init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support
            .appendingPathComponent("EmojiMatch", isDirectory: true)
            .appendingPathComponent("progress.json")
        self.init(url: url, fileManager: fileManager)
    }

    public convenience init(url: URL, fileManager: FileManager = .default) {
        self.init(url: url, fileManager: fileManager) { data, destination in
            try data.write(to: destination, options: .atomic)
        }
    }

    init(url: URL,
         fileManager: FileManager,
         writeData: @escaping (Data, URL) throws -> Void) {
        self.url = url
        self.writeData = writeData

        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
        } catch {
            data = .empty
            lastError = .directoryCreationFailed(error.localizedDescription)
            return
        }

        guard fileManager.fileExists(atPath: url.path) else {
            data = .empty
            return
        }

        do {
            let raw = try Data(contentsOf: url)
            data = try JSONDecoder().decode(CampaignProgress.self, from: raw)
        } catch {
            data = .empty
            lastError = .loadFailed(error.localizedDescription)
        }
    }

    /// Updates memory before attempting disk persistence so a filesystem error
    /// cannot interrupt or roll back the active session.
    @discardableResult
    public func record(levelID: Int,
                       score: Int,
                       stars: Int,
                       unlockedLevel: Int,
                       completed: Bool) -> Result<Void, CampaignProgressStoreError> {
        var next = data
        next.version = CampaignProgress.currentVersion
        next.stars[levelID] = max(next.stars[levelID] ?? 0,
                                  completed ? max(1, stars) : 0)
        next.bestScores[levelID] = max(next.bestScores[levelID] ?? 0, score)
        if completed {
            next.unlockedLevel = max(next.unlockedLevel, unlockedLevel)
            next.completedLevelIDs.insert(levelID)
        }
        data = next

        let raw: Data
        do {
            raw = try JSONEncoder().encode(data)
        } catch {
            let failure = CampaignProgressStoreError.encodingFailed(error.localizedDescription)
            lastError = failure
            return .failure(failure)
        }

        do {
            try writeData(raw, url)
            lastError = nil
            return .success(())
        } catch {
            let failure = CampaignProgressStoreError.writeFailed(error.localizedDescription)
            lastError = failure
            return .failure(failure)
        }
    }
}
