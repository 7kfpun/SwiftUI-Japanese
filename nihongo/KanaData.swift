import Foundation

/// A kana cell: hiragana, katakana, romaji, and textbook stroke counts per script.
/// Empty strings are grid-alignment placeholders.
struct K: Hashable, Identifiable {
    let hiragana: String, katakana: String, romaji: String
    let hiraganaStrokes: Int, katakanaStrokes: Int
    init(_ h: String, _ k: String, _ r: String, _ hStrokes: Int = 0, _ kStrokes: Int = 0) {
        hiragana = h; katakana = k; romaji = r
        hiraganaStrokes = hStrokes; katakanaStrokes = kStrokes
    }
    var isEmpty: Bool { romaji.isEmpty }
    var id: String { romaji.isEmpty ? "_" + hiragana + katakana : romaji }
}

/// The kana chart, loaded from the bundled KanaChart.json (copied verbatim from
/// minna's vocab/kana.json by scripts/build-minna-data.py) — grid layout, romaji,
/// and stroke counts all come from the data file, not code.
enum KanaData {
    static let seion  = grid("seion", cols: 5)
    static let dakuon = grid("dakuon", cols: 5)
    static let youon  = grid("youon", cols: 3)

    // MARK: chart loading

    private struct Chart: Decodable { let data: [String: [Entry]] }
    private struct Entry: Decodable {
        struct Strokes: Decodable { let hiragana: Int, katakana: Int }
        let hiragana: String, katakana: String, romaji: String
        let row: Int, col: Int
        let strokes: Strokes
    }

    private static let chart: [String: [Entry]] = {
        guard let url = Bundle.main.url(forResource: "KanaChart", withExtension: "json"),
              let chart = try? JSONDecoder().decode(Chart.self, from: Data(contentsOf: url))
        else { fatalError("KanaChart.json missing — run scripts/build-minna-data.py") }
        return chart.data
    }()

    /// Place entries by row/col, pad gaps with placeholders, trim trailing empties
    /// (so ん sits alone on its row, exactly like the printed chart).
    private static func grid(_ group: String, cols: Int) -> [[K]] {
        let entries = chart[group] ?? []
        let rowCount = (entries.map(\.row).max() ?? -1) + 1
        var rows = [[K]](repeating: [K](repeating: K("", "", ""), count: cols), count: rowCount)
        for e in entries {
            rows[e.row][e.col] = K(e.hiragana, e.katakana, e.romaji,
                                   e.strokes.hiragana, e.strokes.katakana)
        }
        return rows.map { row in
            var row = row
            while let last = row.last, last.isEmpty { row.removeLast() }
            return row
        }
    }

    /// Flat distractor pools for the Lessons → Learn tile game (74 each):
    /// every kana that can appear inside a vocab word, including small ゃゅょ.
    static let hiraganaPool: [String] = ["あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ", "が", "ぎ", "ぐ", "げ", "ご", "さ", "し", "す", "せ", "そ", "ざ", "じ", "ず", "ぜ", "ぞ", "た", "ち", "つ", "て", "と", "だ", "ぢ", "づ", "で", "ど", "な", "に", "ぬ", "ね", "の", "は", "ひ", "ふ", "へ", "ほ", "ば", "び", "ぶ", "べ", "ぼ", "ぱ", "ぴ", "ぷ", "ぺ", "ぽ", "ま", "み", "む", "め", "も", "や", "ゆ", "よ", "ゃ", "ゅ", "ょ", "ら", "り", "る", "れ", "ろ", "わ", "を", "ん"]
    static let katakanaPool: [String] = ["ア", "イ", "ウ", "エ", "オ", "カ", "キ", "ク", "ケ", "コ", "ガ", "ギ", "グ", "ゲ", "ゴ", "サ", "シ", "ス", "セ", "ソ", "ザ", "ジ", "ズ", "ゼ", "ゾ", "タ", "チ", "ツ", "テ", "ト", "ダ", "ヂ", "ヅ", "デ", "ド", "ナ", "ニ", "ヌ", "ネ", "ノ", "ハ", "ヒ", "フ", "ヘ", "ホ", "バ", "ビ", "ブ", "ベ", "ボ", "パ", "ピ", "プ", "ペ", "ポ", "マ", "ミ", "ム", "メ", "モ", "ヤ", "ユ", "ヨ", "ャ", "ュ", "ョ", "ラ", "リ", "ル", "レ", "ロ", "ワ", "ヲ", "ン"]
}
