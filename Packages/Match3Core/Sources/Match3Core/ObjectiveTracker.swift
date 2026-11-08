import Foundation

public struct ObjectiveTracker: Sendable, Equatable {
    public private(set) var score: Int = 0
    public private(set) var collected: [Int: Int] = [:]

    public init() {}

    public mutating func apply(points: Int, cleared: [TileKind]) {
        score += points
        for kind in cleared { collected[kind.index, default: 0] += 1 }
    }

    public func count(forKind index: Int) -> Int {
        collected[index, default: 0]
    }

    public func progress(for objective: Objective) -> Double {
        let current: Int
        switch objective.type {
        case .score: current = score
        case .collect: current = count(forKind: objective.tileKind ?? 0)
        }
        guard objective.target > 0 else { return 1 }
        return min(1, Double(current) / Double(objective.target))
    }

    public func current(for objective: Objective) -> Int {
        switch objective.type {
        case .score: return score
        case .collect: return count(forKind: objective.tileKind ?? 0)
        }
    }

    public func isSatisfied(_ objectives: [Objective]) -> Bool {
        objectives.allSatisfy { current(for: $0) >= $0.target }
    }
}
