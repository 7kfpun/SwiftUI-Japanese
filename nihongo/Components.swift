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

/// The status readout every practice screen puts in the centre of its navigation bar:
/// a capsule holding the numbers, and — where the run has a shape worth naming — a
/// caption under it.
///
/// One component rather than each screen assembling its own capsule, because they had
/// already drifted: different paddings, two fills and two fonts across the kana quizzes,
/// Match and the ladder, for what is the same object in the same slot on every one of
/// them. `ScoreBadge` is now this with right/wrong/total inside it.
///
/// `fixedSize` because the toolbar is free to compress its principal item, and a counter
/// it decides to shrink is one that will be — the numbers are the point.
struct ToolbarStatus<Content: View>: View {
    /// What the run is, in a few words — "Round 2 · 5 pairs". Optional: a kana quiz is
    /// just a quiz, and a caption saying so would be furniture.
    var caption: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 12) { content() }
                // **Never wrap.** The principal slot is whatever the navigation bar has
                // left after the back button and the trailing controls, and on a real
                // device with a Dynamic Island that is narrow enough to break a
                // two-digit number across two lines — "✓ 1/0" where 10 was meant.
                // `fixedSize` on the outer stack is not enough: it asks for the ideal
                // size, and the toolbar can still refuse it. Denying the wrap at the
                // text is what actually holds.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .fixedSize()
    }
}

/// One consistent score indicator used by every scored screen in the app (Kana Classic,
/// Kana Swipe, Kana Write). Shows right / wrong / total, in `ToolbarStatus`.
struct ScoreBadge: View {
    let correct: Int
    let total: Int
    private var wrong: Int { total - correct }

    /// What this run is, under the numbers — Match names its round, a kana quiz has
    /// nothing to add.
    var caption: String? = nil

    var body: some View {
        ToolbarStatus(caption: caption) {
            IconCount(icon: "checkmark", count: correct, color: Theme.correct)
            IconCount(icon: "xmark", count: wrong, color: Theme.wrong)
            Text("/ \(total)")
                .font(.footnote.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(correct) correct, \(wrong) wrong, \(total) total")
    }

}

/// The from → to direction bar both kana quizzes wear: two bordered buttons around an
/// arrow, disabled once an answer is picked. In listening mode the prompt side is the
/// audio, so a speaker stands where the first button would be — the classic quiz is the
/// only caller that passes `listening`.
struct KanaDirectionBar: View {
    let model: KanaQuizModel
    var listening = false

    var body: some View {
        HStack(spacing: 8) {
            if listening {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(Theme.accent)
            } else {
                Button(model.from.label) { model.swapFrom() }
            }
            Image(systemName: "arrow.right")
            Button(model.to.label) { model.swapTo() }
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
        .disabled(model.picked != nil)
    }
}

/// The tap-to-hear question pane the Challenge run and the kana quiz share: content
/// on a surface-filled rounded rect, the whole pane tappable to replay. Content stays
/// a closure because the two screens disagree on everything inside it (a 64pt speaker,
/// a word, a caption) and on nothing outside it — which was exactly the duplicated part.
struct QuizPromptPanel<Content: View>: View {
    let onTap: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group(content: content)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
    }
}

/// The 64pt accent speaker that stands in for an audio prompt, in both quiz panes.
struct AudioPromptGlyph: View {
    var body: some View {
        Image(systemName: "speaker.wave.3.fill")
            .font(.system(size: 64))
            .foregroundStyle(Theme.accent)
            // The glyph alone is the whole question ("listen, then pick") — without a
            // label VoiceOver read the pane as an unnamed image.
            .accessibilityLabel(L.t("Tap to hear it"))
    }
}

/// A tinted icon-and-number pair — the atom `ScoreBadge` and the kana flashcards'
/// header readout both drew by hand. `Image` + `Text`, never `Label`: a `Label` in a
/// toolbar's principal slot picks up `.iconOnly` and the number silently vanishes.
/// The font is left to the caller, since the two headers deliberately differ a step.
struct IconCount: View {
    let icon: String
    let count: Int
    let color: Color
    var font: Font = .subheadline.weight(.semibold)

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).imageScale(.small)
            Text("\(count)").monospacedDigit()
        }
        .font(font)
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
                // CoreText over all 39 900 translations in the 18 languages: at 0.5 the
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
    /// The gesture in words ("Swipe left"), under the answer. The chevron already points
    /// the way; this spells it out for the first run, before the gesture is learned.
    /// Optional because the kana quiz teaches its swipe elsewhere and doesn't want the
    /// second line taking room from a chip that is already only romaji.
    var hint: String? = nil
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
            VStack(spacing: 4) {
            HStack(spacing: 6) {
                if side == 0 { marker }
                Text(text)
                    .font(font)
                    .foregroundStyle(answered ? color : .primary)   // reads as text, not a link
                    // Wrap first, shrink second. The chip has a `minHeight`, not a fixed
                    // height, so a long gloss is allowed to make it taller — but
                    // `lineLimit(3)` capped it before it could, and 0.4 of `.title3` is 8pt.
                    // Measured over all 39 900 translations in the 18 languages: at (3, 0.4)
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
            // Hidden once answered: the verdict is the message then, and a swipe
            // instruction on a chip that no longer takes one is just noise.
            if let hint, !answered {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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
            if showsHint { SwipeHint() }
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

/// The end-of-deck panel Practice and the kana flashcards both show: the party
/// popper, "All done!", one line of summary and a Restart button. The two copies were
/// identical to the glyph — only the summary string and what restarting means differ,
/// so those are the parameters.
struct DeckDonePanel: View {
    let summary: String
    let onRestart: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.accent)
            Text(L.t("All done!")).font(Theme.title(.largeTitle, weight: .bold))
            Text(summary).foregroundStyle(.secondary)
            Button(action: onRestart) {
                Label(L.t("Restart"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// A whole-screen empty state: some art over one line of guidance, on the canvas.
/// The art is a parameter because it is the one thing the two call sites disagree on
/// (Progress uses a template illustration, Bookmarks an SF Symbol) — everything else
/// was copied verbatim and had started to drift.
struct EmptyStatePanel<Art: View>: View {
    let text: String
    @ViewBuilder var art: () -> Art

    var body: some View {
        VStack(spacing: 16) {
            art()
            Text(text)
                .font(Theme.title(.subheadline, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }
}

/// The full-width black action pill — `Color.primary` fill, system-background text,
/// 54pt, radius 18 — that Practice's Next and both Challenge buttons drew by hand.
///
/// Fill, shape and `contentShape` all live *inside* the button label on purpose: a
/// `.frame` only reserves layout space and is not hit-testable on its own, so with
/// the background applied outside the label only the glyphs took taps — the bug this
/// codebase has now hit on four separate buttons.
struct PrimaryPillButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var label: () -> Content

    var body: some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundStyle(Color(.systemBackground))
                .background(Color.primary, in: RoundedRectangle(cornerRadius: 18))
                .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

/// The Ordered / Random segmented control the two deck modes share. `event` is the
/// per-screen analytics name — one event name per thing, so the two decks stay
/// separable in the dashboards even though the control is one.
struct OrderPicker: View {
    @Binding var ordered: Bool
    let event: String

    var body: some View {
        Picker("", selection: $ordered) {
            Text(L.t("Ordered")).tag(true)
            Text(L.t("Random")).tag(false)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: ordered) { Track.event(event, ["ordered": ordered]) }
    }
}

/// The trailing toolbar pair every practice surface carries: the report flag, then
/// the sound toggle — **in that order**, which four screens each re-stated in a
/// comment. `item` is optional because the flag only makes sense while a word is on
/// screen; `sound: false` is for Learn, whose sound control lives in its
/// `CardOptionsBar` chip instead — passing neither renders nothing, which is what
/// makes adopting this on every practice screen say "no flag here" out loud.
struct FlagAndSoundToolbar: ToolbarContent {
    var item: Feedback.Item? = nil
    var sound = true

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let item {
                ReportItemButton(item: item)
            }
            if sound {
                SoundToggle()
            }
        }
    }
}

/// A capsule progress bar: a track and a proportional fill. Four screens hand-rolled
/// the same `Capsule` + `GeometryReader` pair — Practice's session bar, the lesson
/// hero, the lesson list's per-row bar and the kana browser — differing only in the
/// colours and the height, so those are the parameters. The fraction is clamped here
/// once instead of at whichever call sites remembered to.
///
/// Two track colours exist on purpose: the default reads against `Theme.surface`
/// rows; Practice passes `Theme.line` because its bar sits directly on the canvas,
/// and the hero passes a translucent system-background because it sits on ink.
struct CapsuleBar: View {
    let fraction: Double
    var height: CGFloat = 6
    var width: CGFloat? = nil
    var track: Color = Color.secondary.opacity(0.18)
    var fill: Color = Theme.accent

    var body: some View {
        Capsule()
            .fill(track)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(fill)
                        .frame(width: geo.size.width * max(0, min(fraction, 1)))
                }
            }
            .clipShape(Capsule())
            .frame(width: width, height: height)
            .accessibilityHidden(true)   // callers narrate the numbers (or label the row)
    }
}

/// The icon–title–blurb head every prompt sheet opens with — the rating ask, the
/// share nudge, the feedback thanks, the paywall, the earned unlock and the
/// notification opt-in all set the same three lines and had six hand copies.
///
/// Deliberately **not** its own stack: the body emits siblings, so each sheet's own
/// `VStack` spacing keeps applying between them — the six sheets space 14/18/20pt and
/// unifying that would have moved every one of them. The icon is decorative by
/// definition here (the title says everything), so it is accessibility-hidden.
struct PromptHeader: View {
    let icon: String
    let title: String
    var blurb: String? = nil
    var iconFont: Font = .system(size: 40)
    var tint: Color = Theme.accent
    var titleFont: Font = Theme.title(.title3)

    var body: some View {
        Image(systemName: icon)
            .font(iconFont)
            .foregroundStyle(tint)
            .accessibilityHidden(true)
        Text(title)
            .font(titleFont)
            .multilineTextAlignment(.center)
        if let blurb {
            Text(blurb)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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

extension View {
    /// Sheet content that scrolls only when it doesn't fit.
    ///
    /// The prompt sheets sit in fixed-height detents; at accessibility type sizes (or
    /// under German and Russian titles) their buttons fell past the bottom edge with
    /// no way to reach them — and on the notification opt-in the only exit left was a
    /// swipe-down, which the caller reads as "never answered", so the sheet returned
    /// forever. A `ScrollView` that only engages under pressure keeps the normal case
    /// pinned and the cramped case usable; pairing the fixed detent with `.large`
    /// gives the same escape hatch to fingers.
    func scrollableWhenCramped() -> some View {
        ViewThatFits(in: .vertical) {
            self
            ScrollView { self }
        }
    }
}

/// Defers a destination's construction until navigation actually renders it.
///
/// `NavigationLink { Destination() }` evaluates the closure during **body** — the
/// link only defers *rendering*. A destination whose init does real work
/// (`ChallengeView` builds ten rejection-sampled questions via `State(initialValue:)`)
/// therefore ran on every render of the presenting screen: the lesson hub was
/// rebuilding on the order of eighty questions per visit across its chips and cards.
/// Storing the closure and calling it in `body` moves that work to the push.
struct Deferred<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder _ content: @escaping () -> Content) { self.content = content }
    var body: Content { content() }
}

/// The drag every swipe-to-decide card runs — Practice, the kana flashcards and the
/// kana swipe quiz had three hand copies of the same three branches: past the
/// threshold rightward decides right, leftward decides left, anything else springs
/// home. `canDrag` is each screen's own reason the card is currently pinned;
/// `canCommit` covers Practice's held-flipped card, where releasing a drag must
/// spring back no matter how far it travelled.
/// How long a card must be held before it turns over — one number for Today,
/// Flashcards and Practice, so the same gesture is exactly as eager everywhere.
/// 0.2s is markedly snappier than the 0.5s system default while staying clear of
/// the plain tap every card also carries (tap speaks, hold flips).
enum CardFlip {
    static let hold: TimeInterval = 0.2
}

enum CardSwipe {
    static func gesture(drag: Binding<CGSize>, threshold: CGFloat,
                        canDrag: @escaping () -> Bool,
                        canCommit: @escaping () -> Bool = { true },
                        decide: @escaping (_ right: Bool) -> Void) -> some Gesture {
        DragGesture()
            .onChanged { if canDrag() { drag.wrappedValue = $0.translation } }
            .onEnded { value in
                guard canCommit() else {
                    return withAnimation(.spring) { drag.wrappedValue = .zero }
                }
                if value.translation.width > threshold { decide(true) }
                else if value.translation.width < -threshold { decide(false) }
                else { withAnimation(.spring) { drag.wrappedValue = .zero } }
            }
    }

    /// Fling the card off-screen and run the continuation once it has left. The exit
    /// itself is always 0.25s; `then` is how long the *caller* waits, which the kana
    /// swipe quiz stretches to let its verdict badge read before the next card deals.
    static func fling(_ drag: Binding<CGSize>, toRight: Bool,
                      then delay: TimeInterval = 0.25,
                      _ continuation: @escaping () -> Void) {
        withAnimation(.easeOut(duration: 0.25)) {
            drag.wrappedValue.width = toRight ? 700 : -700
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: continuation)
    }
}

/// The "⟨ Swipe ⟩" whisper at a card's bottom edge — `SwipeCard` shows it through
/// `showsHint`, and Learn (which draws its own card chrome for the tile game) overlays
/// the same one rather than keeping a byte-for-byte copy.
struct SwipeHint: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.compact.left")
            Text(L.t("Swipe"))
            Image(systemName: "chevron.compact.right")
        }
        .font(.caption).foregroundStyle(.tertiary).padding(.bottom, 8)
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

/// 2×2 grid of quiz options — the kana classic quiz's layout.
///
/// The Challenge ladder used to share it and now stacks its four options full-width
/// instead: a vocab option is a gloss that can run to a phrase, and two of those side
/// by side shrink to unreadable where a kana romaji never does.
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

/// An example sentence as aligned columns: kanji over kana over romaji, one column per
/// bunsetsu, wrapping like text. The alignment is the feature — see `ExampleSentence`.
struct ExampleSentenceView: View {
    let example: ExampleSentence
    /// The sentence's translated meaning, drawn under the columns when given — the
    /// three screens that show one all stacked the same pair by hand, in three fonts.
    var translation: String? = nil
    var translationFont: Font = .footnote
    var alignment: HorizontalAlignment = .center
    /// Gap between the columns and the translation — the read-along playlist packs a
    /// tighter 4 into its rows; everywhere else keeps 6.
    var spacing: CGFloat = 6

    /// The columns wrap in reading order, so long sentences fold like prose would.
    ///
    /// Furigana order, not caption order: the small kana sits *above* the kanji it
    /// reads, the way every Japanese text annotates readings — putting it below made
    /// the column read as three unrelated lines. The reading slot is reserved even
    /// where kanji and kana coincide, so the kanji baseline and the romaji line stay
    /// level across every column of the sentence.
    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            columns
            if let translation {
                Text(translation)
                    .font(translationFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(alignment == .trailing ? .trailing
                                            : alignment == .center ? .center : .leading)
            }
        }
    }

    private var columns: some View {
        annotatedColumns
            // On the columns, not inside `hiddenSpan` — a `.hidden()` zero-height
            // ruler isn't in the accessibility tree, so the combined sentence label
            // was attached to nothing and VoiceOver read three fragments per column.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(example.spoken)
    }

    private var annotatedColumns: some View {
        FlowLayout(spacing: 8, lineSpacing: 6) {
            ForEach(example.kanji.indices, id: \.self) { i in
                // Centred within the column: furigana over the kanji, romaji under the
                // phrase, the way printed furigana is set. Left-aligned, both
                // annotations hugged the column's left edge and looked indented.
                VStack(alignment: .center, spacing: 0) {
                    // The reading centres over the kanji **core**, not the phrase: in
                    // 本です。 the ほん belongs over 本 alone, and centring it over the
                    // whole column parked it visibly off its kanji. Hidden copies of
                    // the prefix and suffix (zero height, real width) push the reading
                    // to exactly the core's span; the row keeps the reading's own
                    // height, so the reserved blank line stays the same size as ever.
                    if let a = example.annotated(at: i) {
                        HStack(alignment: .center, spacing: 0) {
                            hiddenSpan(a.prefix)
                            Text(a.reading)
                                .font(Theme.jp(9))
                                .foregroundStyle(.secondary)
                                .layoutPriority(1)
                            hiddenSpan(a.suffix)
                        }
                    } else {
                        Text(" ").font(Theme.jp(9))
                    }
                    // Quieter than the headword above the pane on purpose: the example
                    // illustrates the word, it doesn't compete with it.
                    Text(example.kanji[i]).font(Theme.jp(14))
                    if example.romaji.indices.contains(i) {
                        Text(example.romaji[i]).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    /// A phrase segment that occupies its rendered *width* and nothing else — the
    /// ruler that positions a reading over its kanji core. Zero height so the
    /// main-line font doesn't inflate the small furigana row.
    private func hiddenSpan(_ text: String) -> some View {
        Text(text).font(Theme.jp(14)).fixedSize()
            .frame(height: 0).hidden()
    }
}

/// Minimal wrapping layout — rows of subviews at their natural size, folding when the
/// width runs out. Exists because the example columns must wrap like text, and neither
/// `HStack` (clips) nor a grid (uniform cells) can do ragged reading-order wrapping.
///
/// **Caveat**: `sizeThatFits` arranges against the *proposed* width while
/// `placeSubviews` re-arranges against the *granted* one. With a concrete width — every
/// current call site — the two agree. Under an unspecified proposal (an ideal-size
/// pass) the reported height would be one row's while placement wraps several, painting
/// past the reserved space. If a caller ever puts this in a context that probes ideal
/// size (`fixedSize`, alignment-guide measurement), reconcile the two first.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Wrap against the width actually granted, not the one proposed: the two differ
        // whenever the parent proposes nil/unspecified (an ideal-size pass), and folding
        // on `.infinity` there lays every column out on one row that then runs off the
        // side of `bounds`.
        let granted = ProposedViewSize(width: bounds.width, height: bounds.height)
        for (subview, point) in zip(subviews, arrange(proposal: granted, subviews: subviews).points) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                          proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            width = max(width, x + size.width)
            x += size.width + spacing
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}


/// A short horizontal shake — the app's one "that didn't work" motion.
///
/// A `GeometryEffect` rather than an offset animation so it can run to completion and
/// return, without leaving the view displaced if the value changes mid-flight.
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 4
    var shakesPerUnit = 3
    var animatableData: CGFloat

    init(shakes: Int) { animatableData = CGFloat(shakes) }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)), y: 0))
    }
}

/// The vocab card face: kana (+ kanji), revealing meaning + romaji + example.
/// Shared by Practice's reveal and the Flashcards deck's back — the same face, so a
/// word looks the same wherever it is turned over.
struct VocabFace: View {
    let vocab: Vocab
    let revealed: Bool
    var speakExample: () -> Void = {}

    var body: some View {
        VStack(spacing: 14) {
            Text(vocab.kana)
                .font(Theme.jp(56))
                .minimumScaleFactor(0.4)
                .multilineTextAlignment(.center)
            if vocab.displaysKanji {
                Text(vocab.kanji).font(Theme.jp(22)).foregroundStyle(.secondary)
            }
            if revealed {
                Divider().padding(.horizontal, 40)
                Text(vocab.translation)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
                if !vocab.romaji.isEmpty {
                    Text(vocab.romaji).font(.subheadline).foregroundStyle(.secondary)
                }
                // The example, after the reveal only: the front is a recall test and
                // the sentence contains the word — showing it early would answer the
                // card. A button (speaks on tap), because the card face's own tap is
                // taken by pronouncing the word.
                if let example = vocab.example {
                    Button(action: speakExample) {
                        ExampleSentenceView(example: example,
                                            translation: vocab.exampleTranslation)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
    }
}
