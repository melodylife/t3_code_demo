import Foundation

public enum StarRating {
    public static func scoreTier(score: Int, thresholds: [Int]) -> Int {
        min(3, thresholds.filter { score >= $0 }.count)
    }

    public static func campaign(score: Int,
                                thresholds: [Int],
                                objectivesCompleted: Bool) -> Int {
        guard objectivesCompleted else { return 0 }
        return max(1, scoreTier(score: score, thresholds: thresholds))
    }

    public static func nextThreshold(after score: Int, thresholds: [Int]) -> Int? {
        thresholds.sorted().first { $0 > score }
    }

    public static func nextCampaignThreshold(score: Int,
                                             thresholds: [Int],
                                             objectivesCompleted: Bool) -> Int? {
        guard objectivesCompleted else { return nextThreshold(after: score, thresholds: thresholds) }
        let earned = campaign(score: score,
                              thresholds: thresholds,
                              objectivesCompleted: true)
        let sorted = thresholds.sorted()
        guard earned < 3, earned < sorted.count else { return nil }
        return sorted[earned]
    }
}

public enum StarChasePhase: String, Codable, Sendable, Equatable {
    case playing
    case goalReached
    case starChase
    case won
    case lost

    public var canAcceptMoves: Bool {
        self == .playing || self == .starChase
    }

    public var showsFinalResult: Bool {
        self == .won || self == .lost
    }

    public var hasGuaranteedClear: Bool {
        self == .goalReached || self == .starChase || self == .won
    }
}

/// Foundation-only transition model. Call `didBeginMove()` before playback and
/// `didSettle` only after the complete cascade has been applied.
public struct StarChaseState: Sendable, Equatable {
    public private(set) var phase: StarChasePhase
    public private(set) var isSettled: Bool
    public private(set) var finishIsQueued: Bool

    public init(phase: StarChasePhase = .playing,
                isSettled: Bool = true,
                finishIsQueued: Bool = false) {
        self.phase = phase
        self.isSettled = isSettled
        self.finishIsQueued = finishIsQueued
    }

    public mutating func didBeginMove() {
        guard phase.canAcceptMoves else { return }
        isSettled = false
    }

    @discardableResult
    public mutating func didSettle(objectivesSatisfied: Bool,
                                  movesLeft: Int,
                                  stars: Int) -> StarChasePhase {
        isSettled = true

        switch phase {
        case .playing:
            if objectivesSatisfied {
                phase = (movesLeft == 0 || stars >= 3) ? .won : .goalReached
            } else if movesLeft == 0 {
                phase = .lost
            }

        case .starChase:
            if finishIsQueued || movesLeft == 0 || stars >= 3 {
                finishIsQueued = false
                phase = .won
            }

        case .goalReached, .won, .lost:
            break
        }
        return phase
    }

    @discardableResult
    public mutating func chooseStarChase(movesLeft: Int, stars: Int) -> StarChasePhase {
        guard phase == .goalReached else { return phase }
        phase = (movesLeft > 0 && stars < 3) ? .starChase : .won
        return phase
    }

    /// Finishes immediately at a settled boundary, or queues a safe finish for
    /// the next boundary if an in-flight callback races the disabled UI action.
    @discardableResult
    public mutating func requestFinish() -> StarChasePhase {
        guard phase == .goalReached || phase == .starChase else { return phase }
        if isSettled {
            finishIsQueued = false
            phase = .won
        } else {
            finishIsQueued = true
        }
        return phase
    }
}
