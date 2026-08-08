import SwiftUI
import StoreKit

/// The Airtable feedback form (inherited from the RN app), prefilled with the platform
/// and with where the user came from — Settings is someone choosing to write in, a
/// low star rating is someone we sent. Those are different populations and the form
/// can't tell them apart otherwise.
enum Feedback {
    static func url(source: String) -> URL {
        URL(string: "https://airtable.com/shr7xvYAyInUbJNif?prefill_Platform=iOS&prefill_Source=\(source)")!
    }
}

/// Asks for a rating, but only from people who have earned the right to be asked and
/// only once.
///
/// The shape is deliberate: a *custom* star picker first, and only a 4- or 5-star pick
/// hands off to Apple's real review sheet. A low pick opens the feedback form instead.
/// Apple's sheet gives no signal about what was submitted and is rate-limited to a
/// handful of impressions a year, so spending one on someone about to leave two stars
/// wastes the only asks the app gets. Routing unhappy taps to the form turns the same
/// moment into something actionable — and the person gets a reply rather than a
/// one-way star.
///
/// Note this is not a rating *gate*: the App Store prohibits making a review path
/// conditional on sentiment, and nothing here blocks anyone. The star row is the app's
/// own question, every answer leads somewhere, and the App Store page stays reachable
/// from Settings regardless.
enum RatingPrompt {
    /// Asked once, ever. Apple's own throttle would silently swallow a second ask
    /// anyway, so a second one is only a chance to annoy.
    static var hasAsked: Bool { UserDefaults.standard.bool(forKey: Pref.ratingAsked) }
    static func markAsked() { UserDefaults.standard.set(true, forKey: Pref.ratingAsked) }

    /// Whether to ask after this challenge.
    ///
    /// Subscribers only — they've already said the app is worth paying for, and the
    /// question is "would you say so publicly" rather than a cold ask. A free user's
    /// most likely rating is about the paywall, which the star row can't fix.
    ///
    /// The other two conditions pick the moment: a *passed* rung (asking after a fail
    /// asks how they feel about failing) that isn't their first (someone one challenge
    /// in has nothing to rate yet).
    static func shouldAsk(isPremium: Bool, passed: Bool, passedCount: Int) -> Bool {
        isPremium && passed && passedCount >= 3 && !hasAsked
    }

    /// 4★ and up → Apple's review sheet. Apple decides whether it actually appears;
    /// there's no callback and no guarantee, which is exactly why the star row exists
    /// in front of it.
    @MainActor static func requestAppStoreReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        AppStore.requestReview(in: scene)
    }
}

/// The star row itself. Deliberately not a `.alert`: an alert can't hold a tappable
/// star row, and the whole point is that the rating is chosen here rather than in
/// Apple's sheet.
struct RatingSheet: View {
    /// Called with the chosen 1–5 once the user commits.
    let onRate: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var stars = 0

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)

            Text(L.t("Enjoying Japanese Daily?"))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(L.t("Tap a star to tell us how it's going."))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        stars = i
                        // A beat on the filled star before the sheet goes, so the tap
                        // registers as an answer rather than just closing something.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            dismiss()
                            onRate(i)
                        }
                    } label: {
                        Image(systemName: i <= stars ? "star.fill" : "star")
                            .font(.system(size: 32))
                            .foregroundStyle(i <= stars ? Theme.accent : Color.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("%@ stars", "\(i)"))
                }
            }
            .padding(.vertical, 4)

            Button(L.t("Not now")) {
                dismiss()
                Track.event("rating_dismissed")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(28)
        .presentationDetents([.height(340)])
    }
}
