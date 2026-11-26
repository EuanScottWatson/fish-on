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
    func testCatchCanBeSavedOffline() {
        let app = XCUIApplication()
        app.launchEnvironment["FISH_UI_TEST"] = "offline"
        app.launch()
        XCTAssertTrue(app.buttons["Log a catch"].waitForExistence(timeout: 30))
        app.buttons["Log a catch"].tap()
        let species = app.textFields["Fish species"]
        XCTAssertTrue(species.waitForExistence(timeout: 10))
        species.tap()
        species.typeText("Offline roach")
        let save = app.buttons["Save catch"]
        if !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.buttons["Log a catch"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Catches"].tap()
        XCTAssertTrue(app.staticTexts["Offline roach"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Waiting to sync"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Catches"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Catches"].tap()
        XCTAssertTrue(app.staticTexts["Offline roach"].waitForExistence(timeout: 15))
    }
    func testSurveysAppearOnlyAfterSearch() {
        let app = XCUIApplication()
        app.launchEnvironment["FISH_UI_TEST"] = "1"
        app.launch()
        let nearby = app.buttons["Fish nearby"]
        XCTAssertTrue(nearby.waitForExistence(timeout: 30))
        for _ in 0..<4 where !nearby.isHittable { app.swipeUp() }
        nearby.tap()
        let search = app.buttons["Search this area"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Showing 1 surveys in the searched area. Historic records do not imply fishing access. © Environment Agency."].exists)
        search.tap()
        XCTAssertTrue(app.staticTexts["Showing 1 surveys in the searched area. Historic records do not imply fishing access. © Environment Agency."].waitForExistence(timeout: 20))
    }
    func testDetectorBoxRemainsVisibleWhenIdentificationFails() {
        let app = XCUIApplication()
        app.launchEnvironment["FISH_UI_TEST"] = "1"
        app.launchEnvironment["FISH_UI_IDENTIFY"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["Log a catch"].waitForExistence(timeout: 30))
        app.buttons["Log a catch"].tap()
        XCTAssertTrue(app.buttons["Load test photo"].waitForExistence(timeout: 10))
        app.buttons["Load test photo"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "reached its limit")).firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["fish-selection-box"].exists)
        XCTAssertTrue(app.buttons["Draw or adjust fish box"].exists)
        XCTAssertTrue(app.buttons["Save catch"].exists)
    }
    func testManualBoxRemainsAvailableWhenDetectionFails() {
        let app = XCUIApplication()
        app.launchEnvironment["FISH_UI_TEST"] = "offline"
        app.launchEnvironment["FISH_UI_IDENTIFY"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["Log a catch"].waitForExistence(timeout: 30))
        app.buttons["Log a catch"].tap()
        XCTAssertTrue(app.buttons["Load test photo"].waitForExistence(timeout: 10))
        app.buttons["Load test photo"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Draw a box around it")).firstMatch.waitForExistence(timeout: 20))
        let draw = app.buttons["Draw or adjust fish box"]
        XCTAssertTrue(draw.exists)
        draw.tap()
        XCTAssertTrue(app.navigationBars["Select the fish"].waitForExistence(timeout: 10))
    }
}
