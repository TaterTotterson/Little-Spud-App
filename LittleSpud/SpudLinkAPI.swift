import Foundation
import UIKit

enum SpudLinkAPIError: LocalizedError {
    case message(String)
    case httpStatus(action: String, statusCode: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .message(let value):
            return value
        case .httpStatus(let action, _, let detail):
            return "\(action) failed: \(detail)"
        }
    }

    var statusCode: Int? {
        switch self {
        case .message:
            return nil
        case .httpStatus(_, let statusCode, _):
            return statusCode
        }
    }
}

struct SpudLinkChatResponse {
    let content: String
    let reopenMic: Bool
    let attachments: [LittleSpudAttachment]
}

struct SpudLinkToolNotice {
    let id: String
    let text: String
    let runId: String
    let tool: String
    let phase: String
    let createdAt: Date

    init(payload: [String: Any]) {
        let cleanText = dictString(payload, "text", "wait_text")
        let waitPayload = dict(payload["wait_payload"])
        let cleanRunId = dictString(payload, "run_id")
        let cleanTool = dictString(payload, "display_name", "tool").ifEmpty(dictString(waitPayload, "display_name", "tool"))
        let cleanPhase = dictString(payload, "phase").ifEmpty(dictString(waitPayload, "phase")).ifEmpty("tool_start")
        let key = [cleanRunId, cleanTool, cleanPhase, cleanText].joined(separator: "|")
        self.id = "tool-\(key.hashValue)"
        self.text = cleanText
        self.runId = cleanRunId
        self.tool = cleanTool
        self.phase = cleanPhase
        self.createdAt = Self.dateValue(payload, keys: ["createdAt", "created_at"]).ifNil(Date())
    }

    private static func dateValue(_ dict: [String: Any], keys: [String]) -> Date? {
        for key in keys {
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

final class SpudLinkAPI {
    private let clientVersion = "1.0.0"
    private let pushGatewayRegisterURL = "https://push.taterassistant.com/little-spud/register"
    private let pushGatewaySendURL = "https://push.taterassistant.com/little-spud/send"
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func pair(userName: String, deviceName: String, hubUrlInput: String, syncInput: String) async throws -> LittleSpudSession {
        let cleanUser = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDevice = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty else {
            throw SpudLinkAPIError.message("Enter a user name first.")
        }

        let sync = try parsePairingInput(rawInput: syncInput, hubUrlInput: hubUrlInput)
        let deviceInfo = await currentDeviceInfo()
        let body = try jsonData([
            "pairing_code": sync.pairingCode,
            "role": "little_spud",
            "node_name": "\(cleanUser) on \(cleanDevice)",
            "metadata": [
                "client": "little-spud-ios",
                "client_version": clientVersion,
                "user_name": cleanUser,
                "device_name": cleanDevice,
                "user_agent": "LittleSpud iOS \(deviceInfo.systemVersion)"
            ]
        ])

        var payload: [String: Any] = [:]
        var pairedURL = sync.hubUrl
        var lastError: Error?
        for pairUrl in sync.pairUrls {
            do {
                var request = URLRequest(url: try url(pairUrl, label: "Pairing URL"))
                request.httpMethod = "POST"
                request.timeoutInterval = pairUrl == sync.pairUrls.first ? 2.0 : 12.0
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
                payload = try await fetchDictionary(request, actionLabel: "Pairing")
                pairedURL = hubBaseFromAPIURL(pairUrl, endpoint: "/api/spudlink/pair").ifEmpty(sync.hubUrl)
                break
            } catch {
                lastError = error
            }
        }
        if payload.isEmpty, let lastError {
            throw lastError
        }
        let token = dictString(payload, "node_token")
        guard !token.isEmpty else {
            throw SpudLinkAPIError.message("Pairing succeeded but no node token was returned.")
        }

        let node = dict(payload["node"])
        let hub = dict(payload["hub"]) ?? dict(payload["server"])
        let now = Date()

        return LittleSpudSession(
            hubUrl: pairedURL,
            homeHubUrl: sync.homeHubUrl,
            awayHubUrl: sync.awayHubUrl,
            activeRoute: sync.homeHubUrl == pairedURL ? .home : sync.awayHubUrl == pairedURL ? .away : .unknown,
            token: token,
            userName: cleanUser,
            deviceName: cleanDevice,
            nodeName: dictString(node, "name").ifEmpty("\(cleanUser) on \(cleanDevice)"),
            hubName: dictString(hub, "name").ifEmpty(sync.hubUrl),
            hubMode: dictString(hub, "mode"),
            assistantName: dictString(hub, "assistant_name", "tater_name").ifEmpty("Tater"),
            toolsEnabled: dictBool(hub, "tools_enabled"),
            pairedAt: now,
            lastSeenAt: now
        )
    }

    func sendHeartbeat(session: LittleSpudSession, messageCount: Int) async throws -> LittleSpudSession {
        try await sendHeartbeat(session: session, messageCount: messageCount, preferHome: false)
    }

    func sendHeartbeat(session: LittleSpudSession, messageCount: Int, preferHome: Bool) async throws -> LittleSpudSession {
        let deviceInfo = await currentDeviceInfo()
        let body = try jsonData([
            "node_name": session.displayNodeName,
            "mode": "little_spud",
            "version": clientVersion,
            "stats": [
                "platform": "iOS",
                "system_version": deviceInfo.systemVersion,
                "device_model": deviceInfo.model,
                "online": true
            ],
            "activity": [
                "messages": messageCount,
                "attachments_pending": 0
            ]
        ])

        var lastError: Error?
        for candidate in routeCandidates(for: session, preferHome: preferHome) {
            do {
                var candidateSession = session
                candidateSession.hubUrl = candidate.url
                candidateSession.activeRoute = candidate.route
                var request = try authorizedRequest(session: candidateSession, path: "/api/spudlink/heartbeat")
                request.httpMethod = "POST"
                request.timeoutInterval = candidate.route == .home ? 1.4 : 10.0
                request.httpBody = body
                let payload = try await fetchDictionary(request, actionLabel: "Hub ping")
                return updatedSession(from: payload, session: candidateSession)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? SpudLinkAPIError.message("Could not reach Tater.")
    }

    private func updatedSession(from payload: [String: Any], session: LittleSpudSession) -> LittleSpudSession {
        let node = dict(payload["node"])
        let hub = dict(payload["server"]) ?? dict(payload["hub"])

        var updated = session
        updated.nodeName = dictString(node, "name").ifEmpty(updated.nodeName)
        updated.hubName = dictString(hub, "name").ifEmpty(updated.hubName)
        updated.hubMode = dictString(hub, "mode").ifEmpty(updated.hubMode)
        updated.assistantName = dictString(hub, "assistant_name", "tater_name").ifEmpty(updated.assistantName)
        updated.toolsEnabled = dictBool(hub, "tools_enabled") ?? updated.toolsEnabled
        updated.lastSeenAt = Date()
        return updated
    }

    func fetchHistory(session: LittleSpudSession) async throws -> [HubHistoryMessage] {
        try await fetchHistoryState(session: session).messages
    }

    func fetchHistoryState(session: LittleSpudSession) async throws -> HubSyncState {
        let request = try authorizedRequest(session: session, path: "/api/spudlink/v1/history?limit=80")
        let payload = try await fetchDictionary(request, actionLabel: "History sync")
        let items = payload["messages"] as? [[String: Any]] ?? []
        let runs: [[String: Any]]
        if let activeRuns = payload["active_runs"] as? [[String: Any]] {
            runs = activeRuns
        } else if let activeRun = dict(payload["active_run"]) {
            runs = [activeRun]
        } else {
            runs = []
        }
        let hub = dict(payload["server"]) ?? dict(payload["hub"])
        return HubSyncState(
            messages: items.compactMap { normalizeHistoryMessage($0, session: session) },
            activeRuns: runs.compactMap(normalizeActiveRun),
            assistantName: dictString(payload, "assistant_name").ifEmpty(dictString(hub, "assistant_name", "tater_name"))
        )
    }

    func pollNotification(session: LittleSpudSession, waitSeconds: Int = 20) async throws -> HubNotification? {
        let path = "/api/spudlink/v1/notifications/next?wait_seconds=\(max(1, min(waitSeconds, 60)))"
        let request = try authorizedRequest(session: session, path: path)
        let payload = try await fetchDictionary(request, actionLabel: "Notification poll")
        guard let notification = dict(payload["notification"]) else {
            return nil
        }
        return normalizeNotification(notification)
    }

    func forgetPairing(session: LittleSpudSession) async throws {
        if session.isDemo {
            return
        }

        var lastError: Error?
        for candidate in routeCandidates(for: session, preferHome: true) {
            do {
                var candidateSession = session
                candidateSession.hubUrl = candidate.url
                var request = try authorizedRequest(session: candidateSession, path: "/api/spudlink/v1/forget")
                request.httpMethod = "POST"
                request.timeoutInterval = 8
                _ = try await fetchDictionary(request, actionLabel: "Forget pairing")
                return
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
    }

    func registerPushGateway(fcmToken: String, session: LittleSpudSession, environment: String) async throws -> LittleSpudPushRegistration {
        let cleanToken = fcmToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else {
            throw SpudLinkAPIError.message("Firebase push token is missing.")
        }
        let deviceInfo = await currentDeviceInfo()
        var request = URLRequest(url: try url(pushGatewayRegisterURL, label: "Push gateway URL"))
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonData([
            "provider": "fcm",
            "app": "little_spud_ios",
            "platform": "ios",
            "environment": environment,
            "bundle_id": "com.tatertotterson.littlespud.ios",
            "fcm_token": cleanToken,
            "device_name": session.deviceName,
            "node_name": session.displayNodeName,
            "client_version": clientVersion,
            "system_version": deviceInfo.systemVersion,
            "device_model": deviceInfo.model
        ])

        let payload = try await fetchDictionary(request, actionLabel: "Push gateway registration")
        let pushDeviceId = dictString(payload, "push_device_id", "device_id")
        let pushSecret = dictString(payload, "push_secret", "secret")
        guard !pushDeviceId.isEmpty, !pushSecret.isEmpty else {
            throw SpudLinkAPIError.message("Push gateway did not return registration credentials.")
        }
        return LittleSpudPushRegistration(
            provider: dictString(payload, "provider").ifEmpty("fcm"),
            app: dictString(payload, "app").ifEmpty("little_spud_ios"),
            environment: dictString(payload, "environment").ifEmpty(environment),
            pushDeviceId: pushDeviceId,
            pushSecret: pushSecret,
            gatewayUrl: dictString(payload, "gateway_url", "relay_url", "send_url").ifEmpty(pushGatewaySendURL),
            tokenFingerprint: String(cleanToken.suffix(24)),
            registeredAt: Date()
        )
    }

    func updatePushRegistration(session: LittleSpudSession, registration: LittleSpudPushRegistration?, enabled: Bool) async throws -> LittleSpudSession {
        var request = try authorizedRequest(session: session, path: "/api/spudlink/v1/push-registration")
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        var body: [String: Any] = [
            "enabled": enabled
        ]
        if enabled, let registration {
            body.merge([
                "provider": registration.provider,
                "app": registration.app,
                "environment": registration.environment,
                "push_device_id": registration.pushDeviceId,
                "push_secret": registration.pushSecret,
                "gateway_url": registration.gatewayUrl,
                "registered_at": registration.registeredAt.timeIntervalSince1970,
                "metadata": [
                    "client": "little-spud-ios",
                    "client_version": clientVersion
                ]
            ]) { _, new in new }
        }
        request.httpBody = try jsonData(body)
        let payload = try await fetchDictionary(request, actionLabel: "Push registration")
        return updatedSession(from: payload, session: session)
    }

    func fetchSpeech(session: LittleSpudSession, text: String) async throws -> Data {
        var request = try authorizedRequest(session: session, path: "/api/spudlink/v1/tts/speech")
        request.httpMethod = "POST"
        request.httpBody = try jsonData(["text": text])

        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data, actionLabel: "TTS")
        return data
    }

    func sttStreamURL(session: LittleSpudSession, sampleRate: Int, language: String) throws -> URL {
        let httpURL = try url(hubAPIURL(session.hubUrl, "/api/spudlink/v1/stt/stream"), label: "Voice input URL")
        var components = URLComponents(url: httpURL, resolvingAgainstBaseURL: false)
        components?.scheme = httpURL.scheme?.lowercased() == "https" ? "wss" : "ws"
        components?.queryItems = [
            URLQueryItem(name: "token", value: session.token),
            URLQueryItem(name: "rate", value: String(max(8_000, min(48_000, sampleRate)))),
            URLQueryItem(name: "bits", value: "16"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "user", value: session.userName),
            URLQueryItem(name: "device", value: session.deviceName)
        ]
        guard let streamURL = components?.url else {
            throw SpudLinkAPIError.message("Voice input URL is not valid.")
        }
        return streamURL
    }

    func sendChat(
        session: LittleSpudSession,
        messages: [LittleSpudMessage],
        text: String,
        attachments: [LittleSpudAttachment],
        onToolNotice: @escaping (SpudLinkToolNotice) -> Void
    ) async throws -> SpudLinkChatResponse {
        var request = try authorizedRequest(session: session, path: "/api/spudlink/v1/tater/chat")
        request.httpMethod = "POST"

        let history = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .filter { $0.kind != "tool_notice" }
            .suffix(14)
            .map { ["role": $0.role.rawValue, "content": $0.content] }
        let messageContent = buildMessageContent(text: text, attachments: attachments)
        let attachmentMetadata = attachments.map {
            [
                "name": $0.displayName,
                "type": $0.type,
                "mimetype": $0.type,
                "size": $0.size,
                "data_url": $0.dataUrl
            ] as [String: Any]
        }

        request.httpBody = try jsonData([
            "user": session.userName,
            "user_name": session.userName,
            "device_name": session.deviceName,
            "message": messageContent,
            "history": Array(history),
            "attachments": attachmentMetadata,
            "metadata": [
                "client": "little-spud-ios",
                "client_version": clientVersion,
                "transport": "tater_native_event_stream"
            ]
        ])

        let (bytes, response) = try await urlSession.bytes(for: request)
        try validate(response: response, actionLabel: "Chat request")

        var content = ""
        var reopenMic = false
        var attachments: [LittleSpudAttachment] = []
        var seenToolNotices = Set<String>()

        func emitToolNotice(_ payload: [String: Any]) {
            let notice = SpudLinkToolNotice(payload: payload)
            guard !notice.text.isEmpty else { return }
            guard !seenToolNotices.contains(notice.id) else { return }
            seenToolNotices.insert(notice.id)
            onToolNotice(notice)
        }

        func updateContentFromOpenAIStylePayload(_ payload: [String: Any]) {
            guard let choices = payload["choices"] as? [[String: Any]], let first = choices.first else { return }
            if let delta = first["delta"] as? [String: Any] {
                let deltaContent = dictString(delta, "content")
                if !deltaContent.isEmpty {
                    content += deltaContent
                }
            }
            if let message = first["message"] as? [String: Any] {
                let messageContent = dictString(message, "content")
                if !messageContent.isEmpty {
                    content = messageContent
                }
            }
        }

        func handleBlock(_ block: String) throws -> Bool {
            var event = "message"
            var dataLines: [String] = []

            for rawLine in block.components(separatedBy: .newlines) {
                guard !rawLine.isEmpty, !rawLine.hasPrefix(":") else { continue }
                let parts = rawLine.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                let field = String(parts.first ?? "")
                var value = parts.count > 1 ? String(parts[1]) : ""
                if value.hasPrefix(" ") {
                    value.removeFirst()
                }
                if field == "event" {
                    event = value.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("message")
                } else if field == "data" {
                    dataLines.append(value)
                }
            }

            guard !dataLines.isEmpty else { return false }
            let data = dataLines.joined(separator: "\n")
            if data.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                return true
            }
            guard let payload = try? jsonDictionary(from: Data(data.utf8)) else {
                return false
            }
            switch event {
            case "tater.tool":
                emitToolNotice(payload)
            case "tater.message":
                if let notices = payload["tool_notices"] as? [[String: Any]] {
                    notices.forEach(emitToolNotice)
                }
                content = dictString(payload, "content")
                if let artifacts = payload["artifacts"] as? [[String: Any]] {
                    attachments.append(contentsOf: normalizeAssistantArtifacts(artifacts, session: session))
                }
            case "tater.artifacts":
                let artifacts = payload["artifacts"] as? [[String: Any]] ?? []
                attachments.append(contentsOf: normalizeAssistantArtifacts(artifacts, session: session))
            case "tater.follow_up":
                let followUp = dict(payload["follow_up"])
                reopenMic = dictBool(followUp, "enabled") == true && dictBool(followUp, "reopen_mic") == true
            case "tater.error":
                throw SpudLinkAPIError.message(payloadErrorMessage(payload, fallback: "Tater request failed."))
            case "tater.done":
                return true
            case "message":
                updateContentFromOpenAIStylePayload(payload)
            default:
                break
            }
            return false
        }

        let lfDelimiter = Data([10, 10])
        let crlfDelimiter = Data([13, 10, 13, 10])

        func delimiterRange(in data: Data) -> Range<Data.Index>? {
            let lfRange = data.range(of: lfDelimiter)
            let crlfRange = data.range(of: crlfDelimiter)
            if let lfRange, let crlfRange {
                return lfRange.lowerBound < crlfRange.lowerBound ? lfRange : crlfRange
            }
            return crlfRange ?? lfRange
        }

        var buffer = Data()
        for try await byte in bytes {
            buffer.append(byte)
            while let range = delimiterRange(in: buffer) {
                let blockData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                let block = String(decoding: blockData, as: UTF8.self)
                if try handleBlock(block) {
                    return SpudLinkChatResponse(content: content, reopenMic: reopenMic, attachments: dedupeAttachments(attachments))
                }
            }
        }

        if !buffer.isEmpty {
            let block = String(decoding: buffer, as: UTF8.self)
            _ = try handleBlock(block)
        }
        return SpudLinkChatResponse(content: content, reopenMic: reopenMic, attachments: dedupeAttachments(attachments))
    }

    private func buildMessageContent(text: String, attachments: [LittleSpudAttachment]) -> [[String: Any]] {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptText = cleanText.isEmpty ? "Please review the attached media." : cleanText
        return [
            ["type": "text", "text": "\(promptText)\(attachmentSummary(attachments))"]
        ]
    }

    private func attachmentSummary(_ attachments: [LittleSpudAttachment]) -> String {
        guard !attachments.isEmpty else { return "" }
        let lines = attachments.enumerated().map { index, item in
            "\(index + 1). \(item.displayName) (\(item.type), \(formatBytes(item.size)))"
        }
        return "\n\nAttached media:\n\(lines.joined(separator: "\n"))"
    }

    private func formatBytes(_ size: Int) -> String {
        guard size >= 1024 else { return "\(size) B" }
        let kb = Double(size) / 1024
        guard kb >= 1024 else { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    func parsePairingInput(rawInput: String, hubUrlInput: String) throws -> PairingInput {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackHubUrl = normalizeURL(hubUrlInput)
        guard !input.isEmpty else {
            throw SpudLinkAPIError.message("Enter a sync code or scan a QR payload.")
        }

        if input.hasPrefix("tater-spudlink://") {
            guard
                let components = URLComponents(string: input),
                let dataValue = components.queryItems?.first(where: { $0.name == "data" })?.value,
                let data = decodeBase64URL(dataValue),
                let payload = try? jsonDictionary(from: data)
            else {
                throw SpudLinkAPIError.message("QR payload is missing pairing data.")
            }
            return try pairingInput(from: payload, fallbackHubUrl: fallbackHubUrl)
        }

        if input.hasPrefix("{") || input.hasPrefix("[") {
            guard let payload = try? jsonDictionary(from: Data(input.utf8)) else {
                throw SpudLinkAPIError.message("Pairing payload is not valid JSON.")
            }
            return try pairingInput(from: payload, fallbackHubUrl: fallbackHubUrl)
        }

        guard !fallbackHubUrl.isEmpty else {
            throw SpudLinkAPIError.message("Enter the Tater URL when using a manual pairing code.")
        }
        return PairingInput(
            hubUrl: fallbackHubUrl,
            homeHubUrl: fallbackHubUrl,
            awayHubUrl: "",
            pairUrl: hubAPIURL(fallbackHubUrl, "/api/spudlink/pair"),
            pairUrls: [hubAPIURL(fallbackHubUrl, "/api/spudlink/pair")],
            pairingCode: input
        )
    }

    private func pairingInput(from payload: [String: Any], fallbackHubUrl: String) throws -> PairingInput {
        let routes = dict(payload["route_urls"])
        let homeHubUrl = normalizeURL(
            dictString(routes, "home", "local")
                .ifEmpty(dictString(payload, "home_url", "local_url", "lan_url"))
                .ifEmpty(fallbackHubUrl)
        )
        let awayHubUrl = normalizeURL(
            dictString(routes, "away", "remote")
                .ifEmpty(dictString(payload, "away_url", "remote_url", "public_url"))
        )
        let payloadHubUrl = normalizeURL(dictString(payload, "hub_url", "server_url").ifEmpty(homeHubUrl).ifEmpty(awayHubUrl).ifEmpty(fallbackHubUrl))
        let payloadPairUrl = normalizeURL(dictString(payload, "pair_url"))
        let pairBaseUrl = hubBaseFromAPIURL(payloadPairUrl, endpoint: "/api/spudlink/pair")
        let hubUrl = pairBaseUrl.ifEmpty(payloadHubUrl).ifEmpty(homeHubUrl).ifEmpty(awayHubUrl)
        let pairUrl = payloadPairUrl.ifEmpty(hubUrl.isEmpty ? "" : hubAPIURL(hubUrl, "/api/spudlink/pair"))
        let pairingCode = dictString(payload, "pairing_code", "code")
        guard !pairingCode.isEmpty else {
            throw SpudLinkAPIError.message("Pairing payload is missing a code.")
        }
        guard !hubUrl.isEmpty || !pairUrl.isEmpty else {
            throw SpudLinkAPIError.message("Pairing payload is missing a Tater URL.")
        }
        let pairUrls = uniqueStrings([
            homeHubUrl.isEmpty ? "" : hubAPIURL(homeHubUrl, "/api/spudlink/pair"),
            awayHubUrl.isEmpty ? "" : hubAPIURL(awayHubUrl, "/api/spudlink/pair"),
            pairUrl
        ])
        return PairingInput(
            hubUrl: hubUrl.ifEmpty(hubBaseFromAPIURL(pairUrl, endpoint: "/api/spudlink/pair")),
            homeHubUrl: homeHubUrl,
            awayHubUrl: awayHubUrl,
            pairUrl: pairUrl,
            pairUrls: pairUrls,
            pairingCode: pairingCode
        )
    }

    private func routeCandidates(for session: LittleSpudSession, preferHome: Bool) -> [(url: String, route: LittleSpudConnectionRoute)] {
        var candidates: [(String, LittleSpudConnectionRoute)] = []
        if preferHome {
            candidates.append((session.homeHubUrl, .home))
            candidates.append((session.awayHubUrl, .away))
            candidates.append((session.hubUrl, session.route(for: session.hubUrl)))
        } else {
            candidates.append((session.hubUrl, session.route(for: session.hubUrl)))
            if session.activeRoute != .home {
                candidates.append((session.homeHubUrl, .home))
            }
            if session.activeRoute != .away {
                candidates.append((session.awayHubUrl, .away))
            }
        }
        return uniqueRouteCandidates(candidates)
    }

    private func uniqueRouteCandidates(_ candidates: [(String, LittleSpudConnectionRoute)]) -> [(url: String, route: LittleSpudConnectionRoute)] {
        var seen = Set<String>()
        var out: [(String, LittleSpudConnectionRoute)] = []
        for (value, route) in candidates {
            let clean = normalizeURL(value)
            guard !clean.isEmpty, !seen.contains(clean) else { continue }
            seen.insert(clean)
            out.append((clean, route == .unknown ? (clean == normalizeURL(value) ? route : .unknown) : route))
        }
        return out
    }

    private func authorizedRequest(session: LittleSpudSession, path: String) throws -> URLRequest {
        var request = URLRequest(url: try url(hubAPIURL(session.hubUrl, path), label: "Tater URL"))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        request.setValue(session.userName, forHTTPHeaderField: "X-SpudLink-User")
        request.setValue(session.deviceName, forHTTPHeaderField: "X-SpudLink-Device")
        return request
    }

    private func fetchDictionary(_ request: URLRequest, actionLabel: String) async throws -> [String: Any] {
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data, actionLabel: actionLabel)
        let payload = try jsonDictionary(from: data)
        if dictBool(payload, "ok") == false || payload["error"] != nil {
            throw SpudLinkAPIError.message("\(actionLabel) failed: \(payloadErrorMessage(payload, fallback: "Unknown error"))")
        }
        return payload
    }

    private func validate(response: URLResponse, data: Data = Data(), actionLabel: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let payload = (try? jsonDictionary(from: data)) ?? [:]
            let detail = payloadErrorMessage(payload, fallback: HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
            throw SpudLinkAPIError.httpStatus(action: actionLabel, statusCode: http.statusCode, detail: detail)
        }
    }

    private func normalizeHistoryMessage(_ item: [String: Any], session: LittleSpudSession) -> HubHistoryMessage? {
        let roleValue = dictString(item, "role")
        guard let role = LittleSpudRole(rawValue: roleValue) else { return nil }
        let rawAttachments = (item["attachments"] as? [[String: Any]]) ?? (item["artifacts"] as? [[String: Any]]) ?? []
        let attachments = normalizeAssistantArtifacts(rawAttachments, session: session)
        let content = normalizeHistoryContent(dictString(item, "content"), role: role, attachments: attachments)
        guard !content.isEmpty || !attachments.isEmpty else { return nil }
        return HubHistoryMessage(
            id: dictString(item, "id").ifEmpty(UUID().uuidString),
            role: role,
            content: content,
            createdAt: dateValue(item, keys: ["createdAt", "created_at", "ts"]).ifNil(Date()),
            kind: dictString(dict(item["meta"]), "kind"),
            attachments: attachments
        )
    }

    private func normalizeHistoryContent(
        _ value: String,
        role: LittleSpudRole,
        attachments: [LittleSpudAttachment]
    ) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard role == .user, !attachments.isEmpty else { return text }

        if let range = text.range(of: "\n\nAttached media:", options: [.caseInsensitive]) {
            text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let range = text.range(of: "\nAttached media:", options: [.caseInsensitive]) {
            text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let promptOnly = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if promptOnly.caseInsensitiveCompare("Please review the attached media") == .orderedSame || text.isEmpty {
            let imageCount = attachments.filter { $0.type.lowercased().hasPrefix("image/") }.count
            if imageCount == attachments.count {
                return attachments.count == 1 ? "Attached image" : "Attached images"
            }
            return "Attached media"
        }

        return text
    }

    private func normalizeActiveRun(_ item: [String: Any]) -> HubActiveRun? {
        let id = dictString(item, "run_id", "id")
        guard !id.isEmpty else { return nil }
        return HubActiveRun(
            id: id,
            status: dictString(item, "status").ifEmpty("running"),
            phase: dictString(item, "phase").ifEmpty("thinking"),
            text: dictString(item, "text", "wait_text").ifEmpty("Tater is thinking"),
            startedAt: dateValue(item, keys: ["started_at", "startedAt", "created_at", "createdAt"]).ifNil(Date()),
            updatedAt: dateValue(item, keys: ["updated_at", "updatedAt", "started_at", "startedAt"]).ifNil(Date())
        )
    }

    private func normalizeNotification(_ item: [String: Any]) -> HubNotification? {
        let title = dictString(item, "title")
        let message = dictString(item, "message", "content")
        guard !title.isEmpty || !message.isEmpty else { return nil }
        return HubNotification(
            id: dictString(item, "id").ifEmpty(UUID().uuidString),
            title: title,
            message: message,
            createdAt: dateValue(item, keys: ["createdAt", "created_at", "ts"]).ifNil(Date()),
            priority: dictString(item, "priority").ifEmpty(dictString(dict(item["meta"]), "priority").ifEmpty("normal"))
        )
    }

    private func normalizeAssistantArtifacts(_ artifacts: [[String: Any]], session: LittleSpudSession) -> [LittleSpudAttachment] {
        artifacts.compactMap { item in
            let mimetype = dictString(item, "mimetype", "mime_type")
            let kind = dictString(item, "type").lowercased()
            let type = mimetype.ifEmpty(
                kind == "image" ? "image/remote" :
                kind == "video" ? "video/remote" :
                kind == "audio" ? "audio/remote" :
                "application/octet-stream"
            )
            let rawURL = dictString(item, "previewUrl", "preview_url", "url", "uri")
            let previewURL = spudLinkMediaURL(rawURL, session: session)
            let dataURL = dictString(item, "dataUrl", "data_url")
            let name = dictString(item, "name", "filename").ifEmpty("attachment")
            guard !previewURL.isEmpty || !dataURL.isEmpty || !name.isEmpty else { return nil }
            return LittleSpudAttachment(
                id: dictString(item, "id", "file_id").ifEmpty(UUID().uuidString),
                name: name,
                type: type,
                size: intValue(item["size"]),
                previewUrl: previewURL,
                dataUrl: dataURL
            )
        }
    }

    private func dedupeAttachments(_ attachments: [LittleSpudAttachment]) -> [LittleSpudAttachment] {
        var seen = Set<String>()
        var result: [LittleSpudAttachment] = []
        for item in attachments {
            let key = [item.id, item.previewUrl, item.dataUrl, item.name, item.type].joined(separator: "|")
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(item)
        }
        return result
    }

    private func spudLinkMediaURL(_ value: String, session: LittleSpudSession) -> String {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        let absolute = raw.hasPrefix("/") ? hubAPIURL(session.hubUrl, raw) : raw
        guard
            var components = URLComponents(string: absolute),
            let path = components.url?.path,
            path.hasPrefix("/api/spudlink/")
        else {
            return absolute
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "token" }
        queryItems.append(URLQueryItem(name: "token", value: session.token))
        components.queryItems = queryItems
        return components.url?.absoluteString ?? absolute
    }

    private func hubAPIURL(_ hubUrl: String, _ path: String) -> String {
        let base = normalizeURL(hubUrl).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanPath = path.hasPrefix("/") ? path : "/\(path)"
        return "\(base)\(cleanPath)"
    }

    private func hubBaseFromAPIURL(_ apiUrl: String, endpoint: String) -> String {
        let normalized = normalizeURL(apiUrl)
        guard !normalized.isEmpty else { return "" }
        if let range = normalized.range(of: endpoint) {
            return String(normalized[..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return ""
    }

    private func normalizeURL(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("//") {
            trimmed = "http:\(trimmed)"
        } else if !trimmed.contains("://") {
            trimmed = "http://\(trimmed)"
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    private func url(_ value: String, label: String) throws -> URL {
        guard let url = URL(string: value), let scheme = url.scheme, !scheme.isEmpty else {
            throw SpudLinkAPIError.message("\(label) is not a valid URL.")
        }
        return url
    }

    private func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    private func jsonData(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [])
    }

    private func jsonDictionary(from data: Data) throws -> [String: Any] {
        guard !data.isEmpty else { return [:] }
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        if let dict = object as? [String: Any] {
            return dict
        }
        return [:]
    }

    private func payloadErrorMessage(_ payload: [String: Any], fallback: String) -> String {
        if let detail = payload["detail"] as? String, !detail.isEmpty {
            return detail
        }
        if let error = payload["error"] as? [String: Any] {
            return dictString(error, "message").ifEmpty(fallback)
        }
        if let error = payload["error"] as? String, !error.isEmpty {
            return error
        }
        return fallback
    }

    private func dateValue(_ dict: [String: Any], keys: [String]) -> Date? {
        for key in keys {
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

    private func currentDeviceInfo() async -> (systemVersion: String, model: String) {
        await MainActor.run {
            (UIDevice.current.systemVersion, UIDevice.current.model)
        }
    }
}

private func dict(_ value: Any?) -> [String: Any]? {
    value as? [String: Any]
}

private func dictString(_ dict: [String: Any]?, _ keys: String...) -> String {
    guard let dict else { return "" }
    for key in keys {
        if let value = dict[key] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        } else if let value = dict[key] {
            let string = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            if !string.isEmpty && string != "<null>" { return string }
        }
    }
    return ""
}

private func dictBool(_ dict: [String: Any]?, _ key: String) -> Bool? {
    guard let value = dict?[key] else { return nil }
    if let bool = value as? Bool { return bool }
    if let number = value as? NSNumber { return number.boolValue }
    if let string = value as? String {
        let lower = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["true", "1", "yes"].contains(lower) { return true }
        if ["false", "0", "no"].contains(lower) { return false }
    }
    return nil
}

private func uniqueStrings(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for value in values {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !seen.contains(clean) else { continue }
        seen.insert(clean)
        out.append(clean)
    }
    return out
}

private func intValue(_ value: Any?) -> Int {
    if let int = value as? Int { return int }
    if let number = value as? NSNumber { return number.intValue }
    if let string = value as? String, let int = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return int
    }
    return 0
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

private extension Optional where Wrapped == Date {
    func ifNil(_ fallback: Date) -> Date {
        self ?? fallback
    }
}
