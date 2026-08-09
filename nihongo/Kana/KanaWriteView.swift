import SwiftUI
import SwiftData

/// Write test: hear the kana (and see its romaji), then trace or draw it. A light
/// stroke-shape template (KanjiStrokeOrders font, numbered annotations stripped) sits
/// behind the canvas and can be toggled with Reveal. After each stroke the drawing is scored
/// 0–100 against the target glyph (chamfer + zone matching across template fonts);
/// on Next the kana is graded — stroke count must match exactly and the final score
/// must clear the pass mark — and the verdict feeds the shared KanaResult mastery
/// (green/red browser tiles), like the other quiz modes.
struct KanaWriteView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.pronouncer) private var pronouncer
    @AppStorage(Pref.soundOn) private var soundOn = true

    private enum Script: Int { case hiragana, katakana }

    private let pool: [K]
    @State private var answer: K
    @State private var script: Script = .hiragana
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var showTemplate = true
    @State private var score: Int? = nil
    @State private var correct = 0
    @State private var total = 0
    @State private var templateImage: UIImage? = nil

    /// Pass mark. The scoring curve lands a faithful trace in the mid-90s and a
    /// correct-but-wobbly freehand glyph in the 70s–80s, while the zone term pushes
    /// wrong-but-similar kana well below that — and this is also where the score
    /// turns green, so the verdict and the feedback color always agree.
    private let passScore = 80

    init(table: KanaTable) {
        let p = table.rows.flatMap { $0 }.filter { !$0.isEmpty }
        pool = p
        _answer = State(initialValue: p.randomElement() ?? K("あ", "ア", "a"))
    }

    /// Which glyph the learner should draw (and is scored against).
    private var targetIsKatakana: Bool { script == .katakana }
    private var targetGlyph: String { targetIsKatakana ? answer.katakana : answer.hiragana }

    /// Textbook stroke count from the kana chart (KanaChart.json); 0 = unknown.
    private var expectedStrokes: Int? {
        let count = targetIsKatakana ? answer.katakanaStrokes : answer.hiraganaStrokes
        return count > 0 ? count : nil
    }

    var body: some View {
        VStack(spacing: 16) {
            Picker("", selection: $script) {
                Text(L.t("Hiragana")).tag(Script.hiragana)
                Text(L.t("Katakana")).tag(Script.katakana)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: script) { clear() }
            .onChange(of: targetGlyph) { loadTemplateImage() }

            // Prompt: just the romaji — the script picker above already shows which
            // one is selected, so a repeated "Hiragana"/"Katakana" label was
            // redundant. Tap to replay the audio; the toolbar SoundToggle is the
            // single on/off control.
            Text(answer.romaji)
                .font(Theme.display(40))
                .contentShape(Rectangle())
                .onTapGesture { pronouncer.speak(kana: answer) }

            drawingCanvas

            scoreRow

            HStack(spacing: 12) {
                Button(L.t("Clear")) { clear() }
                    .buttonStyle(.bordered)
                Button {
                    withAnimation { showTemplate.toggle() }
                    // How often the stroke guide is needed is the difficulty signal
                    // for this mode — leaning on it means the kana isn't learned yet.
                    Track.event("kana_write_template", ["shown": showTemplate,
                                                        "romaji": answer.romaji])
                } label: {
                    Label(L.t("Reveal"), systemImage: showTemplate ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(L.t("Next")) { next() }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding()
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(L.t("Write"))
        .onAppear { autoPlay(); loadTemplateImage(); Track.screen("kana_write") }
        .toolbar {
            ToolbarItem(placement: .principal) { ScoreBadge(correct: correct, total: total) }
            ToolbarItem(placement: .topBarTrailing) { SoundToggle() }
        }
    }

    // MARK: drawing

    private var drawingCanvas: some View {
        GeometryReader { geo in
            ZStack {
                if showTemplate, let templateImage {
                    // Pre-rendered, digit-free stroke shape (see loadTemplateImage) —
                    // aspect-preserved, so combos (ちゅ) never squish or clip. Sized
                    // down from the full canvas so it reads as a guide, not a shape
                    // to fill edge-to-edge.
                    Image(uiImage: templateImage)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.tertiary)
                        .frame(width: geo.size.width * 0.6, height: geo.size.height * 0.6)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                Canvas { ctx, _ in
                    for stroke in strokes + [current] where stroke.count > 1 {
                        var path = Path()
                        path.addLines(stroke)
                        ctx.stroke(path, with: .color(.primary),
                                   style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { current.append($0.location) }
                .onEnded { _ in
                    if current.count > 1 {
                        strokes.append(current)
                        rescore()
                    }
                    current = []
                }
        )
    }

    /// Live match feedback after each stroke — wordless, so nothing to localize.
    /// Shows the shape score plus drawn/expected strokes (grading's hard check).
    @ViewBuilder private var scoreRow: some View {
        if let score {
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "scribble.variable")
                    Text("\(score)%").monospacedDigit()
                }
                .foregroundStyle(score >= passScore ? Theme.correct : score >= 40 ? Color.orange : Theme.wrong)
                if let expectedStrokes {
                    HStack(spacing: 5) {
                        Image(systemName: "pencil")
                        Text("\(strokes.count)/\(expectedStrokes)").monospacedDigit()
                    }
                    // Too few strokes may just mean "not finished" — stay neutral.
                    .foregroundStyle(strokes.count == expectedStrokes ? Theme.correct
                                     : strokes.count > expectedStrokes ? Theme.wrong : Color.secondary)
                }
            }
            .font(Theme.title(.headline))
        } else {
            Text(" ").font(Theme.title(.headline))   // keeps the layout stable
        }
    }

    // MARK: flow

    /// Regenerates the trace-template image for the current glyph. 640px gives
    /// plenty of detail on any device while staying cheap to rasterize.
    private func loadTemplateImage() {
        let glyph = targetGlyph
        Task {
            let img = await KanaSketch.strokeTemplateImage(glyph, pixelSize: 640)
            if targetGlyph == glyph { templateImage = img }   // discard a stale in-flight result
        }
    }

    private func rescore() {
        let strokesCopy = strokes
        let glyph = targetGlyph
        let expected = expectedStrokes
        Task {
            let s = await KanaSketch.matchScore(strokes: strokesCopy, glyph: glyph,
                                                expectedStrokes: expected)
            withAnimation { score = s }
        }
    }

    private func clear() {
        strokes = []; current = []
        withAnimation { score = nil }
    }

    private func next() {
        grade()
        clear()
        answer = pool.randomElement() ?? answer
        autoPlay()
    }

    /// Grade on Next — one verdict per kana, so the low scores mid-way through a
    /// multi-stroke glyph never count as misses. Skipped (undrawn) kana aren't graded.
    private func grade() {
        guard let score else { return }
        // Stroke count is a hard check (textbook counts); the shape score covers
        // the rest. No count available = shape-only.
        let strokesOK = expectedStrokes.map { strokes.count == $0 } ?? true
        let pass = strokesOK && score >= passScore
        total += 1
        if pass { correct += 1 }
        KanaResult.record(romaji: answer.romaji, isCorrect: pass, context: context)
        Track.event("kana_write_grade", ["pass": pass, "score": score])
    }

    /// Auto-play respects the global sound setting (explicit prompt taps don't).
    private func autoPlay() {
        if soundOn { pronouncer.speak(kana: answer) }
    }
}
