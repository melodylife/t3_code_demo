import Foundation

public struct Run: Equatable, Sendable {
    public let cells: [Cell]
    public let axis: Axis
    public let kind: TileKind
}

public enum GroupShape: Equatable, Sendable {
    /// A single straight run. The payload is the run length (>= 3).
    case line(Int)
    /// An L or T: at least one horizontal and one vertical run joined together.
    case corner
}

public struct MatchGroup: Equatable, Sendable {
    public let cells: [Cell]
    public let shape: GroupShape
    public let kind: TileKind
    /// Cell that should receive a spawned special: the junction of a corner,
    /// or the middle of a straight run.
    public let pivot: Cell

    public var length: Int { cells.count }
}

public enum MatchDetector {
    public static func runs(in board: Board) -> [Run] {
        var result: [Run] = []

        for row in 0..<board.rows {
            var col = 0
            while col < board.cols {
                guard let kind = board[Cell(row: row, col: col)]?.kind else { col += 1; continue }
                var end = col + 1
                while end < board.cols, board[Cell(row: row, col: end)]?.kind == kind { end += 1 }
                let length = end - col
                if length >= 3 {
                    result.append(Run(cells: (col..<end).map { Cell(row: row, col: $0) }, axis: .horizontal, kind: kind))
                }
                col = end
            }
        }

        for col in 0..<board.cols {
            var row = 0
            while row < board.rows {
                guard let kind = board[Cell(row: row, col: col)]?.kind else { row += 1; continue }
                var end = row + 1
                while end < board.rows, board[Cell(row: end, col: col)]?.kind == kind { end += 1 }
                let length = end - row
                if length >= 3 {
                    result.append(Run(cells: (row..<end).map { Cell(row: $0, col: col) }, axis: .vertical, kind: kind))
                }
                row = end
            }
        }

        return result
    }

    public static func groups(in board: Board) -> [MatchGroup] {
        let allRuns = runs(in: board)
        guard !allRuns.isEmpty else { return [] }

        var parent = Array(0..<allRuns.count)
        func find(_ value: Int) -> Int {
            var value = value
            while parent[value] != value {
                parent[value] = parent[parent[value]]
                value = parent[value]
            }
            return value
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[rb] = ra }
        }

        var firstOwner: [Cell: Int] = [:]
        for (i, run) in allRuns.enumerated() {
            for cell in run.cells {
                if let owner = firstOwner[cell] {
                    union(i, owner)
                } else {
                    firstOwner[cell] = i
                }
            }
        }

        var buckets: [Int: [Int]] = [:]
        for i in allRuns.indices { buckets[find(i), default: []].append(i) }

        return buckets.values.compactMap { indices -> MatchGroup? in
            var cellSet = Set<Cell>()
            var runCountPerCell: [Cell: Int] = [:]
            var horizontal = 0
            var vertical = 0
            var longest: Run?
            var kind: TileKind?

            for i in indices {
                let run = allRuns[i]
                kind = kind ?? run.kind
                if run.axis == .horizontal { horizontal += 1 } else { vertical += 1 }
                if longest == nil || run.cells.count > longest!.cells.count { longest = run }
                for cell in run.cells {
                    cellSet.insert(cell)
                    runCountPerCell[cell, default: 0] += 1
                }
            }

            guard let groupKind = kind, let longestRun = longest else { return nil }
            let cells = cellSet.sorted()

            let shape: GroupShape
            let pivot: Cell
            if horizontal > 0 && vertical > 0 {
                shape = .corner
                // The corner is the only cell shared by runs of both axes.
                pivot = runCountPerCell.filter { $0.value >= 2 }.keys.min() ?? cells[0]
            } else {
                shape = .line(longestRun.cells.count)
                pivot = longestRun.cells[longestRun.cells.count / 2]
            }

            return MatchGroup(cells: cells, shape: shape, kind: groupKind, pivot: pivot)
        }
        .sorted { ($0.cells.first ?? Cell(row: 0, col: 0)) < ($1.cells.first ?? Cell(row: 0, col: 0)) }
    }
}
