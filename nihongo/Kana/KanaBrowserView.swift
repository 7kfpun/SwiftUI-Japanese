import SwiftUI
import SwiftData

enum KanaTable: String, CaseIterable, Identifiable {
    case seion, dakuon, youon
    var id: String { rawValue }
    /// The Japanese terms rather than English glosses ("Basic"/"Voiced"/"Combos"),
    /// same treatment as Hiragana/Katakana elsewhere: romanized in Latin scripts,
    /// transliterated or given the native term otherwise. A learner meets these words
    /// in every other kana resource, so naming the tabs after them teaches something —
    /// "Combos" doesn't survive contact with a textbook.
    var title: String {
        switch self {
        case .seion:  return L.t("Seion")     // 清音
        case .dakuon: return L.t("Dakuon")    // 濁音
        case .youon:  return L.t("Youon")     // 拗音
        }
    }
    var rows: [[K]] {
        switch self {
        case .seion:  return KanaData.seion
        case .dakuon: return KanaData.dakuon
        case .youon:  return KanaData.youon
        }
    }
}

struct KanaBrowserView: View {
    @Environment(\.modelContext) private var context
    @Query private var results: [KanaResult]
    @State private var table: KanaTable = .seion
    @AppStorage(Pref.kanaTileScript) private var tileScript = 0   // 0 hira · 1 kata · 2 romaji
    @State private var showQuiz = false
    @State private var confirmClear = false

    /// What the toolbar button rotates through, in order. Index is the stored
    /// `Pref.kanaTileScript` value and `KanaTileView.big`, so the order is a persisted
    /// contract — appending is safe, reordering would silently rewrite everyone's setting.
    /// `name` keys the existing localized strings the old menu used.
    private static let tileScripts: [(glyph: String, name: String)] = [
        ("あ", "Hiragana"), ("ア", "Katakana"), ("A", "Romaji"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Kana set", selection: $table) {
                    ForEach(KanaTable.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                ScrollView {
                    // Combos (拗音) are 3 columns instead of 5 — forcing them square
                    // would make each tile huge and out of proportion with the other
                    // two tables, so only Basic/Voiced go square.
                    KanaGrid(rows: table.rows, big: tileScript, square: table != .youon)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 24)
                }
            }
            .background(Theme.canvas)
            .navigationTitle(L.t("Kana"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { Track.screen("kana") }
            // Which chart people actually study, and which script they read it in —
            // the two study preferences this screen exposes.
            .onChange(of: table) { Track.event("kana_table", ["table": table.rawValue]) }
            .onChange(of: tileScript) { Track.event("kana_tile_script", ["script": tileScript]) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) { confirmClear = true } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(results.isEmpty)
                }
                // What the tiles show big. One tap rotates hiragana → katakana → romaji.
                //
                // Not a menu and not a second segmented row: there are only three values,
                // they're mutually exclusive, and the button's own glyph already shows which
                // one is active — so a dropdown spent two taps and a covered screen saying
                // what one tap says. (Two stacked segmented controls looked cluttered, which
                // is why the menu existed in the first place.)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        tileScript = (tileScript + 1) % Self.tileScripts.count
                    } label: {
                        Text(Self.tileScripts[tileScript].glyph)
                            // Romaji is Latin, so it takes the rounded Latin face rather than
                            // the Japanese one — same split as the tiles themselves.
                            .font(tileScript == 2 ? Theme.display(15, weight: .semibold)
                                                  : Theme.jpBold(15))
                    }
                    // Sighted users read the state off the glyph; VoiceOver needs the name.
                    // Reuses the three names the menu used, so this costs no new strings.
                    .accessibilityLabel(L.t(Self.tileScripts[tileScript].name))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(L.t("Quiz")) { showQuiz = true; Track.event("kana_quiz_open") }
                }
            }
            .confirmationDialog(L.t("Clear all learned kana?"),
                                isPresented: $confirmClear, titleVisibility: .visible) {
                Button(L.t("Clear %@", "\(results.count)"), role: .destructive) { clearAll() }
                Button(L.t("Cancel"), role: .cancel) {}
            } message: {
                Text(L.t("Resets the green/red progress on every kana tile."))
            }
            .navigationDestination(isPresented: $showQuiz) {
                KanaQuizModeView(table: table)
            }
        }
    }

    private func clearAll() {
        try? context.delete(model: KanaResult.self)
        try? context.save()
        Track.event("kana_clear")
    }
}

private struct KanaGrid: View {
    let rows: [[K]]
    var big = 0
    var square = true
    @Query private var results: [KanaResult]
    @Environment(\.pronouncer) private var pronouncer
    @State private var width: CGFloat = 0

    private let spacing: CGFloat = 6
    private let flexibleHeight: CGFloat = 64

    /// Latest answer per kana. Merged by timestamp, not first-wins: a CloudKit merge
    /// can leave duplicate rows, and "the most recent answer" is this store's meaning.
    private var byRomaji: [String: Bool] {
        Dictionary(results.map { ($0.romaji, ($0.timestamp, $0.isCorrect)) },
                   uniquingKeysWith: { a, b in a.0 >= b.0 ? a : b })
            .mapValues(\.1)
    }

    private var cols: Int { rows.map(\.count).max() ?? 1 }
    /// Explicit width/height per tile, computed from the measured row width —
    /// `.aspectRatio(1, .fit)` combined with a flexible `.frame(maxWidth: .infinity)`
    /// inside an HStack doesn't reliably divide space evenly (each tile can end up
    /// a different size); a fixed square size is deterministic.
    private var tileSize: CGFloat {
        guard width > 0 else { return flexibleHeight }
        return (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        if cell.isEmpty {
                            sized(Color.clear)
                        } else {
                            sized(
                                KanaTileView(cell: cell, lastCorrect: byRomaji[cell.romaji], big: big)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        pronouncer.speak(kana: cell)
                                        Track.event("play_kana", ["romaji": cell.romaji])
                                    }
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)   // measure the full row width, not the content's own
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
    }

    @ViewBuilder private func sized<V: View>(_ view: V) -> some View {
        if square {
            view.frame(width: tileSize, height: tileSize)
        } else {
            view.frame(maxWidth: .infinity).frame(height: flexibleHeight)
        }
    }
}

struct KanaTileView: View {
    let cell: K
    let lastCorrect: Bool?
    var big = 0   // 0 hiragana · 1 katakana · 2 romaji

    private var bigText: String { [cell.hiragana, cell.katakana, cell.romaji][big] }

    /// Romaji is Latin text and gets the rounded Latin face; kana gets the Japanese one.
    /// `Theme.jpBold` is Hiragino Sans, which *has* Latin glyphs — so a romaji tile rendered
    /// with it looked plain rather than broken, which is exactly why it survived unnoticed.
    private var bigFont: Font { big == 2 ? Theme.display(26, weight: .semibold) : Theme.jpBold(26) }
    private var caption: [String] {
        switch big {
        case 1:  return [cell.hiragana, cell.romaji]
        case 2:  return [cell.hiragana, cell.katakana]
        default: return [cell.katakana, cell.romaji]
        }
    }

    private var border: Color {
        switch lastCorrect {
        case .some(true):  return Theme.correct
        case .some(false): return Theme.wrong
        case .none:        return Theme.line
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(bigText).font(bigFont).minimumScaleFactor(0.5).lineLimit(1)
            HStack(spacing: 6) {
                Text(caption[0])
                Text(caption[1])
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(border, lineWidth: 1.5))
    }
}

#Preview {
    KanaBrowserView()
        .modelContainer(for: KanaResult.self, inMemory: true)
}
