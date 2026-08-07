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

/// One consistent score indicator used by every quiz in the app
/// (Kana classic, Kana swipe, Lessons quiz). Shows right / wrong / total.
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

/// A quiz answer button that fills the space it's given. Shared by the two
/// multiple-choice quizzes so they look identical — and now wearing the same
/// `choiceChip` chrome as every other choice control in the app. It used to be a
/// plain white box with a thin grey outline: inert before you answered, and the only
/// control still speaking the old visual language.
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
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .choiceChip(color)
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
    var font: Font = .title3.weight(.semibold)

    private var answered: Bool { picked != nil }
    private var isPicked: Bool { picked == side }

    private var color: Color {
        guard answered else { return Theme.accent }
        if isAnswer { return Theme.correct }
        return isPicked ? Theme.wrong : Theme.line
    }

    var body: some View {
        HStack(spacing: 6) {
            if side == 0 { marker }
            Text(text)
                .font(font)
                .foregroundStyle(answered ? color : .primary)   // reads as text, not a link
                .minimumScaleFactor(0.4)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if side == 1 { marker }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 96)   // min, not fixed: long glosses need room
        .choiceChip(color)
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

/// 2×2 grid of quiz options that expands to fill the available height.
struct OptionGrid<Cell: View>: View {
    let count: Int
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
            }
        }
        .frame(maxHeight: .infinity)
    }
}
