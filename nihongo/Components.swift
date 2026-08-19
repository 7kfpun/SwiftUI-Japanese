import SwiftUI

/// Toolbar button toggling the app-wide auto-play sound setting (`Pref.soundOn`) —
/// the same flag the Learn/Flashcards/Today toggles use, so it's global.
struct SoundToggle: View {
    @AppStorage(Pref.soundOn) private var soundOn = true

    var body: some View {
        Button {
            soundOn.toggle()
            Track.event("toggle_sound", ["on": soundOn])
        } label: {
            Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
        }
        .accessibilityLabel(soundOn ? "Turn sound off" : "Turn sound on")
    }
}

/// One consistent score indicator used by every scored screen in the app (Kana classic,
/// Kana swipe, Kana write, Train, and the Challenge ladder). Shows right / wrong / total.
struct ScoreBadge: View {
    let correct: Int
    let total: Int
    private var wrong: Int { total - correct }

    var body: some View {
        HStack(spacing: 14) {
            stat("checkmark", correct, Theme.correct)
            stat("xmark", wrong, Theme.wrong)
            Text("/ \(total)")
                .font(.footnote.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(.tertiarySystemFill)))
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(correct) correct, \(wrong) wrong, \(total) total")
    }

    private func stat(_ icon: String, _ n: Int, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).imageScale(.small)
            Text("\(n)").monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(color)
    }
}

/// A mode row: accent icon, name in the title face, one-line description under it — used by
/// both mode pickers (`SelectModeView`'s four Learn modes and `KanaQuizModeView`'s five kana
/// modes), which are the same list of the same shape in two tabs.
///
/// The name is a heading and takes the title face; the subtitle is a sentence about it and
/// stays on the system font. `locked` greys the icon and adds the padlock — only the Lessons
/// side ever passes it, since Kana is free in full.
struct ModeRow: View {
    let icon: String, title: String, subtitle: String
    var locked = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 30)
                .foregroundStyle(locked ? Color.secondary : Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.title(.headline))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            if locked {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .foregroundStyle(.primary)   // keep the label neutral inside a plain Button
    }
}

/// A quiz answer button that fills the space it's given. Shared by the two
/// multiple-choice quizzes (the Challenge ladder and the classic kana quiz) so they
/// look identical.
///
/// Takes the answer state rather than a pre-computed colour, so the idle/correct/
/// wrong rules live here instead of being re-derived at each call site.
struct QuizOptionButton: View {
    let text: String
    /// This button's position in the grid.
    let index: Int
    /// Which option was chosen; nil while the question is still open.
    let picked: Int?
    /// Whether this button holds the correct answer.
    let isAnswer: Bool
    var font: Font = .headline   // kana quizzes pass a bigger Japanese face
    let action: () -> Void

    private var answered: Bool { picked != nil }
    private var isPicked: Bool { picked == index }
    /// Neither chosen nor correct — dimmed once the question is settled, so the two
    /// buttons that matter carry the eye.
    private var isAlsoRan: Bool { answered && !isAnswer && !isPicked }

    private var color: Color {
        guard answered else { return Theme.accent }
        if isAnswer { return Theme.correct }
        return isPicked ? Theme.wrong : Theme.line
    }

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(font)
                .foregroundStyle(answered ? color : .primary)   // the word reads as text
                .multilineTextAlignment(.center)
                // 0.65, not 0.5. The rows are a fixed 74pt (see `OptionGrid`) and the
                // longest Minna glosses are sentence-length parentheticals, so the floor is
                // what actually gets rendered for the tail of the data. Measured with
                // CoreText over all 37 602 translations in the 18 languages: at 0.5 the
                // worst cases land at 8.5pt (Burmese) and 8.8pt (German, Vietnamese) — below
                // anything readable — while 0.65 holds every language at 11.2pt or better.
                // The cost is 46 glosses that tail-truncate instead of shrinking rather than
                // 14, i.e. 0.12% of the data instead of 0.04%: a clipped tail on a
                // sentence-long gloss beats 8pt text on all four buttons. Nepali (18th)
                // was re-measured against this box: Devanagari runs tall, not wide, and
                // its worst gloss fits at 0.68 — above the floor, adding no truncation.
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Raised card, not an outlined box: depth carries "tappable" while the
        // question is open, so no colour has to. A tinted fill on four large targets
        // read as a slab competing with the prompt, and an accent outline on all four
        // wasn't much quieter — both spent the palette on the resting state. Colour
        // now appears only with the verdict, which is the moment it means something.
        .background(answered ? color.opacity(0.12) : Theme.surface,
                    in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: answered ? .clear : Theme.shadow, radius: 5, y: 2)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(answered ? color : .clear, lineWidth: 2))
        // Corner badge rather than inline, so revealing the verdict doesn't reflow
        // the label. Colour alone would exclude red/green colourblind users.
        .overlay(alignment: .topTrailing) {
            if answered, isAnswer || isPicked {
                Image(systemName: isAnswer ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(color)
                    .padding(7)
            }
        }
        .opacity(isAlsoRan ? 0.45 : 1)
        .animation(.easeOut(duration: 0.2), value: answered)
        .disabled(answered)
    }
}

extension View {
    /// Shared chrome for every choice control on a Tinder-like screen — light tint
    /// fill + colored border, foreground tinted to match. Used by the flashcard
    /// grade buttons and the kana swipe quiz's option chips so both look like one
    /// design language instead of two (pill buttons vs. bordered boxes).
    func choiceChip(_ color: Color) -> some View {
        foregroundStyle(color)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(color, lineWidth: 2))
    }
}

/// One of the two candidates on a swipe-to-choose screen — shared by Train (vocab)
/// and the kana swipe quiz, which pose the same question about different content.
///
/// The word is the content and gets the weight; the arrow is only an instruction, so
/// it's a chevron on the chip's *outer* edge, pointing the way you'd swipe. A centred
/// arrow says that less clearly while competing with the text for attention.
///
/// After answering the chevron gives way to a check/cross, so the verdict never rests
/// on colour alone — red/green are the same colour to roughly 8% of men.
struct SwipeOptionChip: View {
    let text: String
    /// 0 = left chip (swipe left to pick), 1 = right.
    let side: Int
    /// Which side was chosen; nil while the question is still open.
    let picked: Int?
    /// Whether this chip holds the correct answer.
    let isAnswer: Bool
    /// Kana readings are short and want to be large; vocab glosses run long and don't.
    /// Title-sized but deliberately *not* `Theme.title` at any call site: an answer you
    /// pick is content, and the two Japanese call sites pass their own face anyway.
    var font: Font = .title3.weight(.semibold)
    /// Choosing this option. Swiping the card is the headline gesture, but tapping the
    /// chip has to work too — it's the obvious thing to try, and these looked tappable
    /// long before they were.
    let action: () -> Void

    private var answered: Bool { picked != nil }
    private var isPicked: Bool { picked == side }

    private var color: Color {
        guard answered else { return Theme.accent }
        if isAnswer { return Theme.correct }
        return isPicked ? Theme.wrong : Theme.line
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if side == 0 { marker }
                Text(text)
                    .font(font)
                    .foregroundStyle(answered ? color : .primary)   // reads as text, not a link
                    // Wrap first, shrink second. The chip has a `minHeight`, not a fixed
                    // height, so a long gloss is allowed to make it taller — but
                    // `lineLimit(3)` capped it before it could, and 0.4 of `.title3` is 8pt.
                    // Measured over all 37 602 translations in the 18 languages: at (3, 0.4)
                    // the worst cases in English, French, German, Vietnamese and Burmese all
                    // bottomed out at the 8pt floor; at (4, 0.6) nothing renders below 12pt
                    // and the share that tail-truncates instead only moves from 0.08% to
                    // 0.15%. Nepali's worst gloss fits at 0.72, well above the floor.
                    .minimumScaleFactor(0.6)
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                if side == 1 { marker }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 96)   // min, not fixed: long glosses need room
            .contentShape(Rectangle())                   // the whole chip is the target
        }
        .buttonStyle(.plain)
        .choiceChip(color)
        .disabled(answered)
    }

    /// Direction chevron before answering, verdict icon after. The unpicked wrong chip
    /// keeps a faint placeholder so the row doesn't shift when icons appear.
    @ViewBuilder private var marker: some View {
        Group {
            if answered {
                if isAnswer { Image(systemName: "checkmark.circle.fill") }
                else if isPicked { Image(systemName: "xmark.circle.fill") }
                else { Image(systemName: "circle").opacity(0.25) }
            } else {
                Image(systemName: side == 0 ? "chevron.left" : "chevron.right")
                    .fontWeight(.semibold)
            }
        }
        .font(.subheadline)
        .frame(width: 18)
    }
}

/// The card face every swipeable screen draws: surface, hairline border, shadow, the
/// ⟨ Swipe ⟩ hint, the corner stamps, and the tilt-and-slide that follows a drag.
///
/// Shared by all four — Today, Flashcards, Train, the kana swipe quiz — which had
/// drifted into four copies of the same chrome with four different corner radii and
/// three separate copies of the stamp-opacity arithmetic. What stays with each caller
/// is the part that genuinely differs: the *meaning* of a swipe. Flashcards grade
/// yourself, Train and the kana quiz pick an answer, Today just turns the page. Same
/// gesture, different verbs — so this owns the looks and the callers own the logic.
///
/// The peek stack stays outside on purpose: it must not move with the card, and
/// Today drives movement through `cardPager` rather than a drag binding.
struct SwipeCard<Content: View>: View {
    /// Live drag translation. Leave at zero when something else (e.g. `cardPager`)
    /// is doing the moving.
    var drag: CGSize = .zero
    /// Distance at which a swipe counts — also what the stamps fade in against.
    var threshold: CGFloat = 100
    /// Corner stamps for a leftward / rightward swipe; nil for screens where a swipe
    /// carries no verdict, like Today's paging.
    var leftStamp: (name: String, color: Color)? = nil
    var rightStamp: (name: String, color: Color)? = nil
    /// Suppress the stamps once the answer is in, so they don't flash on the way out.
    var showsStamps = true
    /// Hidden when there's nowhere to swipe to (a single-card deck).
    var showsHint = true
    @ViewBuilder var content: () -> Content

    private static var radius: CGFloat { 20 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.radius)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: Self.radius).stroke(Theme.line, lineWidth: 1))
                .shadow(color: Theme.shadow, radius: 8, y: 4)
            content()
        }
        .overlay(alignment: .topTrailing) { stamp(rightStamp, rotation: 8, active: drag.width > 0) }
        .overlay(alignment: .topLeading) { stamp(leftStamp, rotation: -8, active: drag.width < 0) }
        .overlay(alignment: .bottom) {
            if showsHint {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.compact.left")
                    Text(L.t("Swipe"))
                    Image(systemName: "chevron.compact.right")
                }
                .font(.caption).foregroundStyle(.tertiary).padding(.bottom, 8)
            }
        }
        .offset(x: drag.width, y: drag.height / 10)
        .rotationEffect(.degrees(Double(drag.width / 22)))
        .contentShape(Rectangle())
    }

    /// Fades in with the drag, so the stamp reaches full strength exactly where the
    /// swipe would commit — the feedback that tells you you've pulled far enough.
    @ViewBuilder
    private func stamp(_ spec: (name: String, color: Color)?, rotation: Double, active: Bool) -> some View {
        if let spec {
            SwipeStamp(systemImage: spec.name, color: spec.color, rotation: rotation)
                .opacity(showsStamps && active ? min(abs(drag.width) / threshold, 1) : 0)
                .padding(16)
        }
    }
}

/// The full-screen verdict that flashes over a swipe-to-answer screen — Train and the
/// kana swipe quiz, which both answer by flinging the card and so have no button left to
/// change colour. Non-interactive on purpose: it appears for half a second while the card
/// leaves and must not swallow the next gesture.
struct AnswerBadge: View {
    let correct: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 72))
            Text(correct ? L.t("Correct!") : L.t("Wrong")).font(Theme.title(.title, weight: .bold))
        }
        .foregroundStyle(correct ? Theme.correct : Theme.wrong)
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .transition(.scale.combined(with: .opacity))
        .allowsHitTesting(false)
    }
}

/// Tinder-style corner stamp for swipeable cards — one consistent visual language
/// for every drag-to-decide screen in the app (flashcards, kana swipe quiz).
struct SwipeStamp: View {
    let systemImage: String
    let color: Color
    let rotation: Double

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(color)
            .padding(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 3))
            .rotationEffect(.degrees(rotation))
    }
}

/// Faded, rotated cards peeking out behind a swipeable top card — reads as a real
/// deck. Purely decorative: it never moves, only the top card being dragged does.
struct CardStackPeek: View {
    var count: Int = 2   // how many peek layers to show (0–2)

    private var layer: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line, lineWidth: 1))
    }

    var body: some View {
        Group {
            // Rotation alone reveals the peek corners at the sides. No vertical
            // offset: a same-size card nudged downward pokes out past the bottom
            // edge, into whatever sits right below (grade/option buttons) — this
            // stays fully behind the top card instead.
            if count > 1 { layer.rotationEffect(.degrees(-6)).opacity(0.5) }
            if count > 0 { layer.rotationEffect(.degrees(3.5)).opacity(0.75) }
        }
    }
}

/// 2×2 grid of quiz options.
///
/// Rows have a set height rather than expanding to fill. Letting them grow made the
/// answers as large as the prompt above them — and on a quiz the question should be
/// the thing that dominates; the options only need to be comfortably tappable.
struct OptionGrid<Cell: View>: View {
    let count: Int
    var rowHeight: CGFloat = 74
    let cell: (Int) -> Cell

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<2) { row in
                HStack(spacing: 12) {
                    ForEach(0..<2) { col in
                        let i = row * 2 + col
                        if i < count { cell(i) } else { Color.clear }
                    }
                }
                .frame(height: rowHeight)
            }
        }
    }
}
