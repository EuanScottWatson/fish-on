import XCTest

final class FishOnUITests: XCTestCase {
    func testLogCatchAgainstDisposableServer() {
        let app = XCUIApplication()
        app.launchEnvironment["FISH_UI_TEST"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["Log a catch"].waitForExistence(timeout: 30))
        app.buttons["Log a catch"].tap()
        let species = app.textFields["Fish species"]
        XCTAssertTrue(species.waitForExistence(timeout: 10))
        species.tap()
        species.typeText("Test perch")
        let save = app.buttons["Save catch"]
        if !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.buttons["Log a catch"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Catches"].tap()
        XCTAssertTrue(app.staticTexts["Test perch"].waitForExistence(timeout: 20))
    }
}
