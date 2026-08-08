import SwiftUI

/// Mirrors the app's `Theme` rather than importing it — the watch target compiles none of
/// the app's code, exactly like the widget target doesn't.
enum WatchTheme {
    /// `Theme.accent`'s dark variant. watchOS has no light appearance, so the brightened
    /// teal is the only one that would ever render; the light value is simply dropped.
    static let accent = Color(red: 0.25, green: 0.78, blue: 0.84)

    /// Same Hiragino Maru Gothic the app uses for big kana. If watchOS ever ships without
    /// it, `Font.custom` falls back to the system face at the same size — the layout is
    /// built on `minimumScaleFactor`, not on this font's exact metrics.
    /// `relativeTo:` is what makes a custom font honour the watch's text-size setting —
    /// without it the glyphs stay put while every system font around them grows. The
    /// caller names the style the size is *meant* to sit at, so a 30pt display kana
    /// scales like a title and a 17pt gloss scales like body text, rather than both
    /// being pinned to `.body` (which is what plain `.custom(_:size:)` does).
    static func jp(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("HiraMaruProN-W4", size: size, relativeTo: style)
    }
}
