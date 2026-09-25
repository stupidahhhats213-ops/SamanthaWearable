import XCTest

final class BubbleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsSamanthaBubble() {
        let app = launch()
        XCTAssertTrue(bubble(app).waitForExistence(timeout: 8))
    }

    func testTapOpensPrimaryMenu() {
        let app = launch()
        bubble(app).tap()
        XCTAssertTrue(app.buttons["bubbleHermes"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["bubbleVoice"].exists)
        XCTAssertTrue(app.buttons["bubbleProjects"].exists)
        XCTAssertTrue(app.buttons["bubbleSystem"].exists)
        XCTAssertTrue(app.buttons["bubbleLogs"].exists)
        XCTAssertTrue(app.buttons["bubbleSettings"].exists)
    }

    func testBackdropTapClosesMenu() {
        let app = launch()
        bubble(app).tap()
        let backdrop = app.otherElements["bubbleBackdrop"]
        XCTAssertTrue(backdrop.waitForExistence(timeout: 4))
        backdrop.tap()
        XCTAssertFalse(app.buttons["bubbleHermes"].waitForExistence(timeout: 2))
    }

    func testSettingsNavigationKeepsBubble() {
        let app = launch()
        bubble(app).tap()
        app.buttons["bubbleSettings"].tap()
        XCTAssertTrue(app.otherElements["settingsScreen"].waitForExistence(timeout: 4))
        XCTAssertTrue(bubble(app).exists)
        XCTAssertFalse(app.buttons["bubbleHermes"].exists)
    }

    func testBubbleSurvivesRelaunch() {
        let app = launch()
        XCTAssertTrue(bubble(app).waitForExistence(timeout: 8))
        app.terminate()
        let again = launch()
        XCTAssertTrue(bubble(again).waitForExistence(timeout: 8))
    }

    func testScrollDoesNotMoveBubble() {
        let app = launch()
        let before = frame(bubble(app))
        let scroll = app.scrollViews["homeScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 4))
        scroll.swipeUp()
        scroll.swipeUp()
        scroll.swipeDown()
        let after = frame(bubble(app))
        XCTAssertEqual(before.midX, after.midX, accuracy: 3)
        XCTAssertEqual(before.midY, after.midY, accuracy: 3)
    }

    func testLongPressDragSnapsAndDoesNotOpenMenu() {
        let app = launch()
        let start = frame(bubble(app))
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.45))
        bubble(app).press(forDuration: 0.6, thenDragTo: left)
        let dragged = frame(bubble(app))
        XCTAssertLessThan(dragged.midX, app.frame.midX)
        XCTAssertGreaterThan(abs(dragged.midX - start.midX), 8)
        XCTAssertFalse(app.buttons["bubbleHermes"].exists)
        bubble(app).tap()
        let menu = app.buttons["bubbleHermes"]
        XCTAssertTrue(menu.waitForExistence(timeout: 4))
        XCTAssertGreaterThan(menu.frame.midX, dragged.midX)
    }

    func testHermesNestedMenuThenShellStaysVisible() {
        let app = launch()
        bubble(app).tap()
        app.buttons["bubbleHermes"].tap()
        XCTAssertTrue(app.buttons["bubbleHermesOpen"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["bubbleBack"].exists)
        app.buttons["bubbleHermesOpen"].tap()
        XCTAssertTrue(app.navigationBars["HERMES"].waitForExistence(timeout: 4))
        XCTAssertTrue(bubble(app).exists)
        XCTAssertFalse(app.buttons["bubbleHermesOpen"].exists)
    }

    func testResetReturnsBubbleToRightSide() {
        let app = launch()
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.4))
        bubble(app).press(forDuration: 0.6, thenDragTo: left)
        XCTAssertLessThan(frame(bubble(app)).midX, app.frame.midX)
        bubble(app).tap()
        app.buttons["bubbleSettings"].tap()
        app.buttons["APPEARANCE"].tap()
        let reset = app.buttons["bubbleResetPosition"]
        XCTAssertTrue(reset.waitForExistence(timeout: 4))
        reset.tap()
        XCTAssertGreaterThan(frame(bubble(app)).midX, app.frame.midX)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launch()
        return app
    }

    private func bubble(_ app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["samanthaBubble"]
        if button.exists { return button }
        return app.otherElements["samanthaBubble"]
    }

    private func frame(_ element: XCUIElement) -> CGRect {
        XCTAssertTrue(element.waitForExistence(timeout: 4))
        return element.frame
    }
}
