import Foundation
import UserNotifications

/// Mac notifications for switch advice and for Claude Code's org turning red. Only works
/// from the bundled app (an unbundled binary has no notification identity).
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onClick: (() -> Void)?

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    /// Listens for clicks. Permission is asked for the first time there's something to say,
    /// not at launch, where it would stack on top of the sign-in window.
    func start() {
        center?.delegate = self
    }

    func post(_ title: String, _ body: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted { center.add(request) }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run { onClick?() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}
