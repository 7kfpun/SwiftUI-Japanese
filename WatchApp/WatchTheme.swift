import SwiftUI

/// Mirrors the app's `Theme` rather than importing it — the watch target compiles none of
/// the app's code, exactly like the widget target doesn't.
enum WatchTheme {
    /// `Theme.accent`'s dark variant. watchOS has no light appearance, so the brightened
    /// teal is the only one that would ever render; the light value is simply dropped.
    static let accent = Color(red: 0.25, green: 0.78, blue: 0.84)

    /// The watch **cannot** follow the app's Japanese face, and this names what it can.
    ///
    /// `Theme.jp` is Hiragino Mincho ProN. watchOS 26.5 ships exactly one Japanese
    /// family — Hiragino Kaku Gothic (`HiraginoKakuGothic.ttc`) — with no Mincho and no
    /// Maru Gothic in its font set at all. So the previous `HiraMaruProN-W4` here never
    /// resolved either: `Font.custom` silently fell back to the system face, and the
    /// watch has been rendering Kaku Gothic the whole time under a name that suggested
    /// otherwise. Naming `HiraginoSans-W3` states the truth instead of relying on a
    /// fallback, and it is a genuinely better fit for the watch besides — mincho's thin
    /// horizontals are the first thing to disappear at 40mm.
    ///
    /// `relativeTo:` is what makes a custom font honour the watch's text-size setting —
    /// without it the glyphs stay put while every system font around them grows. The
    /// caller names the style the size is *meant* to sit at, so a 30pt display kana
    /// scales like a title and a 17pt gloss scales like body text, rather than both
    /// being pinned to `.body` (which is what plain `.custom(_:size:)` does).
    static func jp(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("HiraginoSans-W3", size: size, relativeTo: style)
    }
}
