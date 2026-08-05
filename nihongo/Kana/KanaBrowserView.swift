import SwiftUI
import SwiftData

enum KanaTable: String, CaseIterable, Identifiable {
    case seion, dakuon, youon
    var id: String { rawValue }
    var title: String {
        switch self {
        case .seion:  return "清音"
        case .dakuon: return "濁音"
        case .youon:  return "拗音"
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
    @State private var showQuiz = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Kana set", selection: $table) {
                    ForEach(KanaTable.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                ScrollView {
                    KanaGrid(rows: table.rows)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 24)
                }
            }
            .background(Theme.canvas)
            .navigationTitle(L.t("Kana"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) { confirmClear = true } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(results.isEmpty)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(L.t("Quiz")) { showQuiz = true }
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
    }
}

private struct KanaGrid: View {
    let rows: [[K]]
    @Query private var results: [KanaResult]
    @Environment(\.pronouncer) private var pronouncer

    private var byRomaji: [String: Bool] {
        Dictionary(results.map { ($0.romaji, $0.isCorrect) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        if cell.isEmpty {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 64)
                        } else {
                            KanaTileView(cell: cell, lastCorrect: byRomaji[cell.romaji])
                                .contentShape(Rectangle())
                                .onTapGesture { pronouncer.speak(kana: cell.hiragana) }
                        }
                    }
                }
            }
        }
    }
}

struct KanaTileView: View {
    let cell: K
    let lastCorrect: Bool?

    private var border: Color {
        switch lastCorrect {
        case .some(true):  return Theme.correct
        case .some(false): return Theme.wrong
        case .none:        return Color(.separator)
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(cell.hiragana).font(.title).fontWeight(.light)
            HStack(spacing: 6) {
                Text(cell.katakana)
                Text(cell.romaji)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(border, lineWidth: 1.5))
    }
}

#Preview {
    KanaBrowserView()
        .modelContainer(for: KanaResult.self, inMemory: true)
}
