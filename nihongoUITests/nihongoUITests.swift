import XCTest

final class nihongoUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A launched app with the first-launch intro already answered.
    ///
    /// The intro is a `fullScreenCover` above the whole TabView, so without the argument
    /// every assertion in every test races a tour it can never dismiss. `UserDefaults`
    /// parses `-key value` launch arguments into the volatile domain natively, so this
    /// satisfies `RootView`'s check with no app code knowing that tests exist.
    @MainActor private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-introAnswered", "YES"]
        app.launch()
        return app
    }

    @MainActor
    func testKanaBrowserAndQuizFlow() throws {
        let app = launchApp()

        // Kana browser grid loaded (the あ tile).
        XCTAssertTrue(app.staticTexts["あ"].waitForExistence(timeout: 5))

        // Switch kana set via the segmented control.
        let dakuon = app.segmentedControls.buttons["濁音"]
        if dakuon.waitForExistence(timeout: 2) { dakuon.tap() }

        // Enter the quiz; the Next button is the anchor of the quiz screen.
        XCTAssertTrue(app.buttons["Quiz"].waitForExistence(timeout: 5))
        app.buttons["Quiz"].tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLessonsToLearnFlow() throws {
        let app = launchApp()

        app.buttons["Lessons"].tap()
        XCTAssertTrue(app.staticTexts["Lesson 1"].waitForExistence(timeout: 5))

        app.staticTexts["Lesson 1"].tap()
        XCTAssertTrue(app.staticTexts["Learn"].waitForExistence(timeout: 5))

        app.staticTexts["Learn"].tap()
        // Learn screen shows the field-visibility toggle bar (漢 button) + a lesson counter title.
        XCTAssertTrue(app.buttons["漢"].waitForExistence(timeout: 5))
        attach(app, "learn")
    }

    /// Save a screenshot as a kept attachment (exported via xcresulttool).
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    @MainActor
    func testSearchFindsVocab() throws {
        let app = launchApp()

        app.buttons["Lessons"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("watashi")
        // A result row should appear (translation "I").
        XCTAssertTrue(app.staticTexts["わたし"].waitForExistence(timeout: 5))
    }
}
