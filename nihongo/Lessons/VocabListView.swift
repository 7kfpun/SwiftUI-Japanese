import SwiftUI

struct VocabListView: View {
    let lesson: Lesson

    var body: some View {
        List(lesson.entries) { VocabRow(vocab: $0) }
            .navigationTitle(L.t("Lesson %@", "\(lesson.number)"))
            .navigationBarTitleDisplayMode(.inline)
    }
}
