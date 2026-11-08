import Foundation

/// A board coordinate. Row 0 is the top row.
public struct Cell: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let row: Int
    public let col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }

    public func isAdjacent(to other: Cell) -> Bool {
        abs(row - other.row) + abs(col - other.col) == 1
    }

    public func offset(row dRow: Int = 0, col dCol: Int = 0) -> Cell {
        Cell(row: row + dRow, col: col + dCol)
    }

    public static func < (lhs: Cell, rhs: Cell) -> Bool {
        lhs.row == rhs.row ? lhs.col < rhs.col : lhs.row < rhs.row
    }

    public var description: String { "(\(row),\(col))" }
}
