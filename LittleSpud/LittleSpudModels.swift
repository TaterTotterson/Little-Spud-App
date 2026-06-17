import Foundation
import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.02, green: 0.02, blue: 0.025)
    static let panel = Color(red: 0.07, green: 0.07, blue: 0.078)
    static let panelRaised = Color(red: 0.105, green: 0.105, blue: 0.115)
    static let line = Color.white.opacity(0.12)
    static let text = Color(red: 0.97, green: 0.95, blue: 0.91)
    static let muted = Color(red: 0.68, green: 0.63, blue: 0.59)
    static let accent = Color(red: 1.0, green: 0.42, blue: 0.0)
    static let accent2 = Color(red: 1.0, green: 0.61, blue: 0.14)
    static let green = Color(red: 0.35, green: 0.85, blue: 0.6)
    static let danger = Color(red: 0.96, green: 0.43, blue: 0.37)
}

enum LittleSpudRole: String, Codable {
    case user
    case assistant
    case system
}

enum LittleSpudConnectionRoute: String, Codable {
    case home
    case away
    case unknown
}

struct LittleSpudSession: Codable, Equatable {
    var hubUrl: String
    var homeHubUrl: String
    var awayHubUrl: String
    var activeRoute: LittleSpudConnectionRoute
    var token: String
    var userName: String
    var deviceName: String
    var nodeName: String
    var hubName: String
    var hubMode: String
    var toolsEnabled: Bool?
    var pairedAt: Date
    var lastSeenAt: Date

    var displayNodeName: String {
        nodeName.isEmpty ? "\(userName) on \(deviceName)" : nodeName
    }

    var displayRoute: LittleSpudConnectionRoute {
        activeRoute == .unknown ? route(for: hubUrl) : activeRoute
    }

    var isDemo: Bool {
        hubUrl == "demo://little-spud" || token == "little-spud-demo-token"
    }

    func route(for url: String) -> LittleSpudConnectionRoute {
        let clean = url.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
        if !homeHubUrl.isEmpty && clean == homeHubUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines)) {
            return .home
        }
        if !awayHubUrl.isEmpty && clean == awayHubUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines)) {
            return .away
        }
        return .unknown
    }

    init(
        hubUrl: String,
        homeHubUrl: String = "",
        awayHubUrl: String = "",
        activeRoute: LittleSpudConnectionRoute = .unknown,
        token: String,
        userName: String,
        deviceName: String,
        nodeName: String,
        hubName: String,
        hubMode: String,
        toolsEnabled: Bool?,
        pairedAt: Date,
        lastSeenAt: Date
    ) {
        self.hubUrl = hubUrl
        self.homeHubUrl = homeHubUrl
        self.awayHubUrl = awayHubUrl
        self.activeRoute = activeRoute
        self.token = token
        self.userName = userName
        self.deviceName = deviceName
        self.nodeName = nodeName
        self.hubName = hubName
        self.hubMode = hubMode
        self.toolsEnabled = toolsEnabled
        self.pairedAt = pairedAt
        self.lastSeenAt = lastSeenAt
    }

    enum CodingKeys: String, CodingKey {
        case hubUrl
        case homeHubUrl
        case awayHubUrl
        case activeRoute
        case token
        case userName
        case deviceName
        case nodeName
        case hubName
        case hubMode
        case toolsEnabled
        case pairedAt
        case lastSeenAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hubUrl = try container.decode(String.self, forKey: .hubUrl)
        homeHubUrl = try container.decodeIfPresent(String.self, forKey: .homeHubUrl) ?? ""
        awayHubUrl = try container.decodeIfPresent(String.self, forKey: .awayHubUrl) ?? ""
        activeRoute = try container.decodeIfPresent(LittleSpudConnectionRoute.self, forKey: .activeRoute) ?? .unknown
        token = try container.decode(String.self, forKey: .token)
        userName = try container.decode(String.self, forKey: .userName)
        deviceName = try container.decode(String.self, forKey: .deviceName)
        nodeName = try container.decode(String.self, forKey: .nodeName)
        hubName = try container.decode(String.self, forKey: .hubName)
        hubMode = try container.decode(String.self, forKey: .hubMode)
        toolsEnabled = try container.decodeIfPresent(Bool.self, forKey: .toolsEnabled)
        pairedAt = try container.decode(Date.self, forKey: .pairedAt)
        lastSeenAt = try container.decode(Date.self, forKey: .lastSeenAt)

        if homeHubUrl.isEmpty && awayHubUrl.isEmpty {
            homeHubUrl = hubUrl
            activeRoute = .home
        } else if activeRoute == .unknown {
            activeRoute = route(for: hubUrl)
        }
    }
}

struct LittleSpudAttachment: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var type: String
    var size: Int
    var previewUrl: String
    var dataUrl: String

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "attachment" : name
    }
}

struct LittleSpudMessage: Codable, Identifiable, Equatable {
    var id: String
    var role: LittleSpudRole
    var content: String
    var createdAt: Date
    var kind: String?
    var attachments: [LittleSpudAttachment]

    init(
        id: String,
        role: LittleSpudRole,
        content: String,
        createdAt: Date,
        kind: String?,
        attachments: [LittleSpudAttachment] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.kind = kind
        self.attachments = attachments
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt
        case kind
        case attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(LittleSpudRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        attachments = try container.decodeIfPresent([LittleSpudAttachment].self, forKey: .attachments) ?? []
    }

    var label: String {
        switch role {
        case .user:
            return "You"
        case .assistant:
            return kind == "tool_notice" ? "Tater" : "Tater"
        case .system:
            return "Little Spud"
        }
    }
}

struct PairingInput {
    var hubUrl: String
    var homeHubUrl: String
    var awayHubUrl: String
    var pairUrl: String
    var pairUrls: [String]
    var pairingCode: String
}

struct HubHistoryMessage {
    var id: String
    var role: LittleSpudRole
    var content: String
    var createdAt: Date
    var kind: String?
    var attachments: [LittleSpudAttachment] = []
}

struct HubNotification {
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
