import Foundation
import WatchConnectivity

/// Ships Today's deck to the watch app.
///
/// The home-screen widget reads the deck straight out of the App Group, but that trick
/// stops at the platform boundary: `group.com.kfpun.nihongo` on watchOS is a *different*
/// container that iOS cannot write to. WatchConnectivity is the only bridge, so the watch
/// app re-writes whatever arrives into its own container — from there the complications
/// read it back through the ordinary `TodayShared.read()`, none the wiser.
///
/// `updateApplicationContext` rather than `sendMessage` because Today only ever needs the
/// *latest* deck: each push overwrites the last, it survives both apps being closed, and
/// it lands on the watch's next wake instead of requiring a live, reachable session.
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    private var session: WCSession? { WCSession.isSupported() ? .default : nil }
    private var activating = false
    /// Last payload handed to WatchConnectivity. `publishWidget()` runs on every Today
    /// appear, and re-sending an unchanged deck wakes the watch for nothing.
    private var lastSent: Data?
    /// Held while the session is still activating, or while no watch can receive it yet
    /// (unpaired, app not installed) — so a watch that shows up later still gets today's
    /// words instead of waiting for the next time the deck happens to change.
    private var pending: Data?

    /// Publish a snapshot to the paired watch. Cheap and idempotent — safe to call from
    /// `publishWidget()` on every deal.
    func send(_ snapshot: TodayShared.Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot), data != lastSent else { return }
        lastSent = data
        pending = data
        activate()
        flush()
    }

    private func activate() {
        guard let session, !activating else { return }
        activating = true
        session.delegate = self
        session.activate()
    }

    private func flush() {
        guard let data = pending, let session,
              session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        // A throw here means the context was rejected outright; keep `pending` so the
        // next activation or watch-state change retries rather than dropping the deck.
        if (try? session.updateApplicationContext(["snapshot": data])) != nil { pending = nil }
    }

    // MARK: - WCSessionDelegate
    // Callbacks arrive off the main thread; everything above is main-actor state.

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.flush() }
    }

    /// Pairing, installing the watch app, or unlocking a watch that was out of range —
    /// all of them are the moment a previously undeliverable deck becomes deliverable.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.flush() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched to a different watch — reactivate so the new one gets Today too.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
