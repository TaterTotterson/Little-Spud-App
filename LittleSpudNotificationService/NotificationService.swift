import Foundation
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var resolveTask: Task<Void, Never>?
    private let finishLock = NSLock()
    private var didFinish = false

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        guard let content = (request.content.mutableCopy() as? UNMutableNotificationContent) else {
            finish(with: request.content)
            return
        }
        bestAttemptContent = content

        resolveTask = Task { [weak self] in
            await self?.resolveNotification(content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        resolveTask?.cancel()
        resolveTask = nil
        if let bestAttemptContent {
            finish(with: bestAttemptContent)
        }
    }

    private func resolveNotification(_ content: UNMutableNotificationContent) async {
        defer {
            if let bestAttemptContent {
                finish(with: bestAttemptContent)
            }
        }

        guard let context = LittleSpudShared.loadNotificationContext() else { return }
        guard let notification = await fetchNotification(context: context) else { return }

        let cleanTitle = notification.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMessage = notification.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty {
            content.title = cleanTitle
        }
        if !cleanMessage.isEmpty {
            content.body = cleanMessage
        } else if cleanTitle.isEmpty {
            content.body = notification.content
        }
        content.threadIdentifier = "little-spud"
        content.userInfo["little_spud_resolved_notification_id"] = notification.id
        bestAttemptContent = content
        LittleSpudShared.appendResolvedNotification(notification)
    }

    private func finish(with content: UNNotificationContent) {
        finishLock.lock()
        guard !didFinish, let handler = contentHandler else {
            finishLock.unlock()
            return
        }
        didFinish = true
        contentHandler = nil
        finishLock.unlock()
        handler(content)
    }

    private func fetchNotification(context: LittleSpudShared.NotificationContext) async -> LittleSpudShared.ResolvedNotification? {
        for baseURL in context.routeCandidates {
            guard !Task.isCancelled else { return nil }
            guard let url = URL(string: "\(baseURL)/api/spudlink/v1/notifications/next?wait_seconds=1") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 4
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(context.token)", forHTTPHeaderField: "Authorization")
            request.setValue(context.userName, forHTTPHeaderField: "X-SpudLink-User")
            request.setValue(context.deviceName, forHTTPHeaderField: "X-SpudLink-Device")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }
                if let notification = parseNotification(data) {
                    return notification
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func parseNotification(_ data: Data) -> LittleSpudShared.ResolvedNotification? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let payload = object as? [String: Any],
            let notification = payload["notification"] as? [String: Any]
        else { return nil }

        let title = stringValue(notification, "title")
        let message = stringValue(notification, "message", "content")
        guard !title.isEmpty || !message.isEmpty else { return nil }
        return LittleSpudShared.ResolvedNotification(
            id: stringValue(notification, "id").ifEmpty(UUID().uuidString),
            title: title,
            message: message,
            createdAt: dateValue(notification).ifNil(Date()),
            priority: stringValue(notification, "priority").ifEmpty("normal")
        )
    }

    private func stringValue(_ dict: [String: Any], _ keys: String...) -> String {
        for key in keys {
            if let value = dict[key] as? String {
                let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { return clean }
            } else if let value = dict[key] {
                let clean = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty && clean != "<null>" { return clean }
            }
        }
        return ""
    }

    private func dateValue(_ dict: [String: Any]) -> Date? {
        for key in ["createdAt", "created_at", "ts"] {
            if let number = dict[key] as? NSNumber {
                let value = number.doubleValue
                return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
            }
            if let value = dict[key] as? Double {
                return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
            }
            if let value = dict[key] as? String {
                if let double = Double(value) {
                    return Date(timeIntervalSince1970: double > 10_000_000_000 ? double / 1000 : double)
                }
                if let date = ISO8601DateFormatter().date(from: value) {
                    return date
                }
            }
        }
        return nil
    }
}

private extension Optional where Wrapped == Date {
    func ifNil(_ fallback: Date) -> Date {
        self ?? fallback
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
