import SwiftUI

/// The field-visibility + sound toggles for Learn mode, persisted via @AppStorage
/// (port of the RN CardOptionSelector). Read the same keys directly on the host view
/// (not via a wrapper struct) so the card re-renders the moment a toggle flips.
struct CardOptionsBar: View {
    @AppStorage(Pref.kanjiShown)       private var showKanji = true
    @AppStorage(Pref.kanaShown)        private var showKana = true
    @AppStorage(Pref.romajiShown)      private var showRomaji = true
    @AppStorage(Pref.translationShown) private var showTranslation = true
    @AppStorage(Pref.soundOn)          private var soundOn = true

    var body: some View {
        HStack(spacing: 14) {
            chip($showKanji, "kanji") { Text("漢") }
            chip($showKana, "kana") { Text("か") }
            chip($showRomaji, "romaji") { Text("A") }                 // Latin letter → romaji
            chip($showTranslation, "meaning") { Image(systemName: "globe") }
            chip($soundOn, "sound") {
                Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash")
            }
        }
        .font(.callout)
    }

    private func chip<Label: View>(_ value: Binding<Bool>, _ name: String,
                                   @ViewBuilder _ label: () -> Label) -> some View {
        Button {
            value.wrappedValue.toggle()
            Track.event("toggle_field", ["field": name, "shown": value.wrappedValue])
        } label: {
            label()
                .frame(width: 36, height: 30)
                .background(value.wrappedValue ? Theme.accent.opacity(0.15) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(value.wrappedValue ? Theme.accent : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) \(value.wrappedValue ? "shown" : "hidden")")
    }
}
