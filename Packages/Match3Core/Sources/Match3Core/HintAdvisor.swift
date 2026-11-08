import Foundation

public enum HintReason: Equatable, Sendable, CustomStringConvertible {
    /// Contributes directly to an unmet collection objective for the specified fruit kind.
    case collectObjective(kind: TileKind, clearedCount: Int)
    /// Spawns a special tile (rocket, bomb, or rainbow).
    case createSpecial(special: Tile)
    /// Activates one or more existing specials (rainbow swap, rocket/bomb detonation, combo).
    case activateSpecial
    /// Standard match-3 without special activation or objective progress.
    case standardMatch(clearedCount: Int)

    public var description: String {
        switch self {
        case let .collectObjective(kind, count):
            return "collectObjective(kind: \(kind.index), count: \(count))"
        case let .createSpecial(special):
            return "createSpecial(\(special))"
        case .activateSpecial:
            return "activateSpecial"
        case let .standardMatch(count):
            return "standardMatch(count: \(count))"
        }
    }
}

public struct HintSuggestion: Equatable, Sendable {
    public let from: Cell
    public let to: Cell
    public let reason: HintReason
    public let clearedCount: Int
    public let createdSpecial: Tile?
    public let activatesSpecial: Bool
    public let contributesToObjective: Bool

    public init(from: Cell,
                to: Cell,
                reason: HintReason,
                clearedCount: Int = 0,
                createdSpecial: Tile? = nil,
                activatesSpecial: Bool = false,
                contributesToObjective: Bool = false) {
        self.from = from
        self.to = to
        self.reason = reason
        self.clearedCount = clearedCount
        self.createdSpecial = createdSpecial
        self.activatesSpecial = activatesSpecial
        self.contributesToObjective = contributesToObjective
    }
}

public enum HintAdvisor {

    private struct Candidate {
        let from: Cell
        let to: Cell
        let evaluation: InitialClearEvaluation
        let unmetProgress: Int
        let specialScore: Int

        init(from: Cell, to: Cell, evaluation: InitialClearEvaluation, unmetCollectionKinds: Set<TileKind>) {
            self.from = from
            self.to = to
            self.evaluation = evaluation

            var progress = 0
            for kind in unmetCollectionKinds {
                progress += evaluation.clearedKinds[kind, default: 0]
            }
            self.unmetProgress = progress

            // Score specials: rainbow (4) > bomb (3) > rocket (2) > activating existing special (1)
            var score = 0
            for spawn in evaluation.spawnedSpecials {
                switch spawn.tile {
                case .rainbow:
                    score = max(score, 4)
                case .bomb:
                    score = max(score, 3)
                case .rocket:
                    score = max(score, 2)
                case .normal:
                    break
                }
            }
            if score == 0 && evaluation.activatesExistingSpecial {
                score = 1
            }
            self.specialScore = score
        }
    }

    /// Evaluates all legal moves on the board and suggests the highest-priority move.
    ///
    /// Ranking hierarchy:
    /// 1. Immediate progress on unmet collection goals (higher cleared count for unmet goals ranks first)
    /// 2. Special tile creation or activation (rainbow > bomb > rocket > detonation)
    /// 3. Immediate clear potential (total tiles cleared in step 1)
    /// 4. Stable cell order tie-break (row-major canonical order)
    ///
    /// Never peeks at future refills or RNG. Deterministic for identical board states.
    public static func suggest(board: Board,
                               unmetCollectionKinds: Set<TileKind> = []) -> HintSuggestion? {
        var candidates: [Candidate] = []

        for row in 0..<board.rows {
            for col in 0..<board.cols {
                let cell = Cell(row: row, col: col)
                guard board[cell] != nil else { continue }

                // Right and Down neighbors form canonical adjacent pairs
                for delta in [Cell(row: 0, col: 1), Cell(row: 1, col: 0)] {
                    let other = cell.offset(row: delta.row, col: delta.col)
                    guard board.contains(other), board[other] != nil else { continue }
                    guard Resolver.isAcceptedSwap(board, cell, other) else { continue }
                    guard let evaluation = Resolver.evaluateInitialClear(board, cell, other) else { continue }

                    candidates.append(Candidate(from: cell,
                                                to: other,
                                                evaluation: evaluation,
                                                unmetCollectionKinds: unmetCollectionKinds))
                }
            }
        }

        guard !candidates.isEmpty else { return nil }

        // Find the best candidate according to ranking criteria
        let best = candidates.min { lhs, rhs in
            // Higher unmet progress wins
            if lhs.unmetProgress != rhs.unmetProgress {
                return lhs.unmetProgress > rhs.unmetProgress
            }
            // Higher special score wins
            if lhs.specialScore != rhs.specialScore {
                return lhs.specialScore > rhs.specialScore
            }
            // Higher total cleared tiles wins
            if lhs.evaluation.clearedCells.count != rhs.evaluation.clearedCells.count {
                return lhs.evaluation.clearedCells.count > rhs.evaluation.clearedCells.count
            }
            // Deterministic stable coordinate tie-break
            if lhs.from != rhs.from {
                return (lhs.from.row, lhs.from.col) < (rhs.from.row, rhs.from.col)
            }
            return (lhs.to.row, lhs.to.col) < (rhs.to.row, rhs.to.col)
        }!

        let reason: HintReason
        let createdSpecial = best.evaluation.spawnedSpecials.first?.tile

        if best.unmetProgress > 0 {
            // Find the unmet kind with the most cleared tiles in this move
            let matchingKinds = unmetCollectionKinds.filter { (best.evaluation.clearedKinds[$0] ?? 0) > 0 }
            let primaryKind = matchingKinds.max {
                (best.evaluation.clearedKinds[$0] ?? 0) < (best.evaluation.clearedKinds[$1] ?? 0)
            } ?? matchingKinds.first!
            let count = best.evaluation.clearedKinds[primaryKind, default: 0]
            reason = .collectObjective(kind: primaryKind, clearedCount: count)
        } else if let special = createdSpecial {
            reason = .createSpecial(special: special)
        } else if best.evaluation.activatesExistingSpecial {
            reason = .activateSpecial
        } else {
            reason = .standardMatch(clearedCount: best.evaluation.clearedCells.count)
        }

        return HintSuggestion(
            from: best.from,
            to: best.to,
            reason: reason,
            clearedCount: best.evaluation.clearedCells.count,
            createdSpecial: createdSpecial,
            activatesSpecial: best.evaluation.activatesExistingSpecial,
            contributesToObjective: best.unmetProgress > 0
        )
    }

    /// Overload that computes unmet collection kinds from objectives and tracker.
    public static func suggest(board: Board,
                               objectives: [Objective],
                               tracker: ObjectiveTracker) -> HintSuggestion? {
        var unmet = Set<TileKind>()
        for obj in objectives where obj.type == .collect {
            if let index = obj.tileKind, tracker.current(for: obj) < obj.target {
                unmet.insert(TileKind(index))
            }
        }
        return suggest(board: board, unmetCollectionKinds: unmet)
    }

    /// Overload for objectives array when tracker is at initial state or already filtered.
    public static func suggest(board: Board,
                               unmetObjectives: [Objective]) -> HintSuggestion? {
        var unmet = Set<TileKind>()
        for obj in unmetObjectives where obj.type == .collect {
            if let index = obj.tileKind {
                unmet.insert(TileKind(index))
            }
        }
        return suggest(board: board, unmetCollectionKinds: unmet)
    }
}
