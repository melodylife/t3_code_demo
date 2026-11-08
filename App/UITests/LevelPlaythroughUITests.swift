import XCTest

/// Drives the real app with real touches: no injected state, no test-only paths.
final class LevelPlaythroughUITests: XCTestCase {

    private struct Cell {
        let row: Int
        let col: Int
    }

    private var app: XCUIApplication!
    private var board: XCUIElement!
    private var cellSide: CGFloat = 0
    private var boardOrigin: CGPoint = .zero

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testLevelOneReachesWinOverlay() throws {
        let playButton = app.buttons["level_1"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 15), "menu never appeared")
        playButton.tap()

        board = app.otherElements["board"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 10), "board never appeared")
        measureBoard()

        let moves = app.staticTexts["movesValue"]
        let result = app.staticTexts["resultTitle"]
        XCTAssertTrue(moves.waitForExistence(timeout: 10), "moves counter missing")

        var cursor = 0
        var acceptedSwaps = 0
        let pairs = neighbourPairs()

        while !result.exists && acceptedSwaps < 26 {
            let pair = pairs[cursor % pairs.count]
            let movesBefore = moves.label

            tap(pair.from)
            tap(pair.to)
            // A rejection never consumes a move; an acceptance decrements at once,
            // before the cascade animation starts.
            Thread.sleep(forTimeInterval: 0.25)

            if moves.label != movesBefore {
                acceptedSwaps += 1
                cursor += 3
                Thread.sleep(forTimeInterval: 2.5) // let the cascade finish
                if acceptedSwaps == 3 { attachScreenshot("board-after-3-swaps") }
            } else {
                cursor += 1
            }
        }

        XCTAssertTrue(result.waitForExistence(timeout: 15),
                      "no result overlay after \(acceptedSwaps) accepted swaps")
        // The overlay is a full-screen cover, so the HUD drops out of the accessibility
        // tree while it is up; read the score from the overlay itself.
        let finalScoreText = app.staticTexts["finalScoreValue"]
        XCTAssertTrue(finalScoreText.waitForExistence(timeout: 5), "final score missing")
        print("[uitest] accepted=\(acceptedSwaps) moves='\(moves.label)' overlayScore='\(finalScoreText.label)' result='\(result.label)' boardFrame=\(board.frame) cell=\(cellSide)")
        XCTAssertEqual(result.label, "Level Clear")
        // The score is shown with the user's locale grouping separator ("1,890").
        let finalScore = Int(finalScoreText.label.filter(\.isNumber)) ?? 0
        XCTAssertGreaterThanOrEqual(finalScore, 1500,
                                    "score below the level target (raw label '\(finalScoreText.label)')")

        attachScreenshot("level-clear")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - Geometry

    /// Mirrors BoardLayout: 8pt inset on the shorter side, square tiles floored to
    /// whole points, board centred in the SpriteKit view.
    private func measureBoard() {
        let frame = board.frame
        let side = min(frame.width, frame.height)
        cellSide = floor((side - 16) / 8)
        let boardSide = cellSide * 8
        boardOrigin = CGPoint(x: frame.minX + (frame.width - boardSide) / 2,
                              y: frame.minY + (frame.height - boardSide) / 2)
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func tap(_ cell: Cell) {
        let frame = board.frame
        let x = boardOrigin.x + (CGFloat(cell.col) + 0.5) * cellSide - frame.minX
        let y = boardOrigin.y + (CGFloat(cell.row) + 0.5) * cellSide - frame.minY
        board.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: x, dy: y))
            .tap()
    }

    private func neighbourPairs() -> [(from: Cell, to: Cell)] {
        var pairs: [(from: Cell, to: Cell)] = []
        for row in 0..<8 {
            for col in 0..<8 {
                let cell = Cell(row: row, col: col)
                if col + 1 < 8 {
                    pairs.append((cell, Cell(row: row, col: col + 1)))
                }
                if row + 1 < 8 {
                    pairs.append((cell, Cell(row: row + 1, col: col)))
                }
            }
        }
        return pairs
    }
}
