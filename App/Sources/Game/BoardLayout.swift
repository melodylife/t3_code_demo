import CoreGraphics
import Match3Core

/// Board geometry in scene coordinates (origin bottom-left, y up).
/// Row 0 is the top row, so y decreases as the row index grows.
struct BoardLayout {
    let rows: Int
    let cols: Int
    let tile: CGFloat
    /// Top-left corner of the board.
    let origin: CGPoint

    var width: CGFloat { CGFloat(cols) * tile }
    var height: CGFloat { CGFloat(rows) * tile }

    func center(of cell: Cell) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(cell.col) + 0.5) * tile,
                y: origin.y - (CGFloat(cell.row) + 0.5) * tile)
    }

    func cell(at point: CGPoint) -> Cell? {
        let col = Int(floor((point.x - origin.x) / tile))
        let row = Int(floor((origin.y - point.y) / tile))
        guard row >= 0, row < rows, col >= 0, col < cols else { return nil }
        return Cell(row: row, col: col)
    }

    static func make(rows: Int, cols: Int, in size: CGSize) -> BoardLayout? {
        guard rows > 0, cols > 0, size.width > 80, size.height > 80 else { return nil }
        let inset: CGFloat = 8
        let availableWidth = size.width - inset * 2
        let availableHeight = size.height - inset * 2
        let tile = floor(min(availableWidth / CGFloat(cols), availableHeight / CGFloat(rows)))
        guard tile >= 16 else { return nil }
        let boardWidth = tile * CGFloat(cols)
        let boardHeight = tile * CGFloat(rows)
        let origin = CGPoint(x: (size.width - boardWidth) / 2,
                             y: (size.height + boardHeight) / 2)
        return BoardLayout(rows: rows, cols: cols, tile: tile, origin: origin)
    }
}
