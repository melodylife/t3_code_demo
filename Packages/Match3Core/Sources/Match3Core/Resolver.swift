import Foundation

public enum SwapResult: Equatable, Sendable {
    case accepted
    case rejected
}

public struct TileSpawn: Equatable, Sendable {
    public let cell: Cell
    public let tile: Tile
    public init(cell: Cell, tile: Tile) {
        self.cell = cell
        self.tile = tile
    }
}

public struct TileMove: Equatable, Sendable {
    public let from: Cell
    public let to: Cell
    public init(from: Cell, to: Cell) {
        self.from = from
        self.to = to
    }
}

/// One animation-sized unit of work. The animator plays these in order; it never
/// decides matches by itself.
public enum CascadeStep: Equatable, Sendable {
    case swap(Cell, Cell, SwapResult)
    case clear(cells: [Cell], spawned: [TileSpawn], points: Int, multiplier: Double)
    case gravity(moves: [TileMove])
    case refill(spawns: [TileSpawn])
    case shuffle(Board)

    /// Authoritative board transition. A test asserts that applying every step
    /// in order yields `Resolution.finalBoard`.
    public func apply(to board: inout Board) {
        switch self {
        case let .swap(a, b, result):
            if result == .accepted { board.swap(a, b) }
        case let .clear(cells, spawned, _, _):
            for cell in cells { board[cell] = nil }
            for spawn in spawned { board[spawn.cell] = spawn.tile }
        case let .gravity(moves):
            for move in moves {
                board[move.to] = board[move.from]
                board[move.from] = nil
            }
        case let .refill(spawns):
            for spawn in spawns { board[spawn.cell] = spawn.tile }
        case let .shuffle(newBoard):
            board = newBoard
        }
    }
}

public struct Resolution: Sendable {
    public let steps: [CascadeStep]
    public let finalBoard: Board
    public let totalPoints: Int
    public let clearedKinds: [TileKind: Int]
    public let hitStepCap: Bool

    public var wasAccepted: Bool {
        if case .swap(_, _, .accepted)? = steps.first { return true }
        return false
    }
}
 
public struct InitialClearEvaluation: Sendable, Equatable {
    public let clearedCells: Set<Cell>
    public let clearedKinds: [TileKind: Int]
    public let spawnedSpecials: [TileSpawn]
    public let activatesExistingSpecial: Bool
    public let detonations: Int
    public let groups: [MatchGroup]
    public let points: Int

    public init(clearedCells: Set<Cell>,
                clearedKinds: [TileKind: Int],
                spawnedSpecials: [TileSpawn],
                activatesExistingSpecial: Bool,
                detonations: Int,
                groups: [MatchGroup],
                points: Int) {
        self.clearedCells = clearedCells
        self.clearedKinds = clearedKinds
        self.spawnedSpecials = spawnedSpecials
        self.activatesExistingSpecial = activatesExistingSpecial
        self.detonations = detonations
        self.groups = groups
        self.points = points
    }
}

public enum Resolver {
    public static let maxCascadeSteps = 50

    // MARK: - Swap validation

    /// Mirrors `resolveSwap`'s accept/reject decision exactly, without running the cascade.
    public static func isAcceptedSwap(_ board: Board, _ a: Cell, _ b: Cell) -> Bool {
        guard board.contains(a), board.contains(b), a.isAdjacent(to: b),
              let ta = board[a], let tb = board[b] else { return false }
        // Special activation is decided before looking for runs (see resolveSwap).
        if ta.isRainbow || tb.isRainbow { return true }
        if ta.isSpecial && tb.isSpecial { return true }
        var probe = board
        probe.swap(a, b)
        return !MatchDetector.groups(in: probe).isEmpty
    }

    public static func hasAnyMove(_ board: Board) -> Bool {
        firstAvailableMove(board) != nil
    }

    public static func firstAvailableMove(_ board: Board) -> (Cell, Cell)? {
        for row in 0..<board.rows {
            for col in 0..<board.cols {
                let cell = Cell(row: row, col: col)
                guard board[cell] != nil else { continue }
                for delta in [Cell(row: 0, col: 1), Cell(row: 1, col: 0)] {
                    let other = cell.offset(row: delta.row, col: delta.col)
                    guard board.contains(other), board[other] != nil else { continue }
                    if isAcceptedSwap(board, cell, other) { return (cell, other) }
                }
            }
        }
        return nil
    }

    // MARK: - Initial clear evaluation

    /// Evaluates the first clear step of a swap without consuming RNG or advancing refills.
    public static func evaluateInitialClear(_ board: Board, _ a: Cell, _ b: Cell) -> InitialClearEvaluation? {
        guard board.contains(a), board.contains(b), a.isAdjacent(to: b),
              let tileA = board[a], let tileB = board[b] else { return nil }

        var work = board
        work.swap(a, b)

        var seeds: Set<Cell> = []
        var preResolved: Set<Cell> = []
        var activatesExistingSpecial = false

        if tileA.isRainbow || tileB.isRainbow {
            activatesExistingSpecial = true
            if tileA.isRainbow && tileB.isRainbow {
                seeds = Set(work.cells)
                preResolved = [a, b]
            } else {
                let rainbowCell = tileA.isRainbow ? b : a
                let partnerCell = tileA.isRainbow ? a : b
                if let kind = work[partnerCell]?.kind {
                    seeds = Set(work.cells.filter { work[$0]?.kind == kind })
                }
                seeds.insert(partnerCell)
                seeds.insert(rainbowCell)
                preResolved = [rainbowCell]
            }
        } else if tileA.isSpecial && tileB.isSpecial {
            activatesExistingSpecial = true
            seeds = [a, b]
        }

        let groups = MatchDetector.groups(in: work)
        if seeds.isEmpty && groups.isEmpty { return nil }

        if !activatesExistingSpecial {
            for group in groups {
                for cell in group.cells {
                    let preSwapCell: Cell
                    if cell == a { preSwapCell = b }
                    else if cell == b { preSwapCell = a }
                    else { preSwapCell = cell }
                    if let originalTile = board[preSwapCell], originalTile.isSpecial {
                        activatesExistingSpecial = true
                        break
                    }
                }
                if activatesExistingSpecial { break }
            }
        }

        var clearCells = seeds
        var spawned: [TileSpawn] = []
        for group in groups {
            clearCells.formUnion(group.cells)
            if let special = Rules.special(for: group) {
                let cell = spawnCell(for: group, swapCells: [a, b])
                spawned.append(TileSpawn(cell: cell, tile: special))
            }
        }

        let expansion = expand(cells: clearCells, in: work, alreadyResolved: preResolved)
        let clearedKindsThisStep = expansion.cells.compactMap { work[$0]?.kind }
        var clearedKinds: [TileKind: Int] = [:]
        for kind in clearedKindsThisStep { clearedKinds[kind, default: 0] += 1 }

        if expansion.detonations > 0 {
            activatesExistingSpecial = true
        }

        let points = Rules.points(clearedCount: expansion.cells.count,
                                  groups: groups,
                                  detonations: expansion.detonations,
                                  multiplier: Rules.multiplier(cascadeIndex: 0))

        return InitialClearEvaluation(clearedCells: expansion.cells,
                                      clearedKinds: clearedKinds,
                                      spawnedSpecials: spawned,
                                      activatesExistingSpecial: activatesExistingSpecial,
                                      detonations: expansion.detonations,
                                      groups: groups,
                                      points: points)
    }

    public static func resolveSwap(_ board: Board,
                                   _ a: Cell,
                                   _ b: Cell,
                                   paletteCount: Int,
                                   rng: inout SplitMix64) -> Resolution {
        let rejected = Resolution(steps: [.swap(a, b, .rejected)],
                                  finalBoard: board,
                                  totalPoints: 0,
                                  clearedKinds: [:],
                                  hitStepCap: false)

        guard board.contains(a), board.contains(b), a.isAdjacent(to: b),
              let tileA = board[a], let tileB = board[b] else { return rejected }

        var work = board
        work.swap(a, b)

        // (1) Special activation is resolved BEFORE the no-match rejection:
        //     rainbow + anything and special + special are always legal swaps.
        // Seeds are collected on the POST-swap board: the swap moves both tiles, so a
        // pre-swap coordinate would name the wrong tile. The rainbow's own destination
        // is marked resolved, otherwise the expansion would detonate it a second time
        // for the most common kind and wipe half the board.
        var seeds: Set<Cell> = []
        var preResolved: Set<Cell> = []
        if tileA.isRainbow || tileB.isRainbow {
            if tileA.isRainbow && tileB.isRainbow {
                seeds = Set(work.cells)
                preResolved = [a, b]
            } else {
                let rainbowCell = tileA.isRainbow ? b : a
                let partnerCell = tileA.isRainbow ? a : b
                if let kind = work[partnerCell]?.kind {
                    seeds = Set(work.cells.filter { work[$0]?.kind == kind })
                }
                // The partner cell always goes, so a special partner is detonated by the
                // expansion instead of being skipped.
                seeds.insert(partnerCell)
                seeds.insert(rainbowCell)
                preResolved = [rainbowCell]
            }
        } else if tileA.isSpecial && tileB.isSpecial {
            seeds = [a, b]
        }

        var groups = MatchDetector.groups(in: work)
        if seeds.isEmpty && groups.isEmpty { return rejected }

        var steps: [CascadeStep] = [.swap(a, b, .accepted)]
        var totalPoints = 0
        var clearedKinds: [TileKind: Int] = [:]
        var pendingSeeds = seeds
        var cascade = 0
        var hitCap = false

        while true {
            if cascade >= maxCascadeSteps {
                hitCap = true
                break
            }
            groups = MatchDetector.groups(in: work)
            if groups.isEmpty && pendingSeeds.isEmpty { break }

            let multiplier = Rules.multiplier(cascadeIndex: cascade)

            var clearCells = pendingSeeds
            var spawned: [TileSpawn] = []
            for group in groups {
                clearCells.formUnion(group.cells)
                if let special = Rules.special(for: group) {
                    let cell = spawnCell(for: group, swapCells: [a, b])
                    spawned.append(TileSpawn(cell: cell, tile: special))
                }
            }

            let expansion = expand(cells: clearCells, in: work, alreadyResolved: preResolved)
            preResolved = []
            pendingSeeds = []

            let clearedKindsThisStep = expansion.cells.compactMap { work[$0]?.kind }
            for kind in clearedKindsThisStep { clearedKinds[kind, default: 0] += 1 }

            let points = Rules.points(clearedCount: expansion.cells.count,
                                      groups: groups,
                                      detonations: expansion.detonations,
                                      multiplier: multiplier)
            totalPoints += points

            let step = CascadeStep.clear(cells: expansion.cells.sorted(),
                                         spawned: spawned,
                                         points: points,
                                         multiplier: multiplier)
            step.apply(to: &work)
            steps.append(step)

            let moves = collapse(&work)
            if !moves.isEmpty { steps.append(.gravity(moves: moves)) }

            let spawns = refill(&work, paletteCount: paletteCount, rng: &rng)
            if !spawns.isEmpty { steps.append(.refill(spawns: spawns)) }

            cascade += 1
        }

        if hitCap {
            // A pathologically long chain: rebuild a fresh stable board rather than
            // keep animating forever.
            work = BoardGenerator.generate(rows: board.rows,
                                           cols: board.cols,
                                           paletteCount: paletteCount,
                                           rng: &rng)
            steps.append(.shuffle(work))
        }

        if !Resolver.hasAnyMove(work) {
            work = BoardGenerator.shuffled(work, paletteCount: paletteCount, rng: &rng)
            steps.append(.shuffle(work))
        }

        return Resolution(steps: steps,
                          finalBoard: work,
                          totalPoints: totalPoints,
                          clearedKinds: clearedKinds,
                          hitStepCap: hitCap)
    }

    // MARK: - Step construction helpers

    private static func spawnCell(for group: MatchGroup, swapCells: [Cell]) -> Cell {
        for cell in swapCells where group.cells.contains(cell) { return cell }
        return group.pivot
    }

    /// Expands a clear set by detonating every special caught in it (chain reaction).
    private static func expand(cells: Set<Cell>,
                               in board: Board,
                               alreadyResolved: Set<Cell>) -> (cells: Set<Cell>, detonations: Int) {
        var result = cells
        var queue = cells.sorted()
        var visited = Set<Cell>()
        var detonations = 0

        while !queue.isEmpty {
            let cell = queue.removeFirst()
            guard visited.insert(cell).inserted else { continue }
            guard !alreadyResolved.contains(cell), let tile = board[cell], tile.isSpecial else { continue }
            detonations += 1
            for blasted in blastCells(for: tile, at: cell, in: board) where !result.contains(blasted) {
                result.insert(blasted)
                queue.append(blasted)
            }
        }
        return (result, detonations)
    }

    private static func blastCells(for tile: Tile, at cell: Cell, in board: Board) -> [Cell] {
        switch tile {
        case .rainbow:
            guard let kind = mostCommonKind(in: board) else { return [cell] }
            return board.cells.filter { board[$0]?.kind == kind }
        case let .rocket(_, axis):
            switch axis {
            case .horizontal: return (0..<board.cols).map { Cell(row: cell.row, col: $0) }
            case .vertical: return (0..<board.rows).map { Cell(row: $0, col: cell.col) }
            }
        case .bomb:
            return (-1...1).flatMap { dRow in
                (-1...1).compactMap { dCol in
                    let target = cell.offset(row: dRow, col: dCol)
                    return board.contains(target) ? target : nil
                }
            }
        case .normal:
            return []
        }
    }

    private static func mostCommonKind(in board: Board) -> TileKind? {
        var counts: [TileKind: Int] = [:]
        for cell in board.cells {
            if let kind = board[cell]?.kind { counts[kind, default: 0] += 1 }
        }
        // Deterministic tie-break on the lowest kind index.
        return counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.index > rhs.key.index : lhs.value < rhs.value
        }?.key
    }

    static func collapse(_ board: inout Board) -> [TileMove] {
        var moves: [TileMove] = []
        for col in 0..<board.cols {
            var writeRow = board.rows - 1
            for row in stride(from: board.rows - 1, through: 0, by: -1) {
                let cell = Cell(row: row, col: col)
                guard let tile = board[cell] else { continue }
                if row != writeRow {
                    let target = Cell(row: writeRow, col: col)
                    board[target] = tile
                    board[cell] = nil
                    moves.append(TileMove(from: cell, to: target))
                }
                writeRow -= 1
            }
        }
        return moves
    }

    static func refill(_ board: inout Board, paletteCount: Int, rng: inout SplitMix64) -> [TileSpawn] {
        precondition(paletteCount >= 3)
        var spawns: [TileSpawn] = []
        for col in 0..<board.cols {
            var empties: [Cell] = []
            for row in 0..<board.rows where board[Cell(row: row, col: col)] == nil {
                empties.append(Cell(row: row, col: col))
            }
            for cell in empties.reversed() {
                let kind = TileKind(Int.random(in: 0..<paletteCount, using: &rng))
                let tile = Tile.normal(kind)
                board[cell] = tile
                spawns.append(TileSpawn(cell: cell, tile: tile))
            }
        }
        return spawns
    }
}
