import AppKit
import DevDevCore
import UserNotifications

/// Posts the notifications `NotificationRule` decides on, and opens the App on a Command's output
/// when one is clicked. Which notification to send is decided in `DevDevCore`, not here.
final class SystemNotifications: NSObject, NotificationPoster, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private static let commandKey = "commandID"
    private let opener: AppOpener

    init(opener: AppOpener) {
        self.opener = opener
        super.init()
    }

    /// Must run before the application finishes launching, so a click that launched the Helper arrives.
    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // May not call back for a long time and may be refused (docs/spike-results.md item 4).
        // Never wait for it; posting simply shows nothing while permission is missing.
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if !granted {
                let reason = error.map { " (\($0.localizedDescription))" } ?? ""
                FileHandle.standardError.write(Data("DevDev Helper: notifications are not allowed\(reason)\n".utf8))
            }
        }
    }

    func post(_ notification: SystemNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.userInfo = [Self.commandKey: notification.commandID.uuidString]
        if notification.kind == .crashed { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                FileHandle.standardError.write(
                    Data("DevDev Helper: a notification could not be posted: \(error.localizedDescription)\n".utf8))
            }
        }
    }

    // The Helper has no window, so the system would otherwise treat it as in front and hide the banner.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let text = response.notification.request.content.userInfo[Self.commandKey] as? String
        let opener = opener
        await MainActor.run {
            if let text, let id = UUID(uuidString: text) {
                opener.open(.command(id))
            } else {
                opener.openApp()
            }
        }
    }
}
