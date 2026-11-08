import Match3Core
import SpriteKit

/// A tile sprite that remembers which cell and which logical tile it represents.
final class TileNode: SKSpriteNode {
    var cell = Cell(row: 0, col: 0)
    var tile: Tile = .rainbow
}
