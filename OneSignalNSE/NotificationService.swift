import UserNotifications
#if canImport(OneSignalExtension)
import OneSignalExtension
#endif

/// OneSignal's Notification Service Extension.
///
/// A separate process APNs wakes for each incoming remote notification, before it is
/// shown. It is what makes three things work, none of which the main app can do from
/// inside its own process:
///
/// - **Confirmed Delivery** — the difference between "OneSignal sent it" and "the device
///   received it", which is the only number that means anything in a campaign report.
/// - **Rich media** — images and action buttons attached to a notification.
/// - **Badge counts** that are correct rather than approximate.
///
/// Push still works without it. The reporting is what is lost, silently, which is exactly
/// the kind of gap that gets discovered after a campaign rather than before.
///
/// This target deliberately contains **only** this file. An extension has a hard, short
/// wake budget and its own memory limit; pulling app code in here is how one starts
/// getting killed mid-delivery.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?
    /// Kept because the expiry path needs it: `serviceExtensionTimeWillExpireRequest`
    /// takes a non-optional request, and iOS hands the request to `didReceive` only.
    private var request: UNNotificationRequest?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        self.request = request
        bestAttempt = request.content.mutableCopy() as? UNMutableNotificationContent

        guard let bestAttempt else { return contentHandler(request.content) }
        #if canImport(OneSignalExtension)
        OneSignalExtension.didReceiveNotificationExtensionRequest(
            request, with: bestAttempt, withContentHandler: contentHandler)
        #else
        // No SDK linked (an open-source clone): show the notification unchanged rather
        // than dropping it.
        contentHandler(bestAttempt)
        #endif
    }

    /// iOS is about to run out of patience. Hand back whatever has been assembled —
    /// returning nothing here means the notification is shown in its raw form or not
    /// at all.
    override func serviceExtensionTimeWillExpire() {
        guard let contentHandler, let bestAttempt else { return }
        #if canImport(OneSignalExtension)
        if let request {
            OneSignalExtension.serviceExtensionTimeWillExpireRequest(request, with: bestAttempt)
        }
        #endif
        contentHandler(bestAttempt)
    }
}
