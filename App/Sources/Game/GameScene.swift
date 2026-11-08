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
        didSet { if !inputEnabled { clearSelection(); clearHint() } }
    }

    /// Input gating for instructional overlays, tutorials, and modal dialogs.
    var isInputGated = false {
        didSet {
            if isInputGated {
                clearSelection()
                clearHint()
            }
        }
    }

    /// Settled board status: true when no cascades are actively playing.
    var isSettled: Bool { playback == nil }

    /// Settled board callback, triggered after every cascade playback completes.
    var onBoardSettled: ((Board) -> Void)?

    /// Integration seam for parent Feature 2 feedback: emitted from the actual .clear step.
    var onClearFeedback: ((_ points: Int, _ multiplier: Double, _ spawnedSpecial: Tile?) -> Void)?

    /// Notification for queued special introductions.
    var onSpecialSpawned: ((Tile) -> Void)?

    /// Published active hint suggestion for UI layers.
    private(set) var activeHint: HintSuggestion? {
        didSet {
            onHintChanged?(activeHint)
        }
    }
    var onHintChanged: ((HintSuggestion?) -> Void)?

    /// Testing hook or environment override for Reduce Motion.
    var reduceMotionOverride: Bool?

    private var isReduceMotionEnabled: Bool {
        reduceMotionOverride ?? UIAccessibility.isReduceMotionEnabled
    }

    let level: Level
    private(set) var board: Board
    private var rng: SplitMix64

    private let atlas = EmojiAtlas()
    private var nodes: [Cell: TileNode] = [:]
    private var layout: BoardLayout?
    private var backdrop: SKShapeNode?

    private(set) var selectedCell: Cell?
    private var selectionBox: SKShapeNode?
    private var dragOrigin: Cell?
    private var dragStartPoint: CGPoint = .zero
    private var dragHandled = false

    private var playback: Playback?
    private var isAnimating: Bool { playback != nil }
    private var lastUpdateTime: TimeInterval?
    private var idleSeconds: TimeInterval = 0
    private var hintedPair: (Cell, Cell)?
    private var hintNodes: [SKNode] = []

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

    func symbol(for tile: Tile) -> String {
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
        guard inputEnabled, !isInputGated, !isAnimating, let touch = touches.first, let layout else { return }
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
        guard inputEnabled, !isInputGated, !isAnimating, !dragHandled,
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

    // MARK: - Swap Execution

    @discardableResult
    func commitSwap(from a: Cell, to b: Cell) -> Bool {
        guard inputEnabled, !isInputGated, !isAnimating else { return false }
        clearSelection()
        clearHint()

        let resolution = Resolver.resolveSwap(board, a, b,
                                             paletteCount: level.paletteCount,
                                             rng: &rng)
        guard resolution.wasAccepted else {
            animateRejectedSwap(a, b)
            Haptics.reject()
            SoundPlayer.shared.play(.error)
            gameDelegate?.sceneRejectedSwap()
            return false
        }

        gameDelegate?.sceneDidConsumeMove()
        idleSeconds = 0
        start(resolution.steps, completion: { [weak self] in
            guard let self else { return }
            self.verifyNodeTable(expected: resolution.finalBoard)
            self.onBoardSettled?(resolution.finalBoard)
            self.gameDelegate?.sceneDidSettle(board: resolution.finalBoard)
        })
        return true
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
            if inputEnabled && !isInputGated {
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

        case let .clear(cells, spawned, points, multiplier):
            let kinds = cells.compactMap { board[$0]?.kind }
            step.apply(to: &board)
            return applyClear(cells: cells, spawned: spawned, points: points, kinds: kinds, multiplier: multiplier)

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

    private func applyClear(cells: [Cell],
                            spawned: [TileSpawn],
                            points: Int,
                            kinds: [TileKind],
                            multiplier: Double = 1.0) -> TimeInterval {
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

            // Notify listeners about newly spawned specials
            if spawn.tile.isSpecial {
                onSpecialSpawned?(spawn.tile)
            }
        }

        // Feature 2 parent feedback hook
        onClearFeedback?(points, multiplier, spawned.first?.tile)

        // Existing delegate signature maintained 100% compatible
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

    // MARK: - Selection and Interaction

    func select(_ cell: Cell) {
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

    func clearSelection() {
        selectionBox?.removeFromParent()
        selectionBox = nil
        if let cell = selectedCell, let node = nodes[cell] { node.zPosition = 10 }
        selectedCell = nil
    }

    /// Clears any transient instructional state: selection, hint, and drag.
    func clearInstructionState() {
        clearSelection()
        clearHint()
        dragOrigin = nil
        dragHandled = false
    }

    // MARK: - Hint System

    /// Safe public method to request an objective-aware hint.
    @discardableResult
    func requestHint(unmetCollectionKinds: Set<TileKind> = []) -> HintSuggestion? {
        guard inputEnabled, !isInputGated, isSettled else { return nil }
        clearHint()
        guard let suggestion = HintAdvisor.suggest(board: board, unmetCollectionKinds: unmetCollectionKinds) else {
            return nil
        }
        displayHint(suggestion, isIdle: false)
        return suggestion
    }

    /// Safe public method to request a hint using level objectives and tracker.
    @discardableResult
    func requestHint(objectives: [Objective], tracker: ObjectiveTracker) -> HintSuggestion? {
        guard inputEnabled, !isInputGated, isSettled else { return nil }
        clearHint()
        guard let suggestion = HintAdvisor.suggest(board: board, objectives: objectives, tracker: tracker) else {
            return nil
        }
        displayHint(suggestion, isIdle: false)
        return suggestion
    }

    private func showHintIfNeeded() {
        guard hintedPair == nil, inputEnabled, !isInputGated, isSettled else { return }
        if let suggestion = HintAdvisor.suggest(board: board) {
            displayHint(suggestion, isIdle: true)
        } else if let pair = Resolver.firstAvailableMove(board) {
            let fallback = HintSuggestion(from: pair.0, to: pair.1, reason: .standardMatch(clearedCount: 3), clearedCount: 3)
            displayHint(fallback, isIdle: true)
        }
    }

    private func displayHint(_ suggestion: HintSuggestion, isIdle: Bool = false) {
        clearHint()
        idleSeconds = 0
        hintedPair = (suggestion.from, suggestion.to)
        activeHint = suggestion

        guard let layout else { return }

        let side = layout.tile * 0.94
        for cell in [suggestion.from, suggestion.to] {
            guard let node = nodes[cell] else { continue }

            // Static highlight outline (always shown for Reduce Motion & standard mode)
            let box = SKShapeNode(rect: CGRect(x: -side / 2, y: -side / 2, width: side, height: side),
                                 cornerRadius: side * 0.24)
            box.strokeColor = UIColor.systemYellow.withAlphaComponent(0.9)
            box.lineWidth = 3
            box.fillColor = UIColor.systemYellow.withAlphaComponent(0.12)
            box.zPosition = 4
            box.name = "hint_highlight"
            node.addChild(box)
            hintNodes.append(box)

            // Dynamic pulsing is disabled when Reduce Motion is active
            if !isReduceMotionEnabled {
                node.run(.repeatForever(.sequence([
                    .scale(to: 1.10, duration: 0.32),
                    .scale(to: 1.0, duration: 0.32)
                ])), withKey: "hint")
            }
        }

        // Draw directional connector arrow between the two suggested cells
        drawHintArrow(from: suggestion.from, to: suggestion.to)

        // Spoken announcement for requested hints
        if !isIdle {
            let message = hintAccessibilityAnnouncement(for: suggestion)
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private func drawHintArrow(from a: Cell, to b: Cell) {
        guard let layout else { return }
        let pA = layout.center(of: a)
        let pB = layout.center(of: b)

        let path = CGMutablePath()
        path.move(to: pA)
        path.addLine(to: pB)

        let line = SKShapeNode(path: path)
        line.strokeColor = UIColor.systemYellow.withAlphaComponent(0.85)
        line.lineWidth = 4
        line.lineCap = .round
        line.zPosition = 15
        addChild(line)
        hintNodes.append(line)
    }

    func clearHint() {
        idleSeconds = 0
        for node in hintNodes { node.removeFromParent() }
        hintNodes.removeAll()

        if let pair = hintedPair {
            for cell in [pair.0, pair.1] {
                nodes[cell]?.removeAction(forKey: "hint")
                nodes[cell]?.setScale(1.0)
            }
            hintedPair = nil
        }
        activeHint = nil
    }

    private func hintAccessibilityAnnouncement(for suggestion: HintSuggestion) -> String {
        let fromDesc = "Row \(suggestion.from.row + 1), Column \(suggestion.from.col + 1)"
        let toDesc = "Row \(suggestion.to.row + 1), Column \(suggestion.to.col + 1)"

        switch suggestion.reason {
        case let .collectObjective(kind, _):
            let fruit = level.palette[safe: kind.index] ?? "target"
            return "Hint: Swap \(fromDesc) with \(toDesc) to collect \(fruit)."
        case let .createSpecial(special):
            return "Hint: Swap \(fromDesc) with \(toDesc) to create a \(specialName(for: special))."
        case .activateSpecial:
            return "Hint: Swap \(fromDesc) with \(toDesc) to activate special tile."
        case let .standardMatch(count):
            return "Hint: Swap \(fromDesc) with \(toDesc) to match \(count) tiles."
        }
    }

    private func specialName(for tile: Tile) -> String {
        switch tile {
        case .rocket: return "Rocket"
        case .bomb: return "Bomb"
        case .rainbow: return "Rainbow"
        case .normal: return "Tile"
        }
    }

    // MARK: - Accessibility Support

    func frame(for cell: Cell) -> CGRect? {
        guard let layout else { return nil }
        let center = layout.center(of: cell)
        let side = layout.tile
        return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    func cellTile(at cell: Cell) -> Tile? {
        board[cell]
    }

    func cellAccessibilityLabel(at cell: Cell) -> String {
        guard let tile = board[cell] else {
            return "Empty, Row \(cell.row + 1), Column \(cell.col + 1)"
        }
        let fruit = symbol(for: tile)
        let fruitName = fruitAccessibilityName(fruit)
        let rowStr = "Row \(cell.row + 1)"
        let colStr = "Column \(cell.col + 1)"

        switch tile {
        case .normal:
            return "\(fruitName), \(rowStr), \(colStr)"
        case let .rocket(_, axis):
            let dir = axis == .horizontal ? "Horizontal" : "Vertical"
            return "\(dir) Rocket \(fruitName), \(rowStr), \(colStr)"
        case .bomb:
            return "Bomb \(fruitName), \(rowStr), \(colStr)"
        case .rainbow:
            return "Rainbow, \(rowStr), \(colStr)"
        }
    }

    private func fruitAccessibilityName(_ symbol: String) -> String {
        switch symbol {
        case "🍎": return "Apple"
        case "🍌": return "Banana"
        case "🍇": return "Grapes"
        case "🍊": return "Orange"
        case "🍓": return "Strawberry"
        case "🍒": return "Cherries"
        case "🥝": return "Kiwi"
        case "🍉": return "Watermelon"
        case "🍋": return "Lemon"
        case "🍑": return "Peach"
        case "🍍": return "Pineapple"
        case "🥥": return "Coconut"
        case "🌈": return "Rainbow"
        default: return symbol
        }
    }

    /// Accessibility selection and swap parity with touch events.
    func selectCellAccessibility(at cell: Cell) {
        guard inputEnabled, !isInputGated, isSettled, board[cell] != nil else { return }
        clearHint()

        if let selected = selectedCell {
            if selected == cell {
                clearSelection()
                return
            }
            if selected.isAdjacent(to: cell) {
                commitSwap(from: selected, to: cell)
                return
            }
        }
        select(cell)
    }

    func isCellSelected(_ cell: Cell) -> Bool {
        selectedCell == cell
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
