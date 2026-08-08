import SwiftUI

/// Which tab is showing and where the Lessons stack is parked.
///
/// Both normally belong to the views that own them, and they'd stay there if taps were
/// the only way to navigate. The widget changes that: "Ready for Challenge 3?" has to
/// land the user in a tab they aren't on, which no amount of local `@State` can
/// express. Hoisting just these two makes that reachable while leaving every other
/// screen's navigation alone.
@Observable final class Router {
    enum Tab: Hashable { case today, kana, lessons, settings }

    var tab: Tab = .today
    /// The Lessons tab's stack. Ordinary row taps append to this too, so a deep link and
    /// a tap leave the user in the same place, with a working back button either way.
    var lessonPath = NavigationPath()

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
}
