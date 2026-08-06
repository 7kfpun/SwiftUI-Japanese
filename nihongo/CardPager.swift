import SwiftUI

/// Shared horizontal card-paging gesture (Learn, Today): drag with a slight rotation,
/// fling off-screen, then the next card re-enters from the opposite side.
///
/// `page` receives +1 (forward / swipe left) or -1 (back / swipe right). `canPage`
/// gates paging (e.g. trial limits) — when it refuses, `onBlocked` fires instead.
/// Set `fling` to page programmatically with the same animation (e.g. a shuffle
/// button). Re-entrancy is guarded: a swipe mid-animation is ignored.
struct CardPager: ViewModifier {
    var canPage: () -> Bool = { true }
    var onBlocked: () -> Void = {}
    let page: (Int) -> Void
    @Binding var fling: Int?

    @State private var drag: CGFloat = 0
    @State private var animating = false
    private let threshold: CGFloat = 80

    func body(content: Content) -> some View {
        content
            .offset(x: drag)
            .rotationEffect(.degrees(Double(drag / 30)))
            .gesture(
                DragGesture()
                    .onChanged { if !animating { drag = $0.translation.width } }
                    .onEnded { end($0.translation.width) }
            )
            .onChange(of: fling) {
                if let dir = fling { fling = nil; commit(dir) }
            }
    }

    private func end(_ width: CGFloat) {
        guard abs(width) > threshold else { withAnimation(.spring) { drag = 0 }; return }
        commit(width < 0 ? 1 : -1)
    }

    private func commit(_ dir: Int) {
        guard !animating else { return }
        guard canPage() else {
            withAnimation(.spring) { drag = 0 }
            onBlocked()
            return
        }
        animating = true
        let out: CGFloat = dir > 0 ? -500 : 500      // forward flings left, like a page turn
        withAnimation(.easeOut(duration: 0.18)) { drag = out }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            page(dir)
            drag = -out                               // new card enters from the opposite side
            withAnimation(.spring) { drag = 0 }
            animating = false
        }
    }
}

extension View {
    /// Attach card-paging swipe behavior. See `CardPager`.
    func cardPager(fling: Binding<Int?> = .constant(nil),
                   canPage: @escaping () -> Bool = { true },
                   onBlocked: @escaping () -> Void = {},
                   page: @escaping (Int) -> Void) -> some View {
        modifier(CardPager(canPage: canPage, onBlocked: onBlocked, page: page, fling: fling))
    }
}
