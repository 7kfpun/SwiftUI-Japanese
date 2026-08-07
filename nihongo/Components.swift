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

/// A quiz answer button that fills the space it's given, with a colored state border.
/// Shared by the two multiple-choice quizzes so they look identical.
struct QuizOptionButton: View {
    let text: String
    let border: Color
    let disabled: Bool
    var font: Font = .headline   // kana quizzes pass a bigger Japanese face
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(font)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border, lineWidth: 2))
        .disabled(disabled)
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
