import SwiftUI

/// A spaced-repetition-lite deck over any element type. Cards start in random order.
/// Swipe right = "know it" (retired); swipe left = "don't know" (sent to the back to
/// see again). Repeats until every card has been swiped right. Shared by the Lessons
/// (vocab) and Kana flashcards.
@Observable
final class FlashDeck<Element> {
    private let all: [Element]
    private(set) var deck: [Element]
    private(set) var mastered = 0

    let total: Int

    init(_ items: [Element]) {
        all = items
        deck = items.shuffled()
        total = items.count
    }

    var current: Element? { deck.first }
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

/// The shared Tinder-style flashcard screen: drag/tap gestures, grade buttons, the
/// top count, auto-play, reveal, and the done screen. Callers supply only what's
/// type-specific: the card face, an id (for auto-play change detection), the audio
/// action, and the reveal/summary text.
struct FlashcardScreen<Element, Face: View>: View {
    @State private var deck: FlashDeck<Element>
    @State private var drag: CGSize = .zero
    @State private var revealed = false
    @State private var graded = 0
    @AppStorage("isSoundOn") private var soundOn = true

    private let idOf: (Element) -> String
    private let speak: (Element) -> Void
    private let revealLabel: String
    private let summary: (Int) -> String
    private let trialLimit: Int?
    private let onReachLimit: () -> Void
    private let trackName: String?
    private let face: (Element, Bool) -> Face

    private let threshold: CGFloat = 100

    /// After `trialLimit` grades (nil = unlimited), grading stops and `onReachLimit` fires.
    private var reachedLimit: Bool { trialLimit.map { graded >= $0 } ?? false }

    init(deck: FlashDeck<Element>,
         id: @escaping (Element) -> String,
         revealLabel: String,
         summary: @escaping (Int) -> String,
         trialLimit: Int? = nil,
         onReachLimit: @escaping () -> Void = {},
         trackName: String? = nil,
         speak: @escaping (Element) -> Void,
         @ViewBuilder face: @escaping (Element, Bool) -> Face) {
        _deck = State(initialValue: deck)
        self.idOf = id
        self.revealLabel = revealLabel
        self.summary = summary
        self.trialLimit = trialLimit
        self.onReachLimit = onReachLimit
        self.trackName = trackName
        self.speak = speak
        self.face = face
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            if let card = deck.current {
                cardView(card)
                if reachedLimit { unlockBar } else { graders }
            } else {
                congrats
            }
        }
        .padding()
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { autoPlay() }
        .onChange(of: deck.current.map(idOf)) { autoPlay() }
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

    private var progress: some View {
        HStack(spacing: 14) {
            Label("\(deck.mastered)", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.correct)
            Label("\(deck.remaining)", systemImage: "rectangle.stack.fill").foregroundStyle(Theme.accent)
            Text("/ \(deck.total)").foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold).monospacedDigit())
    }

    private func cardView(_ element: Element) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(.separator), lineWidth: 1))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

            VStack(spacing: 14) {
                face(element, revealed)
                if !revealed {
                    Button { withAnimation { revealed = true } } label: {
                        Label(revealLabel, systemImage: "eye")
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
        .onTapGesture { speak(element) }
        .gesture(
            DragGesture()
                .onChanged { drag = $0.translation }
                .onEnded { value in
                    if reachedLimit { withAnimation(.spring) { drag = .zero }; return }
                    if value.translation.width > threshold { grade(right: true) }
                    else if value.translation.width < -threshold { grade(right: false) }
                    else { withAnimation(.spring) { drag = .zero } }
                }
        )
    }

    private var graders: some View {
        HStack {
            Button { grade(right: false) } label: {
                Label(L.t("Again"), systemImage: "arrow.uturn.left").frame(maxWidth: .infinity)
            }
            .tint(Theme.wrong)
            Button { grade(right: true) } label: {
                Label(L.t("Got it"), systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .tint(Theme.correct)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var unlockBar: some View {
        Button { onReachLimit() } label: {
            Label(L.t("Unlock to continue"), systemImage: "lock.open.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var congrats: some View {
        VStack(spacing: 20) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.accent)
            Text(L.t("All done!")).font(.largeTitle.bold())
            Text(summary(deck.total)).foregroundStyle(.secondary)
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

    private func grade(right: Bool) {
        guard !reachedLimit else { return }
        graded += 1
        if let n = trackName { Track.event("\(n)_grade", ["known": right]) }
        withAnimation(.easeOut(duration: 0.25)) { drag.width = right ? 700 : -700 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if right { deck.know() } else { deck.dontKnow() }
            revealed = false
            drag = .zero
            if deck.isDone, let n = trackName { Track.event("\(n)_done") }
            if reachedLimit { onReachLimit() } else { autoPlay() }
        }
    }

    private func autoPlay() {
        if soundOn, let c = deck.current { speak(c) }
    }
}
