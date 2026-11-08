import Foundation

public struct Objective: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case score
        case collect
    }

    public let type: Kind
    public let target: Int
    /// Required when `type == .collect`.
    public let tileKind: Int?

    public init(type: Kind, target: Int, tileKind: Int? = nil) {
        self.type = type
        self.target = target
        self.tileKind = tileKind
    }
}

public struct Level: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let rows: Int
    public let cols: Int
    public let moves: Int
    /// Emoji strings. The core only counts them; the UI renders them.
    public let palette: [String]
    public let objectives: [Objective]
    public let starThresholds: [Int]
    public let seed: UInt64

    public init(id: Int,
                rows: Int,
                cols: Int,
                moves: Int,
                palette: [String],
                objectives: [Objective],
                starThresholds: [Int],
                seed: UInt64) {
        self.id = id
        self.rows = rows
        self.cols = cols
        self.moves = moves
        self.palette = palette
        self.objectives = objectives
        self.starThresholds = starThresholds
        self.seed = seed
    }

    public var paletteCount: Int { palette.count }

    public func stars(for score: Int) -> Int {
        StarRating.scoreTier(score: score, thresholds: starThresholds)
    }

    /// Stars shown for a campaign result. A completed campaign level always
    /// earns at least one star; an incomplete attempt never earns stars.
    public func campaignStars(for score: Int, objectivesCompleted: Bool) -> Int {
        StarRating.campaign(score: score,
                            thresholds: starThresholds,
                            objectivesCompleted: objectivesCompleted)
    }
}
