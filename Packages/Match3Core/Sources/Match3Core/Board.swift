import Foundation

/// Row-major grid. `nil` means the cell is empty (mid-cascade).
public struct Board: Equatable, Sendable {
    public let rows: Int
    public let cols: Int
    public private(set) var tiles: [Tile?]

    public init(rows: Int, cols: Int) {
        precondition(rows > 0 && cols > 0)
        self.rows = rows
        self.cols = cols
        self.tiles = Array(repeating: nil, count: rows * cols)
    }

    public init(rows: Int, cols: Int, tiles: [Tile?]) {
        precondition(rows > 0 && cols > 0)
        precondition(tiles.count == rows * cols)
        self.rows = rows
        self.cols = cols
        self.tiles = tiles
    }

    private func index(_ cell: Cell) -> Int {
        cell.row * cols + cell.col
    }

    public func contains(_ cell: Cell) -> Bool {
        cell.row >= 0 && cell.row < rows && cell.col >= 0 && cell.col < cols
    }

    public subscript(_ cell: Cell) -> Tile? {
        get { tiles[index(cell)] }
        set { tiles[index(cell)] = newValue }
    }

    public var cells: [Cell] {
        (0..<rows).flatMap { row in (0..<cols).map { Cell(row: row, col: $0) } }
    }

    public var occupiedCells: [Cell] {
        cells.filter { self[$0] != nil }
    }

    public mutating func swap(_ a: Cell, _ b: Cell) {
        let temp = self[a]
        self[a] = self[b]
        self[b] = temp
    }
}
