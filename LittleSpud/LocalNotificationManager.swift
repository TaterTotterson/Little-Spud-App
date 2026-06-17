import Foundation
import UIKit
import UserNotifications

struct NativeNotificationPayload {
    let title: String
    let body: String
    let tag: String
    let url: String?
}

final class LocalNotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = LocalNotificationManager()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
    }

    func configure() {
        center.delegate = self
    }

    func deliver(_ payload: NativeNotificationPayload) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.addNotification(payload)
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted {
                        self.addNotification(payload)
                    }
                }
            case .denied:
                return
            @unknown default:
                return
            }
        }
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { [weak self] settings in
                guard let self else {
                    continuation.resume(returning: false)
                    return
                }
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    continuation.resume(returning: true)
                case .notDetermined:
                    self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                case .denied:
                    continuation.resume(returning: false)
                @unknown default:
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func addNotification(_ payload: NativeNotificationPayload) {
        let content = UNMutableNotificationContent()
        content.title = payload.title.isEmpty ? "Little Spud" : payload.title
        content.body = payload.body
        content.sound = .default

        if let url = payload.url {
            content.userInfo = ["url": url]
        }

        let identifier = payload.tag.isEmpty ? "little-spud-\(UUID().uuidString)" : payload.tag
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .littleSpudNotificationOpened, object: nil)
            completionHandler()
        }
    }
}
