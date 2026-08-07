//
//  ScreenshotTests.swift
//  nihongoUITests
//
//  Captures polished screenshots of every feature (as kept XCTest attachments —
//  export with `xcrun xcresulttool export attachments`). Launches with
//  "-SCREENSHOTS" so the app hides the ad banner (AdBanner.swift).
//
//  One small test per screen: each launches the app fresh, so a simulator
//  hiccup or app crash costs one shot, not the whole run. Steps are guarded —
//  a missing element skips the shot instead of failing everything.
//

import XCTest

final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-SCREENSHOTS"]
        app.launch()
    }

    // MARK: - Today

    @MainActor
    func test01Today() throws {
        _ = app.staticTexts["Swipe"].waitForExistence(timeout: 8)   // card loaded
        shot("01-today")
    }

    // MARK: - Kana

    @MainActor
    func test02KanaTable() throws {
        openTab("Kana")
        guard wait(app.staticTexts["あ"]) else { return }
        shot("02-kana-table")
    }

    @MainActor
    func test03KanaFlashcards() throws {
        guard openKanaMode("Flashcards"), wait(app.buttons["Reveal"]) else { return }
        tapQuiet(app.buttons["Reveal"])
        shot("03-kana-flashcards")
    }

    @MainActor
    func test04KanaQuizClassic() throws {
        guard openKanaMode("Classic"), wait(app.buttons["Next"]) else { return }
        shot("04-kana-quiz-classic")
    }

    @MainActor
    func test05KanaSwipe() throws {
        guard openKanaMode("Swipe"), wait(app.buttons["romaji"]) else { return }
        shot("05-kana-swipe")
    }

    @MainActor
    func test06KanaListening() throws {
        guard openKanaMode("Listening"),
              wait(app.staticTexts["Hear it, pick the word"]) else { return }
        shot("06-kana-listening")
    }

    @MainActor
    func test07KanaWrite() throws {
        guard openKanaMode("Write"), wait(app.navigationBars["Write"]) else { return }
        shot("07-kana-write")
    }

    // MARK: - Lessons

    @MainActor
    func test08Lessons() throws {
        openTab("Lessons")
        guard wait(app.staticTexts["Lesson 1"]) else { return }
        shot("08-lessons")
    }

    @MainActor
    func test09VocabList() throws {
        guard openLessonMode("Vocab List"), wait(app.buttons["Play all"]) else { return }
        shot("09-vocab-list")
    }

    @MainActor
    func test10LessonFlashcards() throws {
        guard openLessonMode("Flashcards"), wait(app.buttons["Show meaning"]) else { return }
        tapQuiet(app.buttons["Show meaning"])
        shot("10-lesson-flashcards")
    }

    @MainActor
    func test11LessonLearn() throws {
        guard openLessonMode("Learn"), wait(app.buttons["Ordered"]) else { return }
        shot("11-lesson-learn")
    }

    @MainActor
    func test12LessonQuiz() throws {
        guard openLessonMode("Quiz"), wait(app.buttons["Next"]) else { return }
        shot("12-lesson-quiz")
    }

    // MARK: - Settings + paywall

    @MainActor
    func test13Settings() throws {
        openTab("Settings")
        guard wait(app.buttons["Unlock all lessons"]) else { return }
        shot("13-settings")
    }

    @MainActor
    func test14Paywall() throws {
        openTab("Settings")
        guard tap(app.buttons["Unlock all lessons"]),
              wait(app.buttons["Cancel"]) else { return }
        _ = app.staticTexts["Restore Purchases"].waitForExistence(timeout: 3)
        shot("14-paywall")
    }

    // MARK: - Navigation helpers

    /// Kana tab → Quiz → the given mode row.
    private func openKanaMode(_ mode: String) -> Bool {
        openTab("Kana")
        guard tap(app.buttons["Quiz"]), wait(app.staticTexts["Classic"]) else { return false }
        return tap(app.staticTexts[mode])
    }

    /// Lessons tab → Lesson 1 → the given mode row.
    private func openLessonMode(_ mode: String) -> Bool {
        openTab("Lessons")
        guard tap(app.staticTexts["Lesson 1"]), wait(app.staticTexts["Vocab List"]) else { return false }
        return tap(app.staticTexts[mode])
    }

    /// Switch tab (tab bar buttons; falls back to a plain button match).
    private func openTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        if tab.waitForExistence(timeout: 3) { tab.tap() }
        else { tapQuiet(app.buttons[name]) }
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Small utilities

    /// Save the current screen as a kept attachment.
    @MainActor private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.8)   // let animations settle
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func wait(_ e: XCUIElement, _ timeout: TimeInterval = 5) -> Bool {
        e.waitForExistence(timeout: timeout)
    }

    /// Tap if it appears in time; report whether it was tapped.
    @discardableResult
    private func tap(_ e: XCUIElement, _ timeout: TimeInterval = 5) -> Bool {
        guard e.waitForExistence(timeout: timeout), e.isHittable else { return false }
        e.tap()
        return true
    }

    /// Tap without caring about the result (optional embellishments).
    private func tapQuiet(_ e: XCUIElement) {
        if e.waitForExistence(timeout: 2), e.isHittable { e.tap() }
    }
}
