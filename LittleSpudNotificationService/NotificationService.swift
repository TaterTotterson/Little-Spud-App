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
        content.badge = nil
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
        let eventID = notificationEventID(from: content.userInfo)
        let notification: LittleSpudShared.ResolvedNotification?
        if eventID.isEmpty {
            notification = await fetchNotification(context: context, eventID: "")
        } else {
            notification = await fetchNotification(context: context, eventID: eventID)
        }
        guard let notification else { return }

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

    private func fetchNotification(context: LittleSpudShared.NotificationContext, eventID: String) async -> LittleSpudShared.ResolvedNotification? {
        for baseURL in context.routeCandidates {
            guard !Task.isCancelled else { return nil }
            guard var components = URLComponents(string: "\(baseURL)/api/spudlink/v1/notifications/next") else { continue }
            var items = [URLQueryItem(name: "wait_seconds", value: "1")]
            let cleanEventID = eventID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanEventID.isEmpty {
                items.append(URLQueryItem(name: "event_id", value: cleanEventID))
            }
            items.append(URLQueryItem(name: "consume", value: "true"))
            components.queryItems = items
            guard let url = components.url else { continue }
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
                if let notification = parseNotification(
                    data,
                    baseURL: baseURL,
                    token: context.token
                ) {
                    return notification
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func notificationEventID(from userInfo: [AnyHashable: Any]) -> String {
        for key in ["event_id", "eventId", "little_spud_event_id", "littleSpudEventId", "notification_id", "notificationId"] {
            if let value = userInfo[key] as? String {
                let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { return clean }
            } else if let value = userInfo[key] {
                let clean = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty && clean != "<null>" { return clean }
            }
        }
        if let littleSpud = userInfo["little_spud"] as? [String: Any] {
            return notificationEventID(from: littleSpud.reduce(into: [AnyHashable: Any]()) { partial, row in
                partial[AnyHashable(row.key)] = row.value
            })
        }
        if let data = userInfo["data"] as? [String: Any] {
            return notificationEventID(from: data.reduce(into: [AnyHashable: Any]()) { partial, row in
                partial[AnyHashable(row.key)] = row.value
            })
        }
        return ""
    }

    private func parseNotification(
        _ data: Data,
        baseURL: String,
        token: String
    ) -> LittleSpudShared.ResolvedNotification? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let payload = object as? [String: Any],
            let notification = payload["notification"] as? [String: Any]
        else { return nil }

        let title = stringValue(notification, "title")
        let message = stringValue(notification, "message", "content")
        guard !title.isEmpty || !message.isEmpty else { return nil }
        let attachments: [LittleSpudShared.ResolvedAttachment] = (
            notification["attachments"] as? [[String: Any]] ?? []
        ).compactMap { item -> LittleSpudShared.ResolvedAttachment? in
            let rawURL = stringValue(item, "previewUrl", "preview_url", "url", "uri")
            let resolvedURL = authenticatedMediaURL(rawURL, baseURL: baseURL, token: token)
            guard !resolvedURL.isEmpty else { return nil }
            let kind = stringValue(item, "type").lowercased()
            let mimetype = stringValue(item, "mimetype", "mime_type")
            let type = mimetype.ifEmpty(
                kind == "image" ? "image/remote" :
                kind == "video" ? "video/remote" :
                kind == "audio" ? "audio/remote" :
                "application/octet-stream"
            )
            return LittleSpudShared.ResolvedAttachment(
                id: stringValue(item, "id", "file_id").ifEmpty(UUID().uuidString),
                name: stringValue(item, "name", "filename").ifEmpty("attachment"),
                type: type,
                size: intValue(item["size"]),
                url: resolvedURL
            )
        }
        return LittleSpudShared.ResolvedNotification(
            id: stringValue(notification, "id").ifEmpty(UUID().uuidString),
            title: title,
            message: message,
            createdAt: dateValue(notification).ifNil(Date()),
            priority: stringValue(notification, "priority").ifEmpty("normal"),
            attachments: attachments
        )
    }

    private func authenticatedMediaURL(_ value: String, baseURL: String, token: String) -> String {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let absolute = raw.hasPrefix("/") ? "\(base)\(raw)" : raw
        guard
            var components = URLComponents(string: absolute),
            let path = components.url?.path,
            path.hasPrefix("/api/spudlink/") || path.contains("/api/spudlink/")
        else {
            return absolute
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "token" }
        queryItems.append(URLQueryItem(name: "token", value: token))
        components.queryItems = queryItems
        return components.url?.absoluteString ?? absolute
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

    private func intValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return max(0, number.intValue) }
        if let value = value as? Int { return max(0, value) }
        if let value = value as? String, let parsed = Int(value) { return max(0, parsed) }
        return 0
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
