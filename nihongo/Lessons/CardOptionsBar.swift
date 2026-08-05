import SwiftUI

/// The field-visibility + sound toggles, persisted via @AppStorage (RN CardOptionSelector).
struct CardOptions {
    @AppStorage("isKanjiShown")       var showKanji = true
    @AppStorage("isKanaShown")        var showKana = true
    @AppStorage("isRomajiShown")      var showRomaji = true
    @AppStorage("isTranslationShown") var showTranslation = true
    @AppStorage("isSoundOn")          var soundOn = true
    @AppStorage("isOrdered")          var ordered = true
}

struct CardOptionsBar: View {
    @AppStorage("isKanjiShown")       private var showKanji = true
    @AppStorage("isKanaShown")        private var showKana = true
    @AppStorage("isRomajiShown")      private var showRomaji = true
    @AppStorage("isTranslationShown") private var showTranslation = true
    @AppStorage("isSoundOn")          private var soundOn = true

    var body: some View {
        HStack(spacing: 18) {
            toggle($showKanji, "漢")
            toggle($showKana, "か")
            toggle($showRomaji, "R")
            toggle($showTranslation, "A")
            toggle($soundOn, nil, onImage: "speaker.wave.2.fill", offImage: "speaker.slash")
        }
        .font(.callout)
    }

    private func toggle(_ value: Binding<Bool>, _ text: String?,
                        onImage: String? = nil, offImage: String? = nil) -> some View {
        Button {
            value.wrappedValue.toggle()
        } label: {
            Group {
                if let text {
                    Text(text)
                } else {
                    Image(systemName: value.wrappedValue ? (onImage ?? "") : (offImage ?? ""))
                }
            }
            .frame(width: 34, height: 30)
            .background(value.wrappedValue ? Theme.accent.opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(value.wrappedValue ? Theme.accent : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}
