import Foundation

enum LittleSpudShared {
    static let appGroupIdentifier = "group.com.tatertotterson.littlespud"
    private static let contextFileName = "notification-context.json"
    private static let resolvedFileName = "resolved-notifications.json"

    struct NotificationContext: Codable, Equatable {
        var hubUrl: String
        var homeHubUrl: String
        var awayHubUrl: String
        var token: String
        var userName: String
        var deviceName: String
        var updatedAt: Date

        var routeCandidates: [String] {
            unique([hubUrl, awayHubUrl, homeHubUrl])
        }
    }

    struct ResolvedNotification: Codable, Equatable {
        var id: String
        var title: String
        var message: String
        var createdAt: Date
        var priority: String

        var content: String {
            if !title.isEmpty && !message.isEmpty {
                return "\(title)\n\n\(message)"
            }
            return title.isEmpty ? message : title
        }
    }

    static func saveNotificationContext(_ context: NotificationContext) {
        guard let url = containerFileURL(contextFileName),
              let data = try? JSONEncoder.littleSpud.encode(context)
        else { return }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            print("Little Spud notification context save failed: \(error.localizedDescription)")
        }
    }

    static func loadNotificationContext() -> NotificationContext? {
        guard let url = containerFileURL(contextFileName),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder.littleSpud.decode(NotificationContext.self, from: data)
    }

    static func clearNotificationContext() {
        guard let url = containerFileURL(contextFileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func appendResolvedNotification(_ notification: ResolvedNotification) {
        var current = loadResolvedNotifications()
        guard !current.contains(where: { $0.id == notification.id }) else { return }
        current.append(notification)
        saveResolvedNotifications(Array(current.suffix(40)))
    }

    static func consumeResolvedNotifications() -> [ResolvedNotification] {
        let current = loadResolvedNotifications()
        guard !current.isEmpty, let url = containerFileURL(resolvedFileName) else { return current }
        try? FileManager.default.removeItem(at: url)
        return current
    }

    private static func loadResolvedNotifications() -> [ResolvedNotification] {
        guard let url = containerFileURL(resolvedFileName),
              let data = try? Data(contentsOf: url)
        else { return [] }
        return (try? JSONDecoder.littleSpud.decode([ResolvedNotification].self, from: data)) ?? []
    }

    private static func saveResolvedNotifications(_ notifications: [ResolvedNotification]) {
        guard let url = containerFileURL(resolvedFileName),
              let data = try? JSONEncoder.littleSpud.encode(notifications)
        else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private static func containerFileURL(_ name: String) -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }
        return container.appendingPathComponent(name)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let clean = value.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
            guard !clean.isEmpty, !seen.contains(clean) else { continue }
            seen.insert(clean)
            out.append(clean)
        }
        return out
    }
}

extension JSONEncoder {
    static var littleSpud: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var littleSpud: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
