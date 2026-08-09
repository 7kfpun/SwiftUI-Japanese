import AppIntents
import WidgetKit

/// How far the widget has been paged by hand, kept in the App Group beside the
/// snapshot itself.
///
/// Deliberately separate from the app's own `index` in `TodayView`: tapping the widget
/// shouldn't silently move the card you find when you next open the app, and paging in
/// the app shouldn't yank the widget out from under a glance. They read the same deck
/// and hold their own place in it.
///
/// A free-running *offset*, not a bounded array index. The displayed word is
/// `cursor + hourSlot` — the buttons move the cursor, the clock moves the hour, and the
/// two simply add. Every reader goes through `TodayShared.rotationIndex`, whose
/// `floorMod` is what makes any cursor value (including the negatives paging back
/// produces) land on a real word — see the trap documented there.
enum WidgetPosition {
    private static let key = "today.widgetOffset"
    private static var store: UserDefaults? { UserDefaults(suiteName: TodayShared.appGroup) }

    static var offset: Int { store?.integer(forKey: key) ?? 0 }

    /// Move the cursor by `delta` (negative goes back). `&+` so a cursor parked at the
    /// extremes wraps rather than traps — `rotationIndex` lands it on a real word anyway.
    static func step(_ delta: Int) { store?.set(offset &+ delta, forKey: key) }
    static func advance() { step(1) }
    static func rewind() { step(-1) }

    /// Park the widget on word `index` right now — what a dot tap does.
    ///
    /// Stored *relative to the current hour*, which looks like indirection and isn't: the
    /// displayed word is `cursor + hourSlot`, so writing the tapped index straight into the
    /// cursor would show that index plus every hour elapsed since 1970. Subtracting the
    /// current hour slot is what makes "show me this dot" mean this dot.
    static func jump(to index: Int) {
        store?.set(index - TodayShared.hourSlot(), forKey: key)
    }

    /// Reset when the deck changes underneath us, so a fresh challenge's words start
    /// at their first entry rather than wherever the last deck had been left.
    static func reset() { jump(to: 0) }
}

/// The widget's "next word" button. WidgetKit reloads the timeline once this returns,
/// so the new word appears without opening the app.
struct NextWordIntent: AppIntent {
    static var title: LocalizedStringResource = "Next word"
    static var isDiscoverable = false   // a widget affordance, not a Shortcuts action

    func perform() async throws -> some IntentResult {
        WidgetPosition.advance()
        return .result()
    }
}

/// The mirror of `NextWordIntent`, moving the same cursor the other way. Paging by hand
/// and the hourly timeline share one cursor on purpose: a tap doesn't fight the clock,
/// and stepping back then waiting resumes from where you left off rather than jumping.
struct PreviousWordIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous word"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        WidgetPosition.rewind()
        return .result()
    }
}

/// A page dot's tap: show word `target` directly, skipping the walk the arrows would
/// take. Same cursor as the arrows and the hourly timeline, so none of the three fight.
struct JumpToWordIntent: AppIntent {
    static var title: LocalizedStringResource = "Show word"
    static var isDiscoverable = false

    @Parameter(title: "Word")
    var target: Int

    init() {}
    init(target: Int) { self.target = target }

    func perform() async throws -> some IntentResult {
        WidgetPosition.jump(to: target)
        return .result()
    }
}
