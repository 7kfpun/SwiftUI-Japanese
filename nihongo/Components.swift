import SwiftUI

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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.headline)
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
