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

    /// Up to `n` cards after the current one — purely decorative, for the peek of
    /// cards waiting behind the top one.
    func peek(_ n: Int) -> [Element] { Array(deck.dropFirst().prefix(n)) }

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
    @State private var animating = false   // guards double-grades mid-animation
    @AppStorage(Pref.soundOn) private var soundOn = true

    private let idOf: (Element) -> String
    private let speak: (Element) -> Void
    private let revealLabel: String
    private let summary: (Int) -> String
    private let trackName: String?
    private let face: (Element, Bool) -> Face

    private let threshold: CGFloat = 100

    init(deck: FlashDeck<Element>,
         id: @escaping (Element) -> String,
         revealLabel: String,
         summary: @escaping (Int) -> String,
         trackName: String? = nil,
         speak: @escaping (Element) -> Void,
         @ViewBuilder face: @escaping (Element, Bool) -> Face) {
        _deck = State(initialValue: deck)
        self.idOf = id
        self.revealLabel = revealLabel
        self.summary = summary
        self.trackName = trackName
        self.speak = speak
        self.face = face
    }

    var body: some View {
        VStack(spacing: 16) {
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
        .onChange(of: deck.current.map(idOf)) { autoPlay() }
        .onChange(of: soundOn) { if soundOn { autoPlay() } }
        // Same toolbar placement as every other quiz/practice screen (counter
        // centered, sound toggle top-right) — was previously a custom inline
        // row with its own accent-tinted button, out of step with the rest of the app.
        .toolbar {
            ToolbarItem(placement: .principal) { progress }
            ToolbarItem(placement: .topBarTrailing) { SoundToggle() }
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

    /// The peek stack is a static backdrop — only `topCard` moves. Applying the
    /// drag offset/rotation to the whole ZStack would drag all three at once.
    private func cardView(_ element: Element) -> some View {
        ZStack {
            CardStackPeek(count: deck.peek(2).count)
            topCard(element)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func topCard(_ element: Element) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line, lineWidth: 1))
                .shadow(color: Theme.shadow, radius: 8, y: 4)

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
        }
        .overlay(alignment: .topTrailing) {
            SwipeStamp(systemImage: "checkmark", color: Theme.correct, rotation: 8)
                .opacity(drag.width > 0 ? min(drag.width / threshold, 1) : 0)
                .padding(16)
        }
        .overlay(alignment: .topLeading) {
            SwipeStamp(systemImage: "xmark", color: Theme.wrong, rotation: -8)
                .opacity(drag.width < 0 ? min(-drag.width / threshold, 1) : 0)
                .padding(16)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.compact.left")
                Text(L.t("Swipe"))
                Image(systemName: "chevron.compact.right")
            }
            .font(.caption).foregroundStyle(.tertiary).padding(.bottom, 8)
        }
        .offset(x: drag.width, y: drag.height / 10)
        .rotationEffect(.degrees(Double(drag.width / 22)))
        .contentShape(Rectangle())
        .onTapGesture { speak(element) }
        .gesture(
            DragGesture()
                .onChanged { if !animating { drag = $0.translation } }
                .onEnded { value in
                    if value.translation.width > threshold { grade(right: true) }
                    else if value.translation.width < -threshold { grade(right: false) }
                    else { withAnimation(.spring) { drag = .zero } }
                }
        )
    }

    /// The grade buttons double as swipe legends: arrows on the outer edges point the
    /// way to swipe for each outcome (left = again, right = got it). Same chip chrome
    /// as the kana swipe quiz's option chips, so every Tinder-like screen matches.
    private var graders: some View {
        HStack(spacing: 12) {
            Button { grade(right: false) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                    Text(L.t("Again")).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.plain)
            .choiceChip(Theme.wrong)

            Button { grade(right: true) } label: {
                HStack(spacing: 6) {
                    Text(L.t("Got it")).fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.plain)
            .choiceChip(Theme.correct)
        }
        .font(.headline)
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
        guard !animating else { return }
        animating = true
        if let n = trackName { Track.event("\(n)_grade", ["known": right]) }
        withAnimation(.easeOut(duration: 0.25)) { drag.width = right ? 700 : -700 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if right { deck.know() } else { deck.dontKnow() }
            revealed = false
            drag = .zero
            animating = false
            if deck.isDone, let n = trackName { Track.event("\(n)_done") }
            autoPlay()
        }
    }

    private func autoPlay() {
        if soundOn, let c = deck.current { speak(c) }
    }
}
