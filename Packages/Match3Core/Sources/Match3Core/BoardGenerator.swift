import Foundation

public enum BoardGenerator {
    /// Fills the board cell by cell, rejecting the two kinds that would complete a
    /// run of three. Always terminates: at most two kinds are forbidden.
    public static func generate(rows: Int,
                                cols: Int,
                                paletteCount: Int,
                                rng: inout SplitMix64) -> Board {
        precondition(paletteCount >= 3, "a palette below 3 kinds cannot avoid initial matches")

        var fallback = Board(rows: rows, cols: cols)
        for _ in 0..<50 {
            var board = Board(rows: rows, cols: cols)
            for row in 0..<rows {
                for col in 0..<cols {
                    var forbidden = Set<Int>()
                    if col >= 2,
                       let left1 = board[Cell(row: row, col: col - 1)]?.kind,
                       let left2 = board[Cell(row: row, col: col - 2)]?.kind,
                       left1 == left2 {
                        forbidden.insert(left1.index)
                    }
                    if row >= 2,
                       let up1 = board[Cell(row: row - 1, col: col)]?.kind,
                       let up2 = board[Cell(row: row - 2, col: col)]?.kind,
                       up1 == up2 {
                        forbidden.insert(up1.index)
                    }
                    let candidates = (0..<paletteCount).filter { !forbidden.contains($0) }
                    let pick = candidates.randomElement(using: &rng) ?? 0
                    board[Cell(row: row, col: col)] = .normal(TileKind(pick))
                }
            }
            fallback = board
            if Resolver.hasAnyMove(board) { return board }
        }
        return fallback
    }

    /// Rearranges the existing tiles until the board has no match and at least one move.
    public static func shuffled(_ board: Board,
                                paletteCount: Int,
                                rng: inout SplitMix64) -> Board {
        let tiles = board.tiles.compactMap { $0 }
        guard !tiles.isEmpty else {
            return generate(rows: board.rows, cols: board.cols, paletteCount: paletteCount, rng: &rng)
        }

        for _ in 0..<200 {
            var pool = tiles
            pool.shuffle(using: &rng)
            var candidate = board
            var cursor = 0
            for cell in candidate.cells where candidate[cell] != nil {
                candidate[cell] = pool[cursor]
                cursor += 1
            }
            if !MatchDetector.groups(in: candidate).isEmpty { continue }
            if !Resolver.hasAnyMove(candidate) { continue }
            return candidate
        }

        // Fallback that cannot loop: rebuild from scratch. Specials are lost; this is
        // only reachable after 200 failed permutations.
        return generate(rows: board.rows, cols: board.cols, paletteCount: paletteCount, rng: &rng)
    }
}
