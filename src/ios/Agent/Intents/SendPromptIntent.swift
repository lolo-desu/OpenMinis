import Foundation
import UIKit
import UserNotifications

/// Helper for posting local notifications from Shortcuts / Scheduled tasks.
/// Tapping the notification opens the associated session.
enum ShortcutNotification {
    /// Category ID for shortcut task notifications — enables tap-to-open-session.
    static let categoryId = "SHORTCUT_TASK"

    static func post(id: String, title: String, body: String, sessionId: String) {
        guard UserDefaults.standard.object(forKey: "backgroundNotificationsEnabled") == nil
                || UserDefaults.standard.bool(forKey: "backgroundNotificationsEnabled") else { return }

        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }

        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: [],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = ["sessionId": sessionId]

        let current = UIApplication.shared.applicationIconBadgeNumber
        content.badge = NSNumber(value: current + 1)
        UIApplication.shared.applicationIconBadgeNumber = current + 1

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}

@MainActor
final class NotificationNavigationStore {
    static let shared = NotificationNavigationStore()

    private var pendingSessionId: String?
    private var pendingSetAt: Date?
    private var handledAt: Date?

    func setPending(_ sessionId: String) {
        pendingSessionId = sessionId
        pendingSetAt = Date()
    }

    func takePending() -> String? {
        defer { pendingSessionId = nil; pendingSetAt = nil }
        guard let sid = pendingSessionId,
              let t = pendingSetAt,
              Date().timeIntervalSince(t) < 30 else { return nil }
        return sid
    }

    func markHandled() {
        pendingSessionId = nil
        pendingSetAt = nil
        handledAt = Date()
    }

    var handledRecently: Bool {
        guard let t = handledAt else { return false }
        return Date().timeIntervalSince(t) < 10
    }
}

final class ShortcutNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ShortcutNotificationDelegate()

    func register() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let sessionId = userInfo["sessionId"] as? String, !sessionId.isEmpty {
            DispatchQueue.main.async {
                NotificationNavigationStore.shared.setPending(sessionId)
                NotificationCenter.default.post(
                    name: .openSessionFromIntent,
                    object: nil,
                    userInfo: ["sessionId": sessionId]
                )
                if let childId = userInfo["childSessionId"] as? String, !childId.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        NotificationCenter.default.post(
                            name: .openHelperSheet, object: nil,
                            userInfo: ["childSessionId": childId, "title": "", "parentSessionId": sessionId])
                    }
                }
            }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
