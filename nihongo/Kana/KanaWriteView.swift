import SwiftUI
import SwiftData
import Vision

/// Write mode: hear the kana (and see its romaji), then draw it with a finger.
/// The sketch is rasterized and read back by Apple's on-device Vision text
/// recognition (Japanese) — the drawing literally becomes Japanese text, and it
/// must read as the target kana. Fully offline, no stroke data needed.
struct KanaWriteView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.pronouncer) private var pronouncer

    private let pool: [K]
    @State private var answer: K
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var canvasSize: CGSize = .zero
    @State private var verdict: Verdict = .drawing
    @State private var recognized = ""
    @State private var showTemplate = false
    @State private var graded = false
    @State private var correct = 0
    @State private var total = 0

    private enum Verdict { case drawing, right, wrong }

    init(table: KanaTable) {
        let p = table.rows.flatMap { $0 }.filter { !$0.isEmpty }
        pool = p
        _answer = State(initialValue: p.randomElement() ?? K("あ", "ア", "a"))
    }

    var body: some View {
        VStack(spacing: 16) {
            // Prompt: romaji + replayable audio — the learner produces the glyph.
            HStack(spacing: 12) {
                Text(answer.romaji)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Button { pronouncer.speak(kana: answer) } label: {
                    Image(systemName: "speaker.wave.2.fill").font(.title2)
                }
            }

            drawingCanvas

            feedback

            HStack(spacing: 12) {
                Button(L.t("Clear")) { clear() }
                    .buttonStyle(.bordered)
                Button { withAnimation { showTemplate.toggle() } } label: {
                    Label(L.t("Reveal"), systemImage: showTemplate ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)
                Spacer()
                if verdict == .drawing {
                    Button(L.t("Check")) { check() }
                        .buttonStyle(.borderedProminent)
                        .disabled(strokes.isEmpty)
                } else {
                    Button(L.t("Next")) { next() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
        }
        .padding()
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { pronouncer.speak(kana: answer); Track.screen("kana_write") }
        .toolbar {
            ToolbarItem(placement: .principal) { ScoreBadge(correct: correct, total: total) }
            ToolbarItem(placement: .topBarTrailing) { SoundToggle() }
        }
    }

    // MARK: drawing

    private var drawingCanvas: some View {
        GeometryReader { geo in
            ZStack {
                if showTemplate {
                    Text(answer.hiragana)
                        .font(Theme.jp(min(geo.size.width, geo.size.height) * 0.7))
                        .foregroundStyle(.quaternary)
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
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { canvasSize = geo.size }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(borderColor, lineWidth: 2))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { current.append($0.location) }
                .onEnded { _ in
                    if current.count > 1 { strokes.append(current) }
                    current = []
                }
        )
    }

    private var borderColor: Color {
        switch verdict {
        case .drawing: return Color(.separator)
        case .right:   return Theme.correct
        case .wrong:   return Theme.wrong
        }
    }

    @ViewBuilder private var feedback: some View {
        switch verdict {
        case .right:
            Label(L.t("Correct!"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.correct).font(.headline)
        case .wrong:
            Label(recognized.isEmpty ? L.t("Wrong") : "\(L.t("Wrong")) — 「\(recognized)」",
                  systemImage: "xmark.circle.fill")
                .foregroundStyle(Theme.wrong).font(.headline)
        case .drawing:
            Text(" ").font(.headline)   // keeps the layout stable
        }
    }

    // MARK: recognition

    private func check() {
        guard !strokes.isEmpty, canvasSize.width > 0 else { return }
        let strokesCopy = strokes
        let size = canvasSize
        let hiragana = answer.hiragana
        let katakana = answer.katakana
        Task {
            let texts = await Self.recognize(strokes: strokesCopy, in: size)
            let hit = texts.contains { $0.contains(hiragana) || $0.contains(katakana) }
            recognized = texts.first ?? ""
            if !graded {
                graded = true
                total += 1
                if hit { correct += 1 }
                KanaResult.record(romaji: answer.romaji, isCorrect: hit, context: context)
            }
            withAnimation { verdict = hit ? .right : .wrong }
            if hit {
                try? await Task.sleep(nanoseconds: 700_000_000)
                next()
            }
        }
    }

    /// Rasterize the strokes (CoreGraphics, off-main-safe) and run Vision's Japanese
    /// text recognition over the bitmap. Returns the candidate strings.
    private nonisolated static func recognize(strokes: [[CGPoint]], in size: CGSize) async -> [String] {
        await Task.detached { () -> [String] in
            let scale = 512 / max(size.width, size.height)
            guard let ctx = CGContext(data: nil,
                                      width: Int(size.width * scale), height: Int(size.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return [] }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
            ctx.setStrokeColor(gray: 0, alpha: 1)
            ctx.setLineWidth(10 * scale)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for stroke in strokes where stroke.count > 1 {
                // flip y: CoreGraphics origin is bottom-left, view points are top-left
                ctx.move(to: CGPoint(x: stroke[0].x * scale,
                                     y: CGFloat(ctx.height) - stroke[0].y * scale))
                for p in stroke.dropFirst() {
                    ctx.addLine(to: CGPoint(x: p.x * scale, y: CGFloat(ctx.height) - p.y * scale))
                }
                ctx.strokePath()
            }
            guard let image = ctx.makeImage() else { return [] }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP"]
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).flatMap { $0.topCandidates(5).map(\.string) }
        }.value
    }

    // MARK: flow

    private func clear() {
        strokes = []; current = []
        recognized = ""
        withAnimation { verdict = .drawing }
    }

    private func next() {
        clear()
        graded = false
        showTemplate = false
        answer = pool.randomElement() ?? answer
        pronouncer.speak(kana: answer)
    }
}
