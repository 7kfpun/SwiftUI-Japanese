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
        // Skip the first-launch intro. `UserDefaults` parses `-key value` launch arguments
        // into the volatile domain natively, so this satisfies `RootView`'s
        // `!bool(forKey: Pref.introAnswered)` check without a line of app code knowing that
        // tests exist. Required, not cosmetic: the intro is a `fullScreenCover` above the
        // whole TabView, so without it every launch lands on intro card 1 — `test01Today`
        // would save a picture of the tour as `01-today`, and the other tests would fall
        // through their guards and capture nothing while still reporting success.
        app.launchArguments += ["-introAnswered", "YES"]
        app.launch()
    }

    // MARK: - Today

    @MainActor
    func test01Today() throws {
        // Asserted, not discarded like the guarded tests below: Today is the landing tab and
        // needs no navigation, so if its card never appears the capture is wrong rather than
        // merely missing — and a wrong `01-today` feeds straight into the App Store framing
        // script. The other tests tolerate a miss because iPad genuinely can't reach the tab
        // bar (see `openTab`).
        XCTAssertTrue(app.staticTexts["Swipe"].waitForExistence(timeout: 8),
                      "Today's card never appeared — 01-today would capture the wrong screen")
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

    /// The scored half of a lesson — a rung of the Challenge ladder, which is the lesson
    /// test the marketing copy describes.
    ///
    /// Named `12-lesson-quiz` because that key is what
    /// `fastlane/generate_framed_screenshots.py`'s `LOCALES` table carries marketing copy
    /// for in every locale — renaming it would silently drop this shot from every framed
    /// set. Navigates by tapping "Challenge 1" rather than a mode row, which is also why
    /// it doesn't use `openLessonMode`.
    @MainActor
    func test12LessonQuiz() throws {
        openTab("Lessons")
        // "Challenge 1", not "Challenge" — the bare word is also the section header, and two
        // matches make a singular query fail for reasons unrelated to the test.
        guard tap(app.staticTexts["Lesson 1"]),
              wait(app.staticTexts["Vocab List"]),
              tap(app.staticTexts["Challenge 1"]),
              wait(app.buttons["Next"]) else { return }
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
    ///
    /// Known gap: on iPad this reliably lands only on the already-selected tab.
    /// iPadOS 26 renders the `TabView` as a floating "Liquid Glass" pill rather
    /// than a `UITabBar`, so neither query matches something tappable and most
    /// shots silently fall through their `guard` (the test still passes — it just
    /// captures nothing). Retrying on hittability, below, did not fix it. Only
    /// the iPhone captures are complete; iPad has Today + Lessons.
    private func openTab(_ name: String) {
        if !tap(app.tabBars.buttons[name], 3) { tapQuiet(app.buttons[name]) }
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

    /// Tap once the element exists AND is hittable, polling until `timeout` instead
    /// of checking once — a one-shot check right after `waitForExistence` flakes
    /// whenever a screen is still mid-transition (e.g. right after a cold launch).
    @discardableResult
    private func tap(_ e: XCUIElement, _ timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if e.exists, e.isHittable {
                e.tap()
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return false
    }

    /// Tap without caring about the result (optional embellishments).
    private func tapQuiet(_ e: XCUIElement) {
        _ = tap(e, 2)
    }
}
