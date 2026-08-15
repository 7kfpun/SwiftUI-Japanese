import Foundation
import UIKit
import UserNotifications
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif
#if canImport(OneSignalFramework)
import OneSignalFramework
#endif

/// Remote push, for messages that originate with **us** — announcements, new content, a
/// campaign to lapsed learners. The learner's own clock is `StreakReminder`'s job and
/// stays on device; nothing here is needed to remind someone about their streak.
///
/// ## Two providers, one delegate
///
/// FCM and OneSignal overlap almost completely, and running both is only safe because
/// this type is the single owner of the push plumbing:
///
/// - `FirebaseAppDelegateProxyEnabled` is `NO` in both Info.plists, so Firebase does not
///   swizzle `UIApplicationDelegate`.
/// - `AppDelegate` forwards the APNs token here, and this hands it to each SDK by name.
/// - `UNUserNotificationCenter.delegate` is set **once**, to `shared`.
///
/// Take any of those away and the two SDKs race for the same callbacks. The loser stops
/// receiving anything, with no error and no crash — the failure shows up as a campaign
/// that went out and reached nobody, which is the kind of bug that gets diagnosed weeks
/// late. If one provider is ever dropped, delete its branch here rather than turning the
/// proxy back on.
///
/// ## Permission
///
/// Deliberately **not** requested here. `StreakReminder.requestAuthorization()` is the one
/// prompt, raised from an explicit opt-in in Settings, and the grant it returns covers
/// push too — iOS has a single per-app notification permission. Registering for remote
/// notifications without it is legal and silent, so this only registers once authorized.
@MainActor
final class PushService: NSObject {
    static let shared = PushService()

    /// OneSignal App ID. **Placeholder** — replace with the real one from
    /// OneSignal → Settings → Keys & IDs before shipping, the same way the AdMob app ID
    /// in `jlpt-Info.plist` is still Google's test value. Left as an empty string rather
    /// than a fake UUID so `start()` skips OneSignal cleanly instead of initializing it
    /// against an app that doesn't exist.
    static var oneSignalAppID: String {
        (Bundle.main.object(forInfoDictionaryKey: "OneSignalAppID") as? String) ?? ""
    }

    private var started = false

    /// Wire up both providers. Safe to call more than once.
    ///
    /// Called from `AppDelegate` *after* `FirebaseApp.configure()`, because
    /// `Messaging.messaging()` requires a configured app and returns a useless instance
    /// before one exists.
    func start(launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) {
        guard !started else { return }
        started = true

        #if canImport(FirebaseMessaging)
        if FirebaseApp.app() != nil { Messaging.messaging().delegate = self }
        #endif

        #if canImport(OneSignalFramework)
        let appID = Self.oneSignalAppID
        if !appID.isEmpty {
            #if DEBUG
            // Verbose only in Debug. OneSignal's own guide shows `.LL_VERBOSE`
            // unconditionally, which in a Release build prints SDK internals to the
            // device console for anyone with a cable.
            OneSignal.Debug.setLogLevel(.LL_VERBOSE)
            #endif
            // Real `launchOptions`, not nil: they carry the notification that launched
            // the app from a cold start, and passing nil loses that open entirely.
            OneSignal.initialize(appID, withLaunchOptions: launchOptions)
            // Never `requestPermission` here, and deliberately not OneSignal's
            // subscription-verification dialog either. `NotificationOptIn` is the one ask
            // in this app: a soft prompt first, the system alert only after a yes. iOS
            // shows that alert once per install, so it is not something to spend on a
            // launch-time guess.
        }
        #endif

        // **After** `OneSignal.initialize`. OneSignal may claim
        // `UNUserNotificationCenter.delegate` for itself during init; setting ours first
        // meant it could be replaced, and the streak reminder's foreground presentation
        // would stop working with nothing to show for it. Ours is installed last so it
        // wins, and OneSignal still receives remote notifications through APNs.
        UNUserNotificationCenter.current().delegate = self
    }

    /// Register with APNs, but only once notifications are actually allowed. Registering
    /// unprompted is silent rather than an error, which makes "we never got a token" and
    /// "the user said no" look identical in the logs.
    func registerIfAuthorized() async {
        guard await StreakReminder.authorizationStatus() == .authorized else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - APNs token fan-out

    /// The APNs device token, handed to every provider explicitly.
    ///
    /// This is the method the swizzling would otherwise have done invisibly, and doing it
    /// by hand is the entire reason both SDKs can coexist.
    func didRegister(deviceToken: Data) {
        #if canImport(FirebaseMessaging)
        if FirebaseApp.app() != nil { Messaging.messaging().apnsToken = deviceToken }
        #endif
        #if canImport(OneSignalFramework)
        // OneSignal reads the token through its own swizzle, which is still installed —
        // only Firebase's proxy is disabled. Nothing to forward.
        #endif
        Track.event("push_registered")
    }

    func didFailToRegister(error: Error) {
        Track.event("push_register_failed", ["error": error.localizedDescription])
    }
}

// MARK: - Notification presentation

extension PushService: UNUserNotificationCenterDelegate {
    /// Show notifications that arrive while the app is open.
    ///
    /// Streak reminders are the case that matters: someone reading a vocab list has not
    /// studied yet, so the reminder is still true and still useful. Suppressing
    /// foreground alerts — the default — would hide it exactly when it would land.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.identifier
        // Local reminders and remote pushes land in the same callback and are worth
        // telling apart: one measures whether the reminder works, the other whether a
        // campaign did.
        await MainActor.run {
            Track.event("notification_opened",
                        ["kind": id.hasPrefix(StreakReminder.prefix) ? "streak_reminder" : "push"])
        }
    }
}

// MARK: - FCM token

#if canImport(FirebaseMessaging)
extension PushService: MessagingDelegate {
    /// The FCM registration token.
    ///
    /// **This is a persistent, install-scoped identifier the app itself handles** — a
    /// stronger claim than the Firebase Installation ID that App Check already carries,
    /// because push only functions if something stores it. It is never written into
    /// `Survey` or any other document this app authors; see `CLAUDE.md`'s identifier rule.
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken token: String?) {
        // The token itself is never logged. It identifies one install, and an analytics
        // event is exactly the wrong place for it.
        Task { @MainActor in Track.event("fcm_token", ["present": token != nil]) }
    }
}
#endif
