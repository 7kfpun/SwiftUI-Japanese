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
/// A free-running cursor, not a bounded array index — the buttons step it and the
/// hourly timeline keeps adding to it. Readers go through `wrapped(_:count:)` (floor
/// modulo, never `%` directly), so any cursor value lands on a real word: it may be
/// negative after paging back, and Swift's `%` is truncating — `-1 % 7` is `-1`, which
/// fed straight into `words[...]` would trap.
enum WidgetPosition {
    private static let key = "today.widgetOffset"
    private static var store: UserDefaults? { UserDefaults(suiteName: TodayShared.appGroup) }

    static var offset: Int { store?.integer(forKey: key) ?? 0 }

    /// Move the cursor by `delta` (negative goes back). `&+` so a cursor parked at the
    /// extremes wraps rather than traps — `wrapped` lands it on a real word either way.
    static func step(_ delta: Int) { store?.set(offset &+ delta, forKey: key) }
    static func advance() { step(1) }
    static func rewind() { step(-1) }

    /// Park the cursor on a word directly — what a dot tap does. Absolute rather than
    /// relative: the tapped dot *is* the destination, so there's nothing to accumulate.
    static func jump(to index: Int) { store?.set(index, forKey: key) }

    /// Reset when the deck changes underneath us, so a fresh challenge's words start
    /// at their first entry rather than wherever the last deck had been left.
    static func reset() { store?.set(0, forKey: key) }

    /// Floor modulo — the only safe way to turn the cursor into an array index, since
    /// `%` keeps the sign of the dividend and the cursor isn't bounds-checked.
    static func wrapped(_ value: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let r = value % count           // -(count-1) ... count-1
        return r < 0 ? r + count : r
    }
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
