import XCTest
@testable import Match3Core

/// ASCII board fixtures.
/// '0'...'5' -> normal kind, R -> horizontal rocket (kind 0), C -> vertical rocket (kind 0),
/// B -> bomb (kind 1), W -> rainbow, anything else -> empty.
func makeBoard(_ rows: [String]) -> Board {
    let height = rows.count
    let width = rows.map(\.count).max() ?? 0
    var board = Board(rows: height, cols: width)
    for (r, line) in rows.enumerated() {
        for (c, ch) in line.enumerated() {
            board[Cell(row: r, col: c)] = makeTile(ch)
        }
    }
    return board
}

func makeTile(_ ch: Character) -> Tile? {
    switch ch {
    case "0"..."5":
        return .normal(TileKind(Int(String(ch))!))
    case "R":
        return .rocket(TileKind(0), .horizontal)
    case "C":
        return .rocket(TileKind(0), .vertical)
    case "B":
        return .bomb(TileKind(1))
    case "W":
        return .rainbow
    default:
        return nil
    }
}

/// Reproduces the animator: applies every step to the starting board.
func applySteps(_ steps: [CascadeStep], to start: Board) -> Board {
    var board = start
    for step in steps { step.apply(to: &board) }
    return board
}

func firstClear(_ resolution: Resolution) -> CascadeStep? {
    resolution.steps.first { if case .clear = $0 { return true } else { return false } }
}
