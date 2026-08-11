import SwiftUI

/// Sharing the app, and the once-a-month nudge that suggests it.
///
/// Kept strictly separate from `RatingPrompt` even though the two look alike: a rating is
/// a favour asked of a paying user and is rate-limited by Apple; a recommendation is a
/// favour asked of anyone and is limited only by taste. They share a moment (a just-passed
/// rung) and must never share an *occasion* — see `ChallengeView`, where the rating wins.
enum SharePrompt {
    /// The listing to send people to. Course-specific: the two apps are two listings, and
    /// a JLPT user recommending the Minna app would be the kind of mistake nobody reports.
    static var appStoreURL: URL {
        URL(string: Course.current.appStoreURL)!
    }

    /// What actually gets shared — one line and the link. Deliberately not a paragraph:
    /// this lands in a message someone is writing to a friend, and a wall of marketing
    /// copy is something they'd have to delete before sending.
    static func shareText() -> String {
        "\(L.t("Learn Japanese with me")) — \(appStoreURL.absoluteString)"
    }

    // MARK: - The nudge

    /// One a month, at most. Long enough that it reads as a suggestion rather than a
    /// campaign; short enough to catch someone in a stretch of real use.
    static let askAgainAfter: TimeInterval = 30 * 24 * 60 * 60

    /// Rungs passed before the app suggests anything — one, i.e. the first rung anyone
    /// clears.
    ///
    /// Far below the rating's 15, and deliberately: that one asks for a public verdict on
    /// the App Store, which needs a body of experience behind it. This asks someone to
    /// mention the app to a friend, and the best moment for that is the first time it
    /// visibly worked, while the feeling is fresh. The 30-day window is what keeps a low
    /// bar from becoming a nag — someone who says no is not asked again for a month.
    static let challengesRequired = 1

    static var lastAskedAt: Date? {
        let stamp = UserDefaults.standard.double(forKey: Pref.shareAskedAt)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    static var mayAskAgain: Bool {
        guard let last = lastAskedAt else { return true }
        return Date().timeIntervalSince(last) >= askAgainAfter
    }

    static func markAsked() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Pref.shareAskedAt)
    }

    /// Diagnostics only — the month is the one condition no amount of practising can
    /// undo, and nobody can wait a month to test a build. Nothing in the app calls this.
    static func resetAsked() {
        UserDefaults.standard.removeObject(forKey: Pref.shareAskedAt)
    }

    /// Whether to suggest sharing after this challenge.
    ///
    /// `ratingShown` is the important argument. Both prompts trigger on a passed rung, and
    /// a user who just answered the star row being handed a second sheet would read the
    /// app as begging. The rating takes precedence because Apple rate-limits it to a
    /// handful of impressions a year; this one comes back next month regardless.
    ///
    /// Not restricted to subscribers, unlike the rating: a free user recommending the app
    /// is exactly the person this is for, and there is nothing to be embarrassed about in
    /// a lesson they got for free.
    static func shouldAsk(passed: Bool, passedCount: Int, ratingShown: Bool) -> Bool {
        passed && !ratingShown && passedCount >= challengesRequired && mayAskAgain
    }
}

/// The nudge itself. A sheet rather than an alert so the share sheet can be raised from
/// it directly, and so "Not now" is a plain, unpunished way out.
struct ShareSheetPrompt: View {
    /// Called when the user chooses to share, after this sheet has dismissed — presenting
    /// the system share sheet from a view that is on its way out drops it silently.
    let onShare: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)

            Text(L.t("Know someone learning Japanese?"))
                .font(Theme.title(.title3))
                .multilineTextAlignment(.center)

            Text(L.t("A recommendation from you is worth more than any ad."))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                dismiss()
                // A beat, so the share sheet rises after this one has gone rather than
                // fighting it for the presentation slot.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onShare() }
            } label: {
                Label(L.t("Share the app"), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)

            Button(L.t("Not now")) { dismiss() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .presentationDetents([.height(360)])
    }
}

/// A row that raises the system share sheet. Used in Settings.
struct ShareAppLink: View {
    var body: some View {
        ShareLink(item: SharePrompt.appStoreURL, message: Text(SharePrompt.shareText())) {
            Label(L.t("Share the app"), systemImage: "square.and.arrow.up")
        }
        .simultaneousGesture(TapGesture().onEnded {
            Track.event("share_opened", ["source": "settings"])
        })
    }
}

extension View {
    /// The system share sheet, driven by a binding.
    ///
    /// `ShareLink` covers every case where the trigger is a button that still exists when
    /// the sheet opens. The nudge is the case it doesn't: its button dismisses its own
    /// sheet first, so by the time anything can be presented the `ShareLink` is gone.
    func shareSheet(isPresented: Binding<Bool>, items: [Any]) -> some View {
        sheet(isPresented: isPresented) {
            ActivityView(items: items)
                .presentationDetents([.medium, .large])
        }
    }
}

/// `UIActivityViewController`, the thing `ShareLink` wraps. Used directly only where a
/// binding is needed rather than a button.
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activity, completed, _, _ in
            Track.event("share_completed", ["source": "prompt",
                                            "completed": completed,
                                            "activity": activity?.rawValue ?? "none"])
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
