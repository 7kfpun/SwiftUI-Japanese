import SwiftUI

/// A spaced-repetition-lite deck: cards start in random order. Swipe right = "know it"
/// (retired), swipe left = "don't know" (sent to the back to see again). Repeats until
/// every card has been swiped right, then shows a done screen. Count lives at the top.
@Observable
final class FlashDeck {
    private let all: [Vocab]
    private(set) var deck: [Vocab]
    private(set) var mastered = 0

    let total: Int

    init(vocab: [Vocab]) {
        all = vocab
        deck = vocab.shuffled()
        total = vocab.count
    }

    var current: Vocab? { deck.first }
    var isDone: Bool { deck.isEmpty }
    var remaining: Int { deck.count }

    /// Swipe right — known, retire it.
    func know() {
        guard !deck.isEmpty else { return }
        deck.removeFirst()
        mastered += 1
    }

    /// Swipe left — unknown, send to the back to revisit later.
    func dontKnow() {
        guard !deck.isEmpty else { return }
        deck.append(deck.removeFirst())
    }

    func restart() {
        deck = all.shuffled()
        mastered = 0
    }
}

struct FlashcardView: View {
    @State private var deck: FlashDeck
    @State private var drag: CGSize = .zero
    @State private var revealed = false
    @AppStorage("isSoundOn") private var soundOn = true
    @Environment(\.pronouncer) private var pronouncer

    private let threshold: CGFloat = 100

    init(lesson: Lesson) {
        _deck = State(initialValue: FlashDeck(vocab: lesson.entries))
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            if let card = deck.current {
                cardView(card)
                graders
            } else {
                congrats
            }
        }
        .padding()
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { autoPlay() }
        .onChange(of: deck.current?.id) { autoPlay() }
        .onChange(of: soundOn) { if soundOn { autoPlay() } }
    }

    /// Count on the left (updates as you swipe), audio toggle on the right.
    private var header: some View {
        HStack {
            progress
            Spacer()
            Button { soundOn.toggle() } label: {
                Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.title3)
                    .foregroundStyle(soundOn ? Theme.accent : .secondary)
            }
            .accessibilityLabel(soundOn ? "Turn sound off" : "Turn sound on")
        }
    }

    // MARK: Card

    private func cardView(_ v: Vocab) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(.separator), lineWidth: 1))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

            VStack(spacing: 14) {
                Text(v.kana)
                    .font(.system(size: 60, weight: .light))
                    .minimumScaleFactor(0.4)
                    .multilineTextAlignment(.center)
                if v.displaysKanji {
                    Text(v.kanji).font(.title2).foregroundStyle(.secondary)
                }
                if revealed {
                    Divider().padding(.horizontal, 40)
                    Text(v.translation)
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .multilineTextAlignment(.center)
                    if !v.romaji.isEmpty {
                        Text(v.romaji).font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    Button { withAnimation { revealed = true } } label: {
                        Label(L.t("Show meaning"), systemImage: "eye")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }
            .padding(24)

            // Directional hint while dragging.
            if drag.width != 0 {
                Image(systemName: drag.width > 0 ? "checkmark.circle.fill"
                                                 : "arrow.uturn.left.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(drag.width > 0 ? Theme.correct : Theme.wrong)
                    .opacity(min(abs(drag.width) / threshold, 1))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: drag.width, y: drag.height / 10)
        .rotationEffect(.degrees(Double(drag.width / 22)))
        .contentShape(Rectangle())
        .onTapGesture { pronouncer.speak(v) }
        .gesture(
            DragGesture()
                .onChanged { drag = $0.translation }
                .onEnded { value in
                    if value.translation.width > threshold { grade(right: true) }
                    else if value.translation.width < -threshold { grade(right: false) }
                    else { withAnimation(.spring) { drag = .zero } }
                }
        )
    }

    private var graders: some View {
        HStack {
            Button { grade(right: false) } label: {
                Label(L.t("Again"), systemImage: "arrow.uturn.left")
                    .frame(maxWidth: .infinity)
            }
            .tint(Theme.wrong)
            Button { grade(right: true) } label: {
                Label(L.t("Got it"), systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .tint(Theme.correct)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var progress: some View {
        HStack(spacing: 14) {
            Label("\(deck.mastered)", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.correct)
            Label("\(deck.remaining)", systemImage: "rectangle.stack.fill").foregroundStyle(Theme.accent)
            Text("/ \(deck.total)").foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold).monospacedDigit())
    }

    private var congrats: some View {
        VStack(spacing: 20) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.accent)
            Text(L.t("All done!")).font(.largeTitle.bold())
            Text(L.t("You reviewed %@ words", "\(deck.total)"))
                .foregroundStyle(.secondary)
            Button {
                withAnimation { deck.restart(); revealed = false; drag = .zero }
                autoPlay()
            } label: {
                Label(L.t("Restart"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: Actions

    private func grade(right: Bool) {
        withAnimation(.easeOut(duration: 0.25)) { drag.width = right ? 700 : -700 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if right { deck.know() } else { deck.dontKnow() }
            revealed = false
            drag = .zero
            autoPlay()
        }
    }

    private func autoPlay() {
        if soundOn, let v = deck.current { pronouncer.speak(v) }
    }
}
