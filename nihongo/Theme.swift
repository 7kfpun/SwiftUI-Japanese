import SwiftUI

/// Visual identity carried over from the RN app (see context/07-ux-ui.md):
/// near-monochrome + one teal accent; green/red reserved for answer feedback.
enum Theme {
    /// One color per appearance — the identity colors need per-mode tuning that the
    /// fixed RN values can't provide (they were designed against white).
    private static func dynamic(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// The course's accent — teal for Minna, orange for JLPT. Brightened in dark so it
    /// keeps its pop against dark surfaces instead of going muddy.
    ///
    /// Read from `Course` rather than fixed here: the two apps build from this one file
    /// and shipping the same accent is what made them look like the same product.
    static let accent = dynamic(UIColor(red: Course.current.accentLight.r,
                                        green: Course.current.accentLight.g,
                                        blue: Course.current.accentLight.b, alpha: 1),
                                UIColor(red: Course.current.accentDark.r,
                                        green: Course.current.accentDark.g,
                                        blue: Course.current.accentDark.b, alpha: 1))
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

    /// Japanese display font for the big word/kana text — **Hiragino Mincho ProN**,
    /// iOS's built-in serif (明朝) face. No bundled font files needed.
    ///
    /// Mincho because that is what the design specifies (its mocks set every Japanese
    /// string in Noto Serif JP, a mincho face, against a sans UI). Noto Serif JP itself
    /// is not on iOS and bundling it would cost megabytes per weight, so this takes the
    /// system face of the same class. Hiragino Mincho carries the modelled brush
    /// contrast a learner is reading *for* — the vertical/horizontal stroke weights that
    /// a rounded gothic flattens away — which matters more here than anywhere else,
    /// because the glyph on screen is the thing being learned rather than chrome.
    ///
    /// ProN, not Pro: JIS2004 glyph shapes, matching what modern Japanese print uses.
    /// Full Latin coverage, so romaji set in it reads as merely plain, never broken —
    /// the invariant in `CLAUDE.md` that outlived three wrong-face slots.
    ///
    /// To swap in a bundled typeface later, change only this name (and `jpBold`).
    static func jp(_ size: CGFloat) -> Font { .custom("HiraMinProN-W3", size: size) }

    /// Bold Japanese display font — Hiragino Mincho ProN W6, the same family's heavy
    /// weight (mincho ships W3 and W6 on iOS, so unlike the old rounded Maru Gothic
    /// this does *not* have to jump families to find a bold). Used for kana glyphs in
    /// Kana modes.
    static func jpBold(_ size: CGFloat) -> Font { .custom("HiraMinProN-W6", size: size) }

    /// Stroke-order font (KanjiStrokeOrders, bundled): glyphs render with numbered
    /// stroke-order annotations, so a learner absorbs stroke order while quizzing. Used by
    /// the kana flashcard face and both kana quizzes' prompts — and the same font file is
    /// Write mode's tracing *and* scoring template (`KanaSketch.strokeOrderFont`), which is
    /// why it can't be swapped for a prettier face.
    static func jpStrokes(_ size: CGFloat) -> Font { .custom("KanjiStrokeOrders", size: size) }

    /// Titles and headings — SF Rounded. **The one place the title face is decided;**
    /// nothing outside `Theme` should name a font design.
    ///
    /// Rounded, and deliberately *not* matched to the Japanese face. `jp` is now a
    /// mincho serif, and the pairing is the design's own: a serif for the Japanese being
    /// taught, a sans for the interface around it (its mocks pair Noto Serif JP with a
    /// sans UI face). The two are meant to read as content and chrome, not as one voice —
    /// so the headings stay rounded SF, which is also the only choice that keeps Dynamic
    /// Type and nineteen languages working.
    ///
    /// Not a bundled display face, deliberately. `design: .rounded` keeps two things a
    /// Latin-only font file would break for the nine non-Latin UI languages: Dynamic
    /// Type, and the system's automatic per-script fallback (a heading in Thai, Burmese,
    /// Tamil or Hangul falls back to that script's own system face rather than to tofu —
    /// SF Rounded covers Latin, Cyrillic and Greek, and nothing else).
    ///
    /// Takes a `Font.TextStyle`, never a point size: `.system(_:design:weight:)` scales
    /// with Dynamic Type, `.system(size:)` doesn't, and this app supports it everywhere.
    /// Body text, subtitles and captions stay on the system font — the contrast between
    /// a rounded heading and a neutral paragraph is what makes it read as a hierarchy
    /// rather than as a theme.
    ///
    /// Two display slots take `display(_:)` below instead, and navigation bar titles come
    /// through `titleUIFont` — everything else that reads as a heading calls this.
    static func title(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }

    /// The title face at a **fixed** point size — the Latin counterpart to `jp`/`jpBold`/
    /// `jpStrokes`, for slots that are *sized* like a Japanese glyph rather than styled
    /// like text.
    ///
    /// Two kinds of caller, both deliberately outside `title(_:)`'s Dynamic Type contract:
    ///
    /// - **Layouts with no slack.** The Challenge result percentage (56) between a stars
    ///   row and a verdict line, and Kana Write's romaji prompt (40) directly above a
    ///   drawing canvas whose height is the thing being drawn on. Through
    ///   `title(.largeTitle)` both would start at 34pt (a visible shrink) and then grow
    ///   with the text size until they pushed those neighbours off screen.
    /// - **The Latin half of a script-switchable slot.** Where the same slot shows kana in
    ///   a Japanese face at some fixed size *or* romaji depending on a setting — the
    ///   browser tiles and their toolbar glyph (26/15), both kana quizzes' prompts
    ///   (120/150) and options (26/30), Train's romaji prompt (44). Those have to take the
    ///   same point size as the Japanese face they alternate with, or switching script
    ///   would resize the card. The Japanese faces have full Latin coverage, so a romaji
    ///   value drawn with one of them looked merely plain rather than broken; this is what
    ///   the Latin side switches to instead.
    ///
    /// Same face as `title(_:)`, so everything matches; it just can't grow.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// UIKit twin of `title(_:)`, for the one heading SwiftUI cannot font: a
    /// `.navigationTitle`. `UINavigationBarAppearance` takes a resolved `UIFont`, so the
    /// face has to be built here rather than named as a `Font.TextStyle`.
    ///
    /// **The `UIFontMetrics` call is load-bearing — do not "simplify" it to
    /// `UIFont.systemFont(ofSize:)` or add a `compatibleWith:` trait collection.** A font
    /// that comes out of `scaledFont(for:maximumPointSize:)` with no trait collection is
    /// *scalable*: the label re-resolves it against its own trait collection every time it
    /// lays out, so a nav title follows a Dynamic Type change made long after launch, and
    /// obeys `maxSize` when it does. Resolve it against a trait collection — or hand over a
    /// plain `systemFont` — and it becomes a fixed size frozen at whatever the text size
    /// was when this ran, which is the bug this shape exists to avoid. Measured on iOS 26:
    /// a bar built at the default size renders 17pt, 20pt after the user moves to the
    /// largest accessibility size, and 17pt again on the way back.
    static func titleUIFont(size: CGFloat,
                            weight: UIFont.Weight,
                            relativeTo style: UIFont.TextStyle,
                            upTo maxSize: CGFloat) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        let rounded = system.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: size) } ?? system
        return UIFontMetrics(forTextStyle: style).scaledFont(for: rounded, maximumPointSize: maxSize)
    }
}
