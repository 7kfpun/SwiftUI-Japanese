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
    static func jp(_ size: CGFloat) -> Font { .custom("HiraMaruProN-W4", size: size) }
}
