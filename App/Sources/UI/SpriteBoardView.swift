import SpriteKit
import SwiftUI
import Match3Core

struct SpriteBoardView: UIViewRepresentable {
    let scene: SKScene

    func makeUIView(context: Context) -> AccessibleBoardSKView {
        let view = AccessibleBoardSKView()
        view.ignoresSiblingOrder = true
        view.isMultipleTouchEnabled = false
        view.backgroundColor = .clear
        view.preferredFramesPerSecond = 60
        view.accessibilityIdentifier = "board"
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ uiView: AccessibleBoardSKView, context: Context) {
        if uiView.scene !== scene {
            uiView.presentScene(scene)
        }
    }
}

final class AccessibleBoardSKView: SKView {
    var gameScene: GameScene? {
        scene as? GameScene
    }

    private var cellElements: [Cell: CellAccessibilityElement] = [:]

    override var isAccessibilityElement: Bool {
        get { false }
        set { }
    }

    override var accessibilityElements: [Any]? {
        get {
            guard let gameScene else { return [] }
            var elements: [UIAccessibilityElement] = []

            for row in 0..<gameScene.board.rows {
                for col in 0..<gameScene.board.cols {
                    let cell = Cell(row: row, col: col)
                    guard gameScene.board[cell] != nil else { continue }

                    let element: CellAccessibilityElement
                    if let existing = cellElements[cell] {
                        element = existing
                    } else {
                        element = CellAccessibilityElement(cell: cell, containerView: self)
                        cellElements[cell] = element
                    }
                    element.update()
                    elements.append(element)
                }
            }
            return elements
        }
        set { }
    }
}

final class CellAccessibilityElement: UIAccessibilityElement {
    let cell: Cell
    private weak var boardView: AccessibleBoardSKView?

    init(cell: Cell, containerView: AccessibleBoardSKView) {
        self.cell = cell
        self.boardView = containerView
        super.init(accessibilityContainer: containerView)
        isAccessibilityElement = true
        accessibilityIdentifier = "cell_\(cell.row)_\(cell.col)"
        accessibilityTraits = [.button]
    }

    func update() {
        guard let boardView, let scene = boardView.gameScene else { return }
        accessibilityLabel = scene.cellAccessibilityLabel(at: cell)

        let isSelected = scene.isCellSelected(cell)
        if isSelected {
            accessibilityTraits = [.button, .selected]
            accessibilityValue = "Selected"
        } else {
            accessibilityTraits = [.button]
            accessibilityValue = nil
        }

        if let hint = scene.activeHint, (hint.from == cell || hint.to == cell) {
            let other = (hint.from == cell) ? hint.to : hint.from
            accessibilityHint = "Hint: Swap with row \(other.row + 1), column \(other.col + 1)"
        } else {
            accessibilityHint = isSelected ? "Double-tap to deselect" : "Double-tap to select or swap with adjacent selection"
        }

        if let sceneFrame = scene.frame(for: cell) {
            let viewRect = boardView.convert(sceneFrame, from: scene)
            accessibilityFrame = UIAccessibility.convertToScreenCoordinates(viewRect, in: boardView)
        }

        if !scene.inputEnabled || scene.isInputGated || !scene.isSettled {
            accessibilityTraits.insert(.notEnabled)
        }

        var actions: [UIAccessibilityCustomAction] = []
        let sourceCell = cell
        let directions: [(String, Cell)] = [
            ("Swap Right", cell.offset(col: 1)),
            ("Swap Down", cell.offset(row: 1)),
            ("Swap Left", cell.offset(col: -1)),
            ("Swap Up", cell.offset(row: -1))
        ]

        for (name, target) in directions {
            if scene.board.contains(target), scene.board[target] != nil {
                let action = UIAccessibilityCustomAction(name: name, actionHandler: { [weak scene] _ in
                    guard let scene else { return false }
                    return scene.commitSwap(from: sourceCell, to: target)
                })
                actions.append(action)
            }
        }
        accessibilityCustomActions = actions
    }

    override func accessibilityActivate() -> Bool {
        guard let boardView, let scene = boardView.gameScene,
              scene.inputEnabled, !scene.isInputGated, scene.isSettled else { return false }
        scene.selectCellAccessibility(at: cell)
        return true
    }
}
