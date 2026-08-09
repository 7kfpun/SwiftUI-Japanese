import Foundation
import Observation
import WatchConnectivity
import WidgetKit

/// Today's deck as the watch knows it, plus the WatchConnectivity receiver that keeps it
/// current. The phone owns the deck (see WatchLink.swift on the iOS side); the watch only
/// ever adopts what arrives.
///
/// Everything that lands here is also written into the watch's own App Group container.
/// That is the whole point: the complications run in a separate process that never sees
/// this session, so the App Group is how they get the same words.
@Observable
final class WatchToday: NSObject, WCSessionDelegate {
    /// The shared fallback deck — see `TodayShared.sampleWords`.
    static let sampleWords = TodayShared.sampleWords

    private(set) var words: [TodayShared.Word] = WatchToday.sampleWords
    private(set) var lesson = 1
    /// Whether `words` is the real deck or the fallback — the view says so quietly, so a
    /// learner isn't left wondering why the wrist disagrees with the phone.
    private(set) var isSynced = false

    override init() {
        super.init()
        // A snapshot from an earlier sync is already on disk; show it before the session
        // has had a chance to activate rather than flashing the sample deck first.
        adopt(TodayShared.read())
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - WCSessionDelegate
    // Callbacks arrive off the main thread; the observable state above is main-actor.

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        // The last context the phone sent is replayed on activation, so a watch that was
        // asleep through the actual push still catches up here.
        let context = session.receivedApplicationContext
        Task { @MainActor in self.absorb(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.absorb(context) }
    }

    private func absorb(_ context: [String: Any]) {
        guard let data = context["snapshot"] as? Data,
              let snapshot = try? JSONDecoder().decode(TodayShared.Snapshot.self, from: data),
              !snapshot.words.isEmpty else { return }
        TodayShared.write(snapshot)
        adopt(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func adopt(_ snapshot: TodayShared.Snapshot?) {
        guard let snapshot, !snapshot.words.isEmpty else { return }
        words = snapshot.words
        lesson = snapshot.lesson
        isSynced = true
    }
}
