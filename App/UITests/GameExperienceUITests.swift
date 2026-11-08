import XCTest

final class GameExperienceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testFirstPlayPracticeCanBeSkippedWithoutUsingCampaignMoves() {
        // Standard UserDefaults launch overrides isolate preferences, not game state.
        app.launchArguments = ["-emojimatch.learning.tips_seen_v1", "NO",
                               "-emojimatch.learning.tutorial_completed_v1", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["level_1"].waitForExistence(timeout: 15))
        app.buttons["level_1"].tap()
        XCTAssertTrue(app.buttons["startLevelButton"].waitForExistence(timeout: 10))
        app.buttons["startLevelButton"].tap()
        XCTAssertTrue(app.buttons["skipTutorialButton"].waitForExistence(timeout: 10))
        app.buttons["skipTutorialButton"].tap()
        let moves = app.staticTexts["movesValue"]
        XCTAssertTrue(moves.waitForExistence(timeout: 10))
        XCTAssertEqual(moves.label.filter(\.isNumber), "20")
        XCTAssertEqual(app.staticTexts["scoreValue"].label.filter(\.isNumber), "0")
        XCTAssertTrue(app.buttons["hintButton"].isEnabled)
        app.buttons["hintButton"].tap()
        XCTAssertTrue(app.buttons["Dismiss Hint"].waitForExistence(timeout: 5))
        app.buttons["Dismiss Hint"].tap()
        attach("guided-play-hint")
    }

    func testHelpReopensPracticeWithoutStartingACampaignSession() {
        app.launch()
        reveal(app.buttons["menuHelpButton"])
        app.buttons["menuHelpButton"].tap()
        reveal(app.buttons["openPracticeFromHelp"])
        app.buttons["openPracticeFromHelp"].tap()
        XCTAssertTrue(app.buttons["skipTutorialButton"].waitForExistence(timeout: 10))
        app.buttons["skipTutorialButton"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["continueButton"].waitForExistence(timeout: 10))
    }

    func testDailyPreviewCanCancelExitThenReturnToMenu() {
        app.launchArguments = ["-emojimatch.learning.tips_seen_v1", "YES",
                               "-emojimatch.learning.tutorial_completed_v1", "YES",
                               "-dailyPuzzle.enabled.v1", "YES"]
        app.launch()
        reveal(app.buttons["playDailyButton"])
        app.buttons["playDailyButton"].tap()
        XCTAssertTrue(app.staticTexts["DAILY PUZZLE"].waitForExistence(timeout: 10))
        app.buttons["exitGameButton"].tap()
        XCTAssertTrue(app.buttons["Keep Playing"].waitForExistence(timeout: 5))
        app.buttons["Keep Playing"].tap()
        XCTAssertEqual(app.staticTexts["movesValue"].label.filter(\.isNumber), "20")
        app.buttons["exitGameButton"].tap()
        XCTAssertTrue(app.buttons["Leave Daily Puzzle"].waitForExistence(timeout: 5))
        app.buttons["Leave Daily Puzzle"].tap()
        XCTAssertTrue(app.buttons["continueButton"].waitForExistence(timeout: 10))
        attach("daily-puzzle-menu")
    }

    private func reveal(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 15))
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
