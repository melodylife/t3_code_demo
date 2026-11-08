import Match3Core
import SpriteKit
import UIKit

protocol GameSceneDelegate: AnyObject {
    func sceneDidConsumeMove()
    func sceneDidClear(points: Int, kinds: [TileKind], spawnedSpecial: Bool)
    func sceneDidSettle(board: Board)
    func sceneRejectedSwap()
}

/// Pure animator for a fully resolved `[CascadeStep]` sequence.
///
/// The board model (`board`) is the single source of truth; step nodes are
/// mirrored into `nodes` and every step is applied to both at the moment its
/// animation starts, so the model and the sprites can never drift apart.
final class GameScene: SKScene {

    private struct Playback {
        let steps: [CascadeStep]
        var index: Int
        var remaining: TimeInterval
        let completion: () -> Void
    }

    weak var gameDelegate: GameSceneDelegate?

    var inputEnabled = true {
        didSet { if !inputEnabled { clearSelection() } }
    }

    private let level: Level
    private var board: Board
    private var rng: SplitMix64

    private let atlas = EmojiAtlas()
    private var nodes: [Cell: TileNode] = [:]
    private var layout: BoardLayout?
    private var backdrop: SKShapeNode?

    private var selectedCell: Cell?
    private var selectionBox: SKShapeNode?
    private var dragOrigin: Cell?
    private var dragStartPoint: CGPoint = .zero
    private var dragHandled = false

    private var playback: Playback?
    private var isAnimating: Bool { playback != nil }
    private var lastUpdateTime: TimeInterval?
    private var idleSeconds: TimeInterval = 0
    private var hintedPair: (Cell, Cell)?

    init(level: Level, board: Board, rng: SplitMix64) {
        self.level = level
        self.board = board
        self.rng = rng
        super.init(size: CGSize(width: 320, height: 320))
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Scene lifecycle

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        rebuildLayout()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        rebuildLayout()
    }

    private func rebuildLayout() {
        guard let newLayout = BoardLayout.make(rows: board.rows, cols: board.cols, in: size) else { return }
        let changed = layout?.tile != newLayout.tile
        layout = newLayout
        guard changed || nodes.isEmpty else { return }
        guard !isAnimating else { return }
        syncAllNodes()
    }

    private func syncAllNodes() {
        for node in nodes.values { node.removeFromParent() }
        nodes.removeAll()
        for cell in board.cells {
            guard let tile = board[cell] else { continue }
            let node = makeNode(tile: tile, cell: cell)
            addChild(node)
            nodes[cell] = node
        }
        drawBackdrop()
    }

    private func drawBackdrop() {
        backdrop?.removeFromParent()
        guard let layout else { return }
        let rect = CGRect(x: layout.origin.x,
                          y: layout.origin.y - layout.height,
                          width: layout.width,
                          height: layout.height)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: layout.tile * 0.35)
        let shape = SKShapeNode(path: path.cgPath)
        shape.fillColor = UIColor.white.withAlphaComponent(0.04)
        shape.strokeColor = UIColor.white.withAlphaComponent(0.10)
        shape.lineWidth = 1
        shape.zPosition = 1
        addChild(shape)
        backdrop = shape
    }

    // MARK: - Node construction

    private func symbol(for tile: Tile) -> String {
        switch tile {
        case let .normal(kind), let .rocket(kind, _), let .bomb(kind):
            return level.palette[safe: kind.index] ?? "❓"
        case .rainbow:
            return "🌈"
        }
    }

    private func makeNode(tile: Tile, cell: Cell) -> TileNode {
        let tileSide = layout?.tile ?? 40
        let texture = atlas.emoji(symbol(for: tile), pointSize: tileSide * 0.66)
        let node = TileNode(texture: texture,
                            color: .clear,
                            size: CGSize(width: tileSide * 0.96, height: tileSide * 0.96))
        node.tile = tile
        node.cell = cell
        node.position = layout?.center(of: cell) ?? .zero
        node.zPosition = 10
        addBadge(to: node, tile: tile, tileSide: tileSide)
        return node
    }

    private func addBadge(to node: TileNode, tile: Tile, tileSide: CGFloat) {
        let name: String?
        switch tile {
        case .rocket(_, .horizontal): name = "arrow.left.and.right"
        case .rocket(_, .vertical): name = "arrow.up.and.down"
        case .bomb: name = "burst.fill"
        case .normal, .rainbow: name = nil
        }
        guard let name else { return }

        let size = tileSide * 0.26
        guard let texture = atlas.symbol(name, pointSize: size, color: .white) else { return }
        let badge = SKSpriteNode(texture: texture, size: CGSize(width: size, height: size))
        badge.position = CGPoint(x: tileSide * 0.26, y: -tileSide * 0.26)
        badge.zPosition = 2
        node.addChild(badge)
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard inputEnabled, !isAnimating, let touch = touches.first, let layout else { return }
        let point = touch.location(in: self)
        guard let cell = layout.cell(at: point), board[cell] != nil else { return }

        clearHint()
        dragOrigin = cell
        dragStartPoint = point
        dragHandled = false

        if let selected = selectedCell {
            if selected == cell {
                clearSelection()
                dragOrigin = nil
                return
            }
            if selected.isAdjacent(to: cell) {
                commitSwap(from: selected, to: cell)
                dragOrigin = nil
                return
            }
        }
        select(cell)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard inputEnabled, !isAnimating, !dragHandled,
              let origin = dragOrigin, let touch = touches.first, let layout else { return }
        let point = touch.location(in: self)
        let dx = point.x - dragStartPoint.x
        let dy = point.y - dragStartPoint.y
        let threshold = max(8, layout.tile * 0.42)
        guard abs(dx) > threshold || abs(dy) > threshold else { return }

        let target: Cell = abs(dx) > abs(dy)
            ? origin.offset(col: dx > 0 ? 1 : -1)
            : origin.offset(row: dy > 0 ? -1 : 1)

        dragHandled = true
        guard board.contains(target), board[target] != nil else { return }
        commitSwap(from: origin, to: target)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragOrigin = nil
        dragHandled = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragOrigin = nil
        dragHandled = false
    }

    // MARK: - Swap

    private func commitSwap(from a: Cell, to b: Cell) {
        guard inputEnabled, !isAnimating else { return }
        clearSelection()

        let resolution = Resolver.resolveSwap(board, a, b,
                                             paletteCount: level.paletteCount,
                                             rng: &rng)
        guard resolution.wasAccepted else {
            animateRejectedSwap(a, b)
            Haptics.reject()
            SoundPlayer.shared.play(.error)
            gameDelegate?.sceneRejectedSwap()
            return
        }

        gameDelegate?.sceneDidConsumeMove()
        idleSeconds = 0
        start(resolution.steps, completion: { [weak self] in
            guard let self else { return }
            self.verifyNodeTable(expected: resolution.finalBoard)
            self.gameDelegate?.sceneDidSettle(board: resolution.finalBoard)
        })
    }

    /// Debug invariant: after a cascade settles the sprite table must mirror the model
    /// exactly, otherwise cleared cells keep holes or ghosts survive.
    private func verifyNodeTable(expected: Board) {
        #if DEBUG
        let missing = board.occupiedCells.filter { nodes[$0] == nil }
        let extra = nodes.keys.filter { board[$0] == nil }
        let drift = board != expected
        if !missing.isEmpty || !extra.isEmpty || drift {
            print("[EmojiMatch] desync missing=\(missing.count) extra=\(extra.count) boardDrift=\(drift)")
        }
        #endif
    }

    private func start(_ steps: [CascadeStep], completion: @escaping () -> Void) {
        guard let first = steps.first else {
            completion()
            return
        }
        let duration = apply(first)
        playback = Playback(steps: steps, index: 0, remaining: duration, completion: completion)
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        let delta = lastUpdateTime.map { min(0.1, max(0, currentTime - $0)) } ?? 0
        lastUpdateTime = currentTime

        guard var active = playback else {
            if inputEnabled {
                idleSeconds += delta
                if idleSeconds > Timing.hintDelay { showHintIfNeeded() }
            }
            return
        }

        active.remaining -= delta
        guard active.remaining <= 0 else {
            playback = active
            return
        }

        let next = active.index + 1
        guard next < active.steps.count else {
            playback = nil
            active.completion()
            return
        }
        active.index = next
        active.remaining = apply(active.steps[next])
        playback = active
    }

    // MARK: - Step application

    @discardableResult
    private func apply(_ step: CascadeStep) -> TimeInterval {
        switch step {
        case let .swap(a, b, result):
            // `apply(to:)` is the engine's own transition and the unit tests assert it
            // reproduces `finalBoard`; the scene never hand-writes model changes.
            step.apply(to: &board)
            if result == .accepted {
                animateSwap(a, b)
            } else {
                animateRejectedSwap(a, b)
            }
            return Timing.swap

        case let .clear(cells, spawned, points, _):
            let kinds = cells.compactMap { board[$0]?.kind }
            step.apply(to: &board)
            return applyClear(cells: cells, spawned: spawned, points: points, kinds: kinds)

        case let .gravity(moves):
            step.apply(to: &board)
            return applyGravity(moves)

        case let .refill(spawns):
            step.apply(to: &board)
            return applyRefill(spawns)

        case .shuffle:
            step.apply(to: &board)
            return applyShuffleVisual()
        }
    }

    private func animateSwap(_ a: Cell, _ b: Cell) {
        guard let layout, let nodeA = nodes[a], let nodeB = nodes[b] else { return }
        nodes[a] = nodeB
        nodes[b] = nodeA
        nodeA.cell = b
        nodeB.cell = a
        nodeA.zPosition = 12
        nodeB.zPosition = 11
        nodeA.run(.sequence([.move(to: layout.center(of: b), duration: Timing.swap), .run { nodeA.zPosition = 10 }]))
        nodeB.run(.sequence([.move(to: layout.center(of: a), duration: Timing.swap), .run { nodeB.zPosition = 10 }]))
    }

    private func animateRejectedSwap(_ a: Cell, _ b: Cell) {
        guard let nodeA = nodes[a], let nodeB = nodes[b] else { return }
        let posA = nodeA.position
        let posB = nodeB.position
        let dx = (posB.x - posA.x) * 0.4
        let dy = (posB.y - posA.y) * 0.4
        nodeA.run(.sequence([.moveBy(x: dx, y: dy, duration: Timing.rejectOut),
                             .move(to: posA, duration: Timing.rejectBack)]))
        nodeB.run(.sequence([.moveBy(x: -dx, y: -dy, duration: Timing.rejectOut),
                             .move(to: posB, duration: Timing.rejectBack)]))
    }

    private func applyClear(cells: [Cell], spawned: [TileSpawn], points: Int, kinds: [TileKind]) -> TimeInterval {
        let pivot = cells.first ?? Cell(row: 0, col: 0)
        var maxDelay: TimeInterval = 0

        for cell in cells {
            guard let node = nodes[cell] else { continue }
            nodes[cell] = nil
            let ring = min(4, max(abs(cell.row - pivot.row), abs(cell.col - pivot.col)))
            let delay = Timing.clearStagger * Double(ring)
            maxDelay = max(maxDelay, delay)
            let pop = SKAction.scale(to: 1.2, duration: Timing.clearPop)
            let shrink = SKAction.group([.scale(to: 0.1, duration: Timing.clearFade),
                                         .fadeOut(withDuration: Timing.clearFade)])
            node.run(.sequence([.wait(forDuration: delay), pop, shrink, .removeFromParent()]))
        }

        let spawnDelay = maxDelay + Timing.clearPop + Timing.clearFade
        for spawn in spawned {
            let node = makeNode(tile: spawn.tile, cell: spawn.cell)
            node.alpha = 0
            node.setScale(0.2)
            addChild(node)
            nodes[spawn.cell] = node
            node.run(.sequence([
                .wait(forDuration: spawnDelay),
                .group([.scale(to: 1.0, duration: Timing.specialPop),
                        .fadeIn(withDuration: Timing.specialPop)])
            ]))
        }

        gameDelegate?.sceneDidClear(points: points, kinds: kinds, spawnedSpecial: !spawned.isEmpty)
        if Haptics.isEnabled { Haptics.tap() }
        SoundPlayer.shared.play(spawned.isEmpty ? .match : .special)

        return spawnDelay + (spawned.isEmpty ? 0 : Timing.specialPop) + Timing.cascadeGap
    }

    private func applyGravity(_ moves: [TileMove]) -> TimeInterval {
        guard let layout else { return 0 }
        var longest: TimeInterval = 0
        var moving: [(TileNode, CGPoint)] = []

        for move in moves {
            guard let node = nodes[move.from] else { continue }
            nodes[move.from] = nil
            nodes[move.to] = node
            node.cell = move.to
            let target = layout.center(of: move.to)
            moving.append((node, target))
        }

        // Two passes: measure, then animate, so all tiles in a column share one
        // acceleration profile and land together.
        for (node, target) in moving {
            let distance = abs(node.position.y - target.y)
            let duration = Timing.fall(distance: distance)
            longest = max(longest, duration)
            node.run(.sequence([.move(to: target, duration: duration),
                                .moveBy(x: 0, y: -3, duration: 0.03),
                                .moveBy(x: 0, y: 3, duration: 0.03)]))
        }
        return longest + Timing.fallPad
    }

    private func applyRefill(_ spawns: [TileSpawn]) -> TimeInterval {
        guard let layout else { return 0 }
        var longest: TimeInterval = 0

        for spawn in spawns {
            nodes[spawn.cell]?.removeFromParent()
            let node = makeNode(tile: spawn.tile, cell: spawn.cell)
            let target = layout.center(of: spawn.cell)
            node.position = CGPoint(x: target.x, y: layout.origin.y + layout.tile * 0.5)
            node.alpha = 0.4
            addChild(node)
            nodes[spawn.cell] = node
            let distance = max(0, node.position.y - target.y)
            let duration = Timing.fall(distance: distance)
            longest = max(longest, duration)
            node.run(.sequence([.move(to: target, duration: duration),
                                .fadeAlpha(to: 1.0, duration: duration * 0.6)]))
        }
        return longest + Timing.fallPad
    }

    private func applyShuffleVisual() -> TimeInterval {
        for node in nodes.values {
            node.run(.sequence([.fadeOut(withDuration: Timing.shuffle * 0.4), .removeFromParent()]))
        }
        nodes.removeAll()

        for cell in board.cells {
            guard let tile = board[cell] else { continue }
            let node = makeNode(tile: tile, cell: cell)
            node.alpha = 0
            addChild(node)
            nodes[cell] = node
            node.run(.fadeIn(withDuration: Timing.shuffle * 0.6))
        }
        return Timing.shuffle
    }

    // MARK: - Selection and hints

    private func select(_ cell: Cell) {
        clearSelection()
        guard let layout, let node = nodes[cell] else { return }
        selectedCell = cell
        let side = layout.tile * 0.94
        let box = SKShapeNode(rect: CGRect(x: -side / 2, y: -side / 2, width: side, height: side),
                             cornerRadius: side * 0.24)
        box.strokeColor = UIColor.white.withAlphaComponent(0.85)
        box.lineWidth = 2
        box.fillColor = UIColor.white.withAlphaComponent(0.10)
        box.zPosition = 3
        node.addChild(box)
        selectionBox = box
        node.zPosition = 12
    }

    private func clearSelection() {
        selectionBox?.removeFromParent()
        selectionBox = nil
        if let cell = selectedCell, let node = nodes[cell] { node.zPosition = 10 }
        selectedCell = nil
    }

    private func showHintIfNeeded() {
        guard hintedPair == nil, inputEnabled, !isAnimating,
              let pair = Resolver.firstAvailableMove(board) else { return }
        hintedPair = pair
        for cell in [pair.0, pair.1] {
            nodes[cell]?.run(.repeatForever(.sequence([
                .scale(to: 1.10, duration: 0.32),
                .scale(to: 1.0, duration: 0.32)
            ])), withKey: "hint")
        }
    }

    private func clearHint() {
        idleSeconds = 0
        guard let pair = hintedPair else { return }
        for cell in [pair.0, pair.1] {
            nodes[cell]?.removeAction(forKey: "hint")
            nodes[cell]?.setScale(1.0)
        }
        hintedPair = nil
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
