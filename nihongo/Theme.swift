import SwiftUI

/// Visual identity carried over from the RN app (see context/07-ux-ui.md):
/// near-monochrome + one teal accent; green/red reserved for answer feedback.
enum Theme {
    /// One color per appearance — the identity colors need per-mode tuning that the
    /// fixed RN values can't provide (they were designed against white).
    private static func dynamic(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    // Teal accent (iOSColors.tealBlue) — brightened in dark so it keeps its pop
    // against dark surfaces instead of going muddy.
    static let accent  = dynamic(UIColor(red: 0.06, green: 0.69, blue: 0.75, alpha: 1),
                                 UIColor(red: 0.25, green: 0.78, blue: 0.84, alpha: 1))
    // Feedback colors (#2ECC40 / #FF4136) — softened in dark so they read as
    // right/wrong without glowing neon on near-black.
    static let correct = dynamic(UIColor(red: 0.18, green: 0.80, blue: 0.25, alpha: 1),
                                 UIColor(red: 0.30, green: 0.78, blue: 0.40, alpha: 1))
    static let wrong   = dynamic(UIColor(red: 1.00, green: 0.25, blue: 0.21, alpha: 1),
                                 UIColor(red: 1.00, green: 0.45, blue: 0.41, alpha: 1))

    // Cards must sit LIGHTER than the screen in both modes: white on gray in light,
    // elevated gray on black in dark. The system pair inverts that relationship in
    // dark (black cards on gray), so the two roles swap for dark.
    static let surface = dynamic(.systemBackground, .secondarySystemBackground)
    static let canvas  = dynamic(.secondarySystemBackground, .systemBackground)

    /// Card/tile hairline. `.separator` is fine on light but near-invisible on the
    /// elevated dark surface, so dark uses a stronger white-alpha line.
    static let line = dynamic(.separator, UIColor(white: 1, alpha: 0.22))

    /// Card drop shadow. Black shadows vanish on a dark canvas — there the lift
    /// comes from the lighter surface + `line` border, so the shadow goes clear.
    static let shadow = dynamic(UIColor(white: 0, alpha: 0.10), .clear)

    /// Japanese display font for the big word/kana text — iOS's built-in rounded
    /// Hiragino Maru Gothic (no bundled font files needed). To swap in a bundled
    /// typeface later (e.g. Zen Maru Gothic), change only this name.
    static func jp(_ size: CGFloat) -> Font { .custom("HiraMaruProN-W4", size: size) }

    /// Bold Japanese display font (the rounded Maru has no bold weight on iOS, so
    /// this uses the built-in Hiragino Sans W6). Used for kana glyphs in Kana modes.
    static func jpBold(_ size: CGFloat) -> Font { .custom("HiraginoSans-W6", size: size) }

    /// Stroke-order font (KanjiStrokeOrders, bundled): glyphs render with numbered
    /// stroke-order annotations — used for the quiz prompt so learners absorb stroke
    /// order while quizzing.
    static func jpStrokes(_ size: CGFloat) -> Font { .custom("KanjiStrokeOrders", size: size) }
}
