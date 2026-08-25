import SwiftUI

/// Sharing the app, and the nudge that suggests it.
///
/// Kept strictly separate from `RatingPrompt` even though the two now look very alike:
/// same audience, same two-month window, same trigger. What differs is what they ask for
/// — a public verdict on the App Store versus a word to a friend — and that the rating is
/// additionally rate-limited by Apple, whose own throttle no code here can see. They share
/// a moment (a just-passed rung) and must never share an *occasion*: see `ChallengeView`,
/// where the rating gets first refusal.
enum SharePrompt {
    /// Where a shared link came from, as an App Store campaign token.
    ///
    /// **`ct`, not `utm_*`.** `apps.apple.com` ignores `utm_` parameters entirely — those
    /// are a Google Analytics convention and nothing on Apple's side reads them, so a
    /// `utm_source` on a store link is decoration. The parameter App Store Connect
    /// actually reports on is `ct` (campaign token), under App Analytics → Campaigns,
    /// where it attributes impressions, downloads and even later proceeds.
    ///
    /// The token names the *surface*, never the person: every user sharing from the
    /// nudge sends the identical string, so it groups traffic without becoming an
    /// identifier — the rule against minting one holds here as everywhere else.
    ///
    /// Values are lowercase, stable and short. Apple caps `ct` at 40 characters and
    /// treats it as an opaque string, so renaming one splits its history in two; add a
    /// case rather than re-wording an existing one.
    enum Campaign: String {
        /// The in-app nudge after a passed rung.
        case prompt = "app_share_prompt"
        /// The Settings row, tapped deliberately rather than offered.
        case settings = "app_share_settings"
    }

    /// The listing to send people to. Course-specific: the two apps are two listings, and
    /// a JLPT user recommending the Minna app would be the kind of mistake nobody reports.
    ///
    /// `campaign` is appended as `ct`. Nil yields the bare listing URL, which is what
    /// anything that isn't a share should use.
    static func appStoreURL(campaign: Campaign? = nil) -> URL {
        let base = URL(string: Course.current.appStoreURL)!
        guard let campaign,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return base }
        // Appended rather than assigned: the listing URLs carry no query today, but a
        // future one might, and silently dropping it would be a broken link nobody tests.
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "ct", value: campaign.rawValue)
        ]
        return components.url ?? base
    }

    /// What actually gets shared — one line and the link. Deliberately not a paragraph:
    /// this lands in a message someone is writing to a friend, and a wall of marketing
    /// copy is something they'd have to delete before sending.
    static func shareText(campaign: Campaign) -> String {
        "\(L.t("Learn Japanese with me")) — \(appStoreURL(campaign: campaign).absoluteString)"
    }

    // MARK: - The nudge

    /// Two months, at most. Long enough that it reads as a suggestion rather than a
    /// campaign; short enough to catch someone in a stretch of real use.
    static let askAgainAfter: TimeInterval = 60 * 24 * 60 * 60

    /// Rungs passed before the app suggests anything — about a lesson's worth.
    ///
    /// A third of the rating's 21, and deliberately: that one asks for a public verdict on
    /// the App Store, which needs a body of experience behind it. This asks someone to
    /// mention the app to a friend, which needs only that the app has visibly worked for
    /// them.
    static let challengesRequired = 7

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

    /// Diagnostics only — the two-month window is the one condition no amount of
    /// practising can undo. Nothing in the app calls this.
    static func resetAsked() {
        UserDefaults.standard.removeObject(forKey: Pref.shareAskedAt)
    }

    /// Whether to suggest sharing after this challenge.
    ///
    /// `ratingShown` is the important argument. Both prompts trigger on a passed rung, and
    /// a user who just answered the star row being handed a second sheet would read the
    /// app as begging. The rating takes precedence because Apple rate-limits it to a
    /// handful of impressions a year, so a wasted occasion costs it more; this one is
    /// limited only by the window here.
    ///
    /// Its lower bar is the other half of that split — someone with a lesson's worth of
    /// rungs behind them has enough to recommend, if not yet enough to review.
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
    /// Whether the share button was the way out, so the dismissal event can say which of
    /// the three exits this was.
    @State private var accepted = false

    var body: some View {
        VStack(spacing: 20) {
            PromptHeader(icon: "heart.text.square",
                         title: L.t("Know someone learning Japanese?"),
                         blurb: L.t("A recommendation from you is worth more than any ad."))

            Button {
                accepted = true
                // The same name Settings' row logs, with the other `source`, so "how many
                // people opened a share sheet" is one event grouped by where it came from.
                Track.event("share_opened", ["source": "prompt"])
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
        .scrollableWhenCramped()
        .presentationDetents([.height(360), .large])
        // `onDisappear`, not the "Not now" button — the same lesson `PaywallView` records.
        // Swiping the sheet away is a third exit, and counting only the button would make
        // `accepted` a rate over an undercounted denominator. `share_prompt_shown` fires
        // from `ChallengeView` and had no counterpart at all until this.
        .onDisappear {
            Track.event("share_prompt_dismissed", ["accepted": accepted])
        }
    }
}

/// A row that raises the system share sheet. Used in Settings.
struct ShareAppLink: View {
    var body: some View {
        ShareLink(item: SharePrompt.appStoreURL(campaign: .settings),
                  message: Text(SharePrompt.shareText(campaign: .settings))) {
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
