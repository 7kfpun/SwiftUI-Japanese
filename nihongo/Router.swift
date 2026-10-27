import SwiftUI

/// Which tab is showing and where the Lessons stack is parked.
///
/// Both normally belong to the views that own them, and they'd stay there if taps were
/// the only way to navigate. The widget changes that: "Ready for Challenge 3?" has to
/// land the user in a tab they aren't on, which no amount of local `@State` can
/// express. Hoisting just these two makes that reachable while leaving every other
/// screen's navigation alone.
@Observable final class Router {
    enum Tab: Hashable { case today, kana, lessons, progress, settings }

    var tab: Tab = .today
    /// The Lessons tab's stack. Ordinary row taps append to this too, so a deep link and
    /// a tap leave the user in the same place, with a working back button either way.
    var lessonPath = NavigationPath()
    /// The lesson whose Read along screen is currently up, if any. A Live Activity tap
    /// while that screen is already showing must not rebuild the stack: rebuilding
    /// disposes the player, which stops the audio the tap was meant to return to.
    var readAlongLesson: Int?

    /// Pushed after a `Lesson` so back lands on the mode list, not on a dead end.
    struct ReadAlongRoute: Hashable {
        let lesson: Int
    }

    /// Replay the first-launch tour on demand — the hidden long-press in Settings.
    ///
    /// Here for the same reason `tab` is: the trigger lives in a tab and the cover lives
    /// above the whole `TabView`, which no amount of local `@State` in `SettingsView` can
    /// reach. Deliberately *not* `Pref.introAnswered` — that flag records "this person has
    /// been shown the tour", which stays true; replaying it is a separate, transient act,
    /// and conflating the two would make a developer's replay look like a fresh install.
    var replayIntro = false

    /// Just the Lessons tab, at its root. Where a link lands when the rung it names is
    /// behind the paywall: the list is the honest destination, since pushing into a
    /// lesson the user can't open would only dead-end them a screen deeper.
    func openLessonList() {
        lessonPath = NavigationPath()
        tab = .lessons
    }

    /// Lessons tab → this lesson's mode list.
    ///
    /// Deliberately stops here rather than pushing the challenge itself. Dropping
    /// someone straight into a scored test they didn't choose to start produces
    /// abandons, not attempts — the rung is one more tap away, and that tap is the
    /// difference between being asked and being committed.
    ///
    /// Rebuilt from empty rather than appended, so a second link doesn't stack lessons
    /// on top of wherever the user had wandered.
    func openLesson(_ lesson: Lesson) {
        var path = NavigationPath()
        path.append(lesson)
        lessonPath = path
        tab = .lessons
    }

    /// Lessons tab → this lesson's mode list → Read along, on the full word list.
    ///
    /// Japanese-only Read along is free on every lesson, so this does not stop at the
    /// paywall the way a locked challenge link does. When the player is already up for
    /// this lesson, only the tab changes.
    func openReadAlong(_ lesson: Lesson) {
        tab = .lessons
        if readAlongLesson == lesson.number { return }
        var path = NavigationPath()
        path.append(lesson)
        path.append(ReadAlongRoute(lesson: lesson.number))
        lessonPath = path
    }
}
