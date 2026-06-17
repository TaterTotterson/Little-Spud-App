import AVFoundation
import Foundation
import SwiftUI
import UIKit

@MainActor
final class LittleSpudViewModel: ObservableObject {
    @Published var userName = ""
    @Published var deviceName = UIDevice.current.name
    @Published var hubUrl = ""
    @Published var syncCode = ""
    @Published var session: LittleSpudSession?
    @Published var messages: [LittleSpudMessage] = []
    @Published var draft = ""
    @Published var statusText = ""
    @Published var statusKind = ""
    @Published var isPairing = false
    @Published var isSending = false
    @Published var isTyping = false
    @Published var notificationsEnabled = false
    @Published var showScanner = false
    @Published var completedMessageId: String?
    @Published var ttsEnabled = false
    @Published var ttsStatus = ""
    @Published var isVoiceRecording = false
    @Published var isVoiceSubmitting = false
    @Published var speechStatus = ""
    @Published var hubConnected = false
    @Published var pendingAttachments: [LittleSpudAttachment] = []

    var connectionRoute: LittleSpudConnectionRoute {
        session?.displayRoute ?? .unknown
    }

    var isDemoMode: Bool {
        session?.isDemo == true
    }

    var connectionStatusText: String {
        if isDemoMode {
            return "Demo Mode"
        }
        guard hubConnected else { return "Not Connected" }
        switch connectionRoute {
        case .home:
            return "Connected Home"
        case .away:
            return "Connected Away"
        case .unknown:
            return "Connected"
        }
    }

    var canSend: Bool {
        session != nil && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
    }

    var canUseVoiceInput: Bool {
        session != nil
    }

    var connectedTitle: String {
        guard let session else { return "Offline" }
        return session.displayNodeName
    }

    var connectedSubtitle: String {
        guard let session else { return "Not paired" }
        let toolLabel: String
        if session.toolsEnabled == true {
            toolLabel = "Hydra tools"
        } else if session.toolsEnabled == false {
            toolLabel = "LLM only"
        } else {
            toolLabel = "Ready"
        }
        return [session.hubName, session.hubMode, toolLabel]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " / ")
    }

    private let api = SpudLinkAPI()
    private let sessionAccount = "little-spud-session"
    private let messagesKey = "little-spud-ios:messages:v1"
    private let notificationsKey = "little-spud-ios:notifications"
    private let ttsKey = "little-spud-ios:tts-enabled"
    private let demoHubUrl = "demo://little-spud"
    private let demoToken = "little-spud-demo-token"
    private var didStart = false
    private var pollTask: Task<Void, Never>?
    private var routeProbeTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var speechWebSocket: URLSessionWebSocketTask?
    private var audioEngine: AVAudioEngine?
    private var voiceTapInstalled = false
    private var pendingReopenTask: Task<Void, Never>?
    private var demoVoiceTask: Task<Void, Never>?
    private var activeChatRunCount = 0

    func start() {
        guard !didStart else { return }
        didStart = true
        notificationsEnabled = UserDefaults.standard.bool(forKey: notificationsKey)
        ttsEnabled = UserDefaults.standard.bool(forKey: ttsKey)
        ttsStatus = ttsEnabled ? "TTS on" : ""
        loadSession()
        loadMessages()
        if session == nil {
            hubConnected = false
            if userName.isEmpty {
                userName = UserDefaults.standard.string(forKey: "little-spud-ios:user-name") ?? ""
            }
            if deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                deviceName = UIDevice.current.name
            }
            statusText = "Pair Little Spud with Tater."
        } else {
            resume()
        }
    }

    func resume() {
        guard session != nil else { return }
        if isDemoMode {
            hubConnected = true
            return
        }
        startNotificationPoll()
        startRouteProbe()
        Task { [weak self] in
            await self?.refreshFromHub(showStatus: false)
        }
    }

    func pauseForegroundWork() {
        pollTask?.cancel()
        pollTask = nil
        routeProbeTask?.cancel()
        routeProbeTask = nil
        demoVoiceTask?.cancel()
        demoVoiceTask = nil
        cancelVoiceInput()
    }

    func pair() {
        guard !isPairing else { return }
        isPairing = true
        statusText = "Pairing with Tater..."
        statusKind = ""

        Task { [weak self] in
            guard let self else { return }
            defer { self.isPairing = false }
            do {
                let paired = try await api.pair(
                    userName: userName,
                    deviceName: deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Little Spud" : deviceName,
                    hubUrlInput: hubUrl,
                    syncInput: syncCode
                )
                session = paired
                hubConnected = true
                userName = paired.userName
                deviceName = paired.deviceName
                hubUrl = paired.hubUrl
                syncCode = ""
                statusText = "Connected. Little Spud is ready."
                statusKind = "ok"
                saveSession()
                UserDefaults.standard.set(userName, forKey: "little-spud-ios:user-name")
                await refreshFromHub(showStatus: false)
                startNotificationPoll()
                startRouteProbe()
            } catch {
                hubConnected = false
                statusText = error.localizedDescription
                statusKind = "error"
            }
        }
    }

    func applyScannedCode(_ value: String) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            statusText = "QR scan did not return a pairing payload."
            statusKind = "error"
            return
        }
        syncCode = clean
        statusText = "QR scanned. Connecting..."
        statusKind = ""
        pair()
    }

    func startDemoMode() {
        let typedUser = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let typedDevice = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = typedUser.isEmpty ? "Little Spud User" : typedUser
        let cleanDevice = typedDevice.isEmpty ? "Preview iPhone" : typedDevice
        let now = Date()
        pauseForegroundWork()
        session = LittleSpudSession(
            hubUrl: demoHubUrl,
            homeHubUrl: demoHubUrl,
            awayHubUrl: "",
            activeRoute: .home,
            token: demoToken,
            userName: cleanUser,
            deviceName: cleanDevice,
            nodeName: "\(cleanUser) on \(cleanDevice)",
            hubName: "Tater Preview",
            hubMode: "Local Preview",
            toolsEnabled: true,
            pairedAt: now,
            lastSeenAt: now
        )
        userName = cleanUser
        deviceName = cleanDevice
        hubUrl = demoHubUrl
        syncCode = ""
        hubConnected = true
        statusText = "Little Spud preview is ready."
        statusKind = "ok"
        messages = [
            LittleSpudMessage(
                id: "demo-welcome",
                role: .assistant,
                content: "Little Spud preview is ready. Ask for a sample image, a notification, or a quick Tater reply. Set up your own Tater at https://taterassistant.com.",
                createdAt: now,
                kind: nil
            )
        ]
        saveSession()
        saveMessages()
        UserDefaults.standard.set(userName, forKey: "little-spud-ios:user-name")
    }

    func addImageAttachment(_ image: UIImage, suggestedName: String = "") {
        guard pendingAttachments.count < 4 else {
            speechStatus = "Remove an image before attaching another."
            return
        }
        guard let attachment = makeImageAttachment(from: image, suggestedName: suggestedName) else {
            speechStatus = "Image could not be attached."
            return
        }
        pendingAttachments.append(attachment)
        speechStatus = "Image attached."
    }

    func removePendingAttachment(id: String) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func sendMessage(fromVoice: Bool = false) {
        guard let currentSession = session, canSend else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let outgoingAttachments = pendingAttachments
        let priorMessages = messages
        let assistantId = UUID().uuidString
        let userContent = text.isEmpty ? (outgoingAttachments.count == 1 ? "Attached image" : "Attached images") : text
        let userMessage = LittleSpudMessage(
            id: UUID().uuidString,
            role: .user,
            content: userContent,
            createdAt: Date(),
            kind: nil,
            attachments: outgoingAttachments
        )
        messages.append(userMessage)
        messages.append(LittleSpudMessage(
            id: assistantId,
            role: .assistant,
            content: "Tater is thinking",
            createdAt: Date(),
            kind: "pending"
        ))
        draft = ""
        pendingAttachments = []
        beginChatRun()
        saveMessages()

        if currentSession.isDemo {
            Task { [weak self] in
                guard let self else { return }
                defer {
                    self.finishChatRun()
                    self.saveMessages()
                }
                await self.sendDemoResponse(for: text, attachments: outgoingAttachments, assistantId: assistantId, fromVoice: fromVoice)
            }
            return
        }

        Task { [weak self] in
            guard let self else { return }
            defer {
                self.finishChatRun()
                self.saveMessages()
            }
            do {
                let chatSession = try await api.sendHeartbeat(session: currentSession, messageCount: messages.count, preferHome: true)
                session = chatSession
                hubUrl = chatSession.hubUrl
                hubConnected = true
                saveSession()

                let response = try await api.sendChat(session: chatSession, messages: priorMessages, text: text, attachments: outgoingAttachments) { notice in
                    Task { @MainActor [weak self] in
                        self?.appendToolNotice(notice, beforeAssistantId: assistantId)
                    }
                }
                let reply = response.content
                guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !response.attachments.isEmpty else {
                    throw SpudLinkAPIError.message("Tater returned no message content.")
                }
                if let messageIndex = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[messageIndex].content = ""
                    messages[messageIndex].kind = nil
                    messages[messageIndex].attachments = response.attachments
                }
                let ttsTask = await beginSpeechPlayback(reply, waitForStart: true)
                await revealAssistantMessage(id: assistantId, text: reply)
                await refreshFromHub(showStatus: false)
                if fromVoice && response.reopenMic {
                    if let ttsTask {
                        await ttsTask.value
                    }
                    reopenMicAfterReply()
                }
            } catch {
                let errorMessage = "Request failed: \(error.localizedDescription)"
                if let messageIndex = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[messageIndex] = LittleSpudMessage(
                        id: assistantId,
                        role: .system,
                        content: errorMessage,
                        createdAt: Date(),
                        kind: "error"
                    )
                } else {
                    messages.append(LittleSpudMessage(
                        id: assistantId,
                        role: .system,
                        content: errorMessage,
                        createdAt: Date(),
                        kind: "error"
                    ))
                }
            }
        }
    }

    private func sendDemoResponse(for text: String, attachments: [LittleSpudAttachment], assistantId: String, fromVoice: Bool) async {
        hubConnected = true
        try? await Task.sleep(nanoseconds: 520_000_000)
        appendToolNotice(
            SpudLinkToolNotice(payload: [
                "run_id": "demo-\(assistantId)",
                "display_name": "Demo Tater",
                "phase": "tool_start",
                "text": demoToolText(for: text, attachments: attachments),
                "created_at": Date().timeIntervalSince1970
            ]),
            beforeAssistantId: assistantId
        )
        try? await Task.sleep(nanoseconds: 620_000_000)

        let response = demoChatResponse(for: text, attachments: attachments)
        if let messageIndex = messages.firstIndex(where: { $0.id == assistantId }) {
            messages[messageIndex].content = ""
            messages[messageIndex].kind = nil
            messages[messageIndex].attachments = response.attachments
        }
        let ttsTask = await beginSpeechPlayback(response.content, waitForStart: true)
        await revealAssistantMessage(id: assistantId, text: response.content)

        if text.localizedCaseInsensitiveContains("notification") {
            appendHubNotification(HubNotification(
                id: "demo-notification-\(UUID().uuidString)",
                title: "Little Spud Preview",
                message: "This is a local preview notification. Set up your own Tater at taterassistant.com.",
                createdAt: Date(),
                priority: "normal"
            ))
        }

        if fromVoice, let ttsTask {
            await ttsTask.value
        }
    }

    private func demoToolText(for text: String, attachments: [LittleSpudAttachment]) -> String {
        if !attachments.isEmpty {
            return "Looking over the attached image..."
        }
        let lower = text.lowercased()
        if lower.contains("image") || lower.contains("photo") || lower.contains("media") {
            return "Drawing a small demo image for you..."
        }
        if lower.contains("notification") {
            return "Queuing a local Little Spud notification..."
        }
        return "Checking the demo Tater shelf..."
    }

    private func demoChatResponse(for text: String, attachments inputAttachments: [LittleSpudAttachment]) -> SpudLinkChatResponse {
        let lower = text.lowercased()
        var content = "Tater preview is awake. This local preview shows how Little Spud feels before you pair it with your own Tater. Set up Tater at https://taterassistant.com."
        var attachments: [LittleSpudAttachment] = []

        if !inputAttachments.isEmpty {
            content = "I received the attached image. Once paired with your own Tater, Hydra can pass it to vision tools when you ask about it."
        } else if lower.contains("image") || lower.contains("photo") || lower.contains("media") || lower.contains("show") {
            content = "Here is a local sample image attachment. Once you pair Little Spud, images, audio, and video can come from your own Tater. Setup info is at https://taterassistant.com."
            attachments.append(LittleSpudAttachment(
                id: "demo-image-\(UUID().uuidString)",
                name: "little-spud-demo.png",
                type: "image/png",
                size: 0,
                previewUrl: "",
                dataUrl: demoImageDataURL()
            ))
        } else if lower.contains("notification") {
            content = "I queued a local preview notification. With your own Tater, Little Spud pulls notifications from your private Tater queue when the app is awake or resumes."
        } else if lower.contains("voice") || lower.contains("mic") {
            content = "Voice mode connects to your paired Tater speech endpoint. This preview keeps everything local until you set up your own Tater at https://taterassistant.com."
        }

        return SpudLinkChatResponse(content: content, reopenMic: false, attachments: attachments)
    }

    private func makeImageAttachment(from image: UIImage, suggestedName: String) -> LittleSpudAttachment? {
        let normalized = resizedImage(image, maxDimension: 1600)
        guard let data = normalized.jpegData(compressionQuality: 0.78), !data.isEmpty else { return nil }
        let cleanName = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleanName.isEmpty ? "little-spud-photo-\(Int(Date().timeIntervalSince1970)).jpg" : cleanName
        let dataUrl = "data:image/jpeg;base64,\(data.base64EncodedString())"
        return LittleSpudAttachment(
            id: UUID().uuidString,
            name: name,
            type: "image/jpeg",
            size: data.count,
            previewUrl: "",
            dataUrl: dataUrl
        )
    }

    private func resizedImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largest = max(size.width, size.height)
        guard largest > maxDimension, largest > 0 else {
            return normalizedImage(image)
        }
        let scale = maxDimension / largest
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private func demoImageDataURL() -> String {
        let size = CGSize(width: 560, height: 320)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let data = renderer.pngData { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 0.055, green: 0.052, blue: 0.045, alpha: 1).setFill()
            context.fill(rect)

            let cg = context.cgContext
            cg.setFillColor(UIColor(red: 1.0, green: 0.45, blue: 0.05, alpha: 1).cgColor)
            cg.fillEllipse(in: CGRect(x: 198, y: 44, width: 164, height: 164))

            cg.setFillColor(UIColor(red: 0.42, green: 0.86, blue: 0.46, alpha: 1).cgColor)
            cg.move(to: CGPoint(x: 326, y: 50))
            cg.addCurve(to: CGPoint(x: 390, y: 34), control1: CGPoint(x: 346, y: 18), control2: CGPoint(x: 374, y: 22))
            cg.addCurve(to: CGPoint(x: 350, y: 86), control1: CGPoint(x: 390, y: 66), control2: CGPoint(x: 370, y: 84))
            cg.closePath()
            cg.fillPath()

            cg.setStrokeColor(UIColor(red: 0.16, green: 0.10, blue: 0.07, alpha: 1).cgColor)
            cg.setLineWidth(7)
            cg.setLineCap(.round)
            cg.move(to: CGPoint(x: 246, y: 116))
            cg.addLine(to: CGPoint(x: 246, y: 116))
            cg.move(to: CGPoint(x: 314, y: 116))
            cg.addLine(to: CGPoint(x: 314, y: 116))
            cg.strokePath()

            cg.setStrokeColor(UIColor(red: 0.16, green: 0.10, blue: 0.07, alpha: 1).cgColor)
            cg.setLineWidth(5)
            cg.addArc(center: CGPoint(x: 280, y: 138), radius: 28, startAngle: 0.18, endAngle: .pi - 0.18, clockwise: false)
            cg.strokePath()

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34, weight: .bold),
                .foregroundColor: UIColor(red: 0.98, green: 0.94, blue: 0.86, alpha: 1)
            ]
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor(red: 1.0, green: 0.66, blue: 0.25, alpha: 1)
            ]
            NSString(string: "Little Spud Preview").draw(in: CGRect(x: 0, y: 226, width: size.width, height: 42), withAttributes: centered(titleAttrs))
            NSString(string: "Set up Tater at taterassistant.com").draw(in: CGRect(x: 0, y: 266, width: size.width, height: 28), withAttributes: centered(subtitleAttrs))
        }
        return "data:image/png;base64,\(data.base64EncodedString())"
    }

    private func centered(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var copy = attributes
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        copy[.paragraphStyle] = paragraph
        return copy
    }

    func toggleTTS() {
        ttsEnabled.toggle()
        UserDefaults.standard.set(ttsEnabled, forKey: ttsKey)
        if ttsEnabled {
            ttsStatus = "TTS on"
        } else {
            stopSpeech()
            ttsStatus = ""
        }
    }

    func toggleVoiceInput() {
        guard session != nil else {
            statusText = "Pair Little Spud before using voice input."
            statusKind = "error"
            return
        }
        cancelPendingReopenMic()
        if isDemoMode {
            toggleDemoVoiceInput()
            return
        }
        if isVoiceRecording {
            stopVoiceInput()
            return
        }
        if isVoiceSubmitting {
            cancelVoiceInput()
            return
        }
        startVoiceInput()
    }

    func toggleNotifications() {
        if notificationsEnabled {
            notificationsEnabled = false
            UserDefaults.standard.set(false, forKey: notificationsKey)
            statusText = "Device notifications paused."
            statusKind = ""
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let granted = await LocalNotificationManager.shared.requestAuthorization()
            notificationsEnabled = granted
            UserDefaults.standard.set(granted, forKey: notificationsKey)
            if granted {
                statusText = "Device notifications enabled."
                statusKind = "ok"
                LocalNotificationManager.shared.deliver(NativeNotificationPayload(
                    title: "Little Spud",
                    body: "Device notifications enabled.",
                    tag: "little-spud-notifications-enabled",
                    url: nil
                ))
            } else {
                statusText = "Notifications are blocked in iOS Settings."
                statusKind = "error"
            }
        }
    }

    func disconnect() {
        pauseForegroundWork()
        stopSpeech()
        cancelVoiceInput()
        KeychainStore.delete(account: sessionAccount)
        session = nil
        hubConnected = false
        hubUrl = ""
        syncCode = ""
        statusText = "Little Spud forgot this pairing."
        statusKind = ""
    }

    private func refreshFromHub(showStatus: Bool) async {
        guard let currentSession = session else { return }
        if currentSession.isDemo {
            hubConnected = true
            return
        }
        do {
            let updated = try await api.sendHeartbeat(session: currentSession, messageCount: messages.count, preferHome: true)
            session = updated
            hubUrl = updated.hubUrl
            hubConnected = true
            saveSession()
            let history = try await api.fetchHistory(session: updated)
            mergeHubHistory(history)
            if showStatus {
                statusText = "Synced with Tater."
                statusKind = "ok"
            }
        } catch {
            hubConnected = false
            if showStatus {
                statusText = error.localizedDescription
                statusKind = "error"
            }
        }
    }

    private func startNotificationPoll() {
        guard session != nil, !isDemoMode, pollTask == nil else { return }
        let client = self.api
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let snapshot = await MainActor.run(body: { self?.session }) else { return }
                do {
                    if let notification = try await client.pollNotification(session: snapshot) {
                        await MainActor.run {
                            self?.hubConnected = true
                            self?.appendHubNotification(notification)
                        }
                    }
                } catch {
                    await MainActor.run {
                        self?.hubConnected = false
                        Task { [weak self] in
                            await self?.refreshFromHub(showStatus: false)
                        }
                    }
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
    }

    private func startRouteProbe() {
        guard session != nil, !isDemoMode, routeProbeTask == nil else { return }
        routeProbeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refreshFromHub(showStatus: false)
            }
        }
    }

    private func beginChatRun() {
        activeChatRunCount += 1
        isSending = activeChatRunCount > 0
        isTyping = false
    }

    private func finishChatRun() {
        activeChatRunCount = max(0, activeChatRunCount - 1)
        isSending = activeChatRunCount > 0
        isTyping = false
    }

    private func appendToolNotice(_ notice: SpudLinkToolNotice, beforeAssistantId: String) {
        let clean = notice.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let exists = messages.contains { $0.id == notice.id }
        guard !exists else { return }
        let message = LittleSpudMessage(
            id: notice.id,
            role: .assistant,
            content: "",
            createdAt: notice.createdAt,
            kind: "tool_notice"
        )
        if let assistantIndex = messages.firstIndex(where: { $0.id == beforeAssistantId }) {
            messages.insert(message, at: assistantIndex)
        } else {
            messages.append(message)
        }
        saveMessages()
        Task { [weak self] in
            await self?.revealAssistantMessage(id: notice.id, text: clean)
        }
        if ttsEnabled {
            Task { [weak self] in
                _ = await self?.beginSpeechPlayback(clean, waitForStart: false)
            }
        }
    }

    private func appendHubNotification(_ notification: HubNotification) {
        let message = LittleSpudMessage(
            id: notification.id,
            role: .system,
            content: notification.content.isEmpty ? "Notification" : notification.content,
            createdAt: notification.createdAt,
            kind: "notification"
        )
        let exists = messages.contains { existing in
            existing.id == message.id || (existing.kind == "notification" && existing.content == message.content)
        }
        guard !exists else { return }
        messages.append(message)
        sortAndLimitMessages()
        saveMessages()
        if notificationsEnabled {
            LocalNotificationManager.shared.deliver(NativeNotificationPayload(
                title: "Little Spud",
                body: message.content.replacingOccurrences(of: "\n", with: " "),
                tag: message.id,
                url: nil
            ))
        }
    }

    private func mergeHubHistory(_ history: [HubHistoryMessage]) {
        guard !history.isEmpty else { return }
        var changed = false
        for incoming in history {
            if incoming.role == .assistant, incoming.kind != "tool_notice" {
                if reconcileIncomingAssistant(incoming) {
                    changed = true
                    continue
                }
            }
            let softDuplicate = messages.contains { existing in
                existing.role == incoming.role
                && existing.content.trimmingCharacters(in: .whitespacesAndNewlines) == incoming.content.trimmingCharacters(in: .whitespacesAndNewlines)
                && (existing.kind != "tool_notice" || incoming.kind == "tool_notice")
            }
            guard !messages.contains(where: { $0.id == incoming.id }) && !softDuplicate else { continue }
            messages.append(LittleSpudMessage(
                id: incoming.id,
                role: incoming.role,
                content: incoming.content,
                createdAt: incoming.createdAt,
                kind: incoming.kind,
                attachments: incoming.attachments
            ))
            changed = true
        }
        if changed {
            sortAndLimitMessages()
            saveMessages()
        }
    }

    private func reconcileIncomingAssistant(_ incoming: HubHistoryMessage) -> Bool {
        let cleanIncoming = incoming.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanIncoming.isEmpty || !incoming.attachments.isEmpty else { return false }

        if messages.contains(where: { existing in
            existing.role == .assistant
            && existing.kind != "tool_notice"
            && existing.kind != "pending"
            && existing.content.trimmingCharacters(in: .whitespacesAndNewlines) == cleanIncoming
        }) {
            return true
        }

        guard let pendingIndex = messages.lastIndex(where: { message in
            message.role == .assistant && (message.kind == "pending" || message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }) else {
            return false
        }

        let pendingMessage = messages[pendingIndex]
        if activeChatRunCount > 0 && incoming.createdAt >= pendingMessage.createdAt.addingTimeInterval(-2) {
            return true
        }

        messages[pendingIndex] = LittleSpudMessage(
            id: pendingMessage.id,
            role: .assistant,
            content: cleanIncoming,
            createdAt: pendingMessage.createdAt,
            kind: nil,
            attachments: incoming.attachments
        )
        return true
    }

    private func startVoiceInput() {
        cancelPendingReopenMic()
        openVoiceInput()
    }

    private func toggleDemoVoiceInput() {
        if isVoiceRecording || isVoiceSubmitting {
            cancelDemoVoiceInput()
            return
        }

        demoVoiceTask?.cancel()
        demoVoiceTask = Task { [weak self] in
            guard let self else { return }
            speechStatus = "Opening mic..."
            let granted = await Self.requestMicrophonePermission()
            guard granted else {
                statusText = "Microphone access is blocked in iOS Settings."
                statusKind = "error"
                speechStatus = ""
                return
            }

            isVoiceRecording = true
            isVoiceSubmitting = false
            speechStatus = "Listening..."
            HapticManager.shared.play("replyTick")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            isVoiceRecording = false
            isVoiceSubmitting = true
            speechStatus = "Transcribing..."
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            isVoiceSubmitting = false
            speechStatus = ""
            draft = "Show me a sample image"
            HapticManager.shared.play("messageComplete")
            sendMessage(fromVoice: true)
            demoVoiceTask = nil
        }
    }

    private func cancelDemoVoiceInput() {
        demoVoiceTask?.cancel()
        demoVoiceTask = nil
        isVoiceRecording = false
        isVoiceSubmitting = false
        speechStatus = ""
    }

    private func openVoiceInput() {
        guard let currentSession = session, !isVoiceRecording, !isVoiceSubmitting else { return }

        Task { [weak self] in
            guard let self else { return }
            let granted = await Self.requestMicrophonePermission()
            guard granted else {
                statusText = "Microphone access is blocked in iOS Settings."
                statusKind = "error"
                speechStatus = ""
                return
            }

            do {
                stopSpeech()
                cleanupVoiceInput(closeSocket: true)

                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(
                    .playAndRecord,
                    mode: .voiceChat,
                    options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers]
                )
                try audioSession.setActive(true)

                let engine = AVAudioEngine()
                let inputNode = engine.inputNode
                let inputFormat = inputNode.outputFormat(forBus: 0)
                let sampleRate = Int(max(8_000, min(48_000, inputFormat.sampleRate.rounded())))
                let language = Locale.current.language.languageCode?.identifier ?? ""
                let streamURL = try api.sttStreamURL(
                    session: currentSession,
                    sampleRate: sampleRate,
                    language: language
                )
                let socket = URLSession.shared.webSocketTask(with: streamURL)

                speechWebSocket = socket
                audioEngine = engine
                isVoiceRecording = true
                isVoiceSubmitting = false
                speechStatus = "Opening mic..."
                socket.resume()
                startReceivingSpeechMessages(socket)

                inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self, weak socket] buffer, _ in
                    guard let socket else { return }
                    let data = Self.pcm16Data(from: buffer)
                    guard !data.isEmpty else { return }
                    socket.send(.data(data)) { error in
                        guard let error else { return }
                        Task { @MainActor [weak self] in
                            self?.handleVoiceFailure(error.localizedDescription)
                        }
                    }
                }
                voiceTapInstalled = true
                try engine.start()
                speechStatus = "Listening..."
            } catch {
                cleanupVoiceInput(closeSocket: true)
                statusText = "Voice input failed: \(error.localizedDescription)"
                statusKind = "error"
                speechStatus = ""
            }
        }
    }

    private func stopVoiceInput() {
        guard isVoiceRecording || isVoiceSubmitting else { return }
        stopVoiceCapture()
        isVoiceRecording = false
        isVoiceSubmitting = true
        speechStatus = "Transcribing..."
        speechWebSocket?.send(.string(#"{"type":"stop"}"#)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.handleVoiceFailure(error.localizedDescription)
            }
        }
    }

    private func cancelVoiceInput() {
        if isDemoMode {
            cancelDemoVoiceInput()
            return
        }
        cancelPendingReopenMic()
        let socket = speechWebSocket
        cleanupVoiceInput(closeSocket: false)
        socket?.send(.string(#"{"type":"cancel"}"#)) { _ in }
        socket?.cancel(with: .goingAway, reason: nil)
    }

    private func cleanupVoiceInput(closeSocket: Bool) {
        stopVoiceCapture()
        if closeSocket {
            speechWebSocket?.cancel(with: .goingAway, reason: nil)
        }
        speechWebSocket = nil
        isVoiceRecording = false
        isVoiceSubmitting = false
        speechStatus = ""
    }

    private func stopVoiceCapture() {
        if voiceTapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            voiceTapInstalled = false
        }
        audioEngine?.stop()
        audioEngine = nil
    }

    private func startReceivingSpeechMessages(_ socket: URLSessionWebSocketTask) {
        socket.receive { [weak self, weak socket] result in
            Task { @MainActor in
                guard let self, let socket, self.speechWebSocket === socket else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let value):
                        self.handleSpeechPayload(value)
                    case .data(let data):
                        if let value = String(data: data, encoding: .utf8) {
                            self.handleSpeechPayload(value)
                        }
                    @unknown default:
                        break
                    }
                    if self.speechWebSocket === socket {
                        self.startReceivingSpeechMessages(socket)
                    }
                case .failure(let error):
                    if self.isVoiceRecording || self.isVoiceSubmitting {
                        self.handleVoiceFailure(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func handleSpeechPayload(_ value: String) {
        guard
            let data = value.data(using: .utf8),
            let payload = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
        else { return }

        if let ok = payload["ok"] as? Bool, !ok {
            handleVoiceFailure(payloadErrorMessage(payload, fallback: "Voice input failed."))
            return
        }

        switch payloadString(payload, "type") {
        case "listening":
            speechStatus = "Listening..."
        case "speech_start":
            speechStatus = "Got it..."
            HapticManager.shared.play("replyTick")
        case "speech_end":
            stopVoiceCapture()
            isVoiceRecording = false
            isVoiceSubmitting = true
            speechStatus = "Transcribing..."
        case "final":
            finishVoiceTranscript(payloadString(payload, "text"))
        case "cancelled":
            cleanupVoiceInput(closeSocket: true)
        case "error":
            handleVoiceFailure(payloadErrorMessage(payload, fallback: "Voice input failed."))
        default:
            break
        }
    }

    private func finishVoiceTranscript(_ value: String) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanupVoiceInput(closeSocket: true)
        guard !clean.isEmpty else {
            speechStatus = "No speech recognized."
            return
        }
        draft = clean
        speechStatus = ""
        HapticManager.shared.play("messageComplete")
        sendMessage(fromVoice: true)
    }

    private func reopenMicAfterReply() {
        guard session != nil, !isVoiceRecording, !isVoiceSubmitting else { return }
        speechStatus = "I'm listening..."
        pendingReopenTask?.cancel()
        pendingReopenTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.pendingReopenTask = nil
                guard self.session != nil, !self.isVoiceRecording, !self.isVoiceSubmitting else { return }
                self.openVoiceInput()
            }
        }
    }

    private func cancelPendingReopenMic() {
        pendingReopenTask?.cancel()
        pendingReopenTask = nil
    }

    private func handleVoiceFailure(_ message: String) {
        cleanupVoiceInput(closeSocket: true)
        statusText = "Voice input failed: \(message)"
        statusKind = "error"
        speechStatus = ""
    }

    private func payloadString(_ payload: [String: Any], _ keys: String...) -> String {
        for key in keys {
            if let value = payload[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let value = payload[key] {
                let string = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !string.isEmpty && string != "<null>" { return string }
            }
        }
        return ""
    }

    private func payloadErrorMessage(_ payload: [String: Any], fallback: String) -> String {
        if let detail = payload["detail"] as? String, !detail.isEmpty {
            return detail
        }
        if let error = payload["error"] as? [String: Any] {
            return payloadString(error, "message", "detail").isEmpty ? fallback : payloadString(error, "message", "detail")
        }
        return payloadString(payload, "error", "message").isEmpty ? fallback : payloadString(payload, "error", "message")
    }

    nonisolated private static func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    nonisolated private static func pcm16Data(from buffer: AVAudioPCMBuffer) -> Data {
        guard let channels = buffer.floatChannelData else { return Data() }
        let channel = channels[0]
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return Data() }

        var data = Data(capacity: frameCount * 2)
        for index in 0..<frameCount {
            let clamped = max(-1.0, min(1.0, channel[index]))
            var sample = Int16(clamped < 0 ? clamped * 32_768 : clamped * 32_767).littleEndian
            withUnsafeBytes(of: &sample) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        return data
    }

    private func revealAssistantMessage(id: String, text: String) async {
        let characters = Array(text)
        let chunkSize = characters.count > 900 ? 10 : characters.count > 420 ? 6 : 3
        var index = 0
        var lastHaptic = Date.distantPast

        while index < characters.count {
            index = min(index + chunkSize, characters.count)
            if let messageIndex = messages.firstIndex(where: { $0.id == id }) {
                messages[messageIndex].content = String(characters.prefix(index))
            }
            if Date().timeIntervalSince(lastHaptic) > 0.085 {
                HapticManager.shared.play("replyTick")
                lastHaptic = Date()
            }
            try? await Task.sleep(nanoseconds: 12_000_000)
        }

        if let messageIndex = messages.firstIndex(where: { $0.id == id }) {
            messages[messageIndex].content = text
        }
        completedMessageId = id
        HapticManager.shared.play("messageComplete")
        saveMessages()
        try? await Task.sleep(nanoseconds: 420_000_000)
        if completedMessageId == id {
            completedMessageId = nil
        }
    }

    private func beginSpeechPlayback(_ value: String, waitForStart: Bool) async -> Task<Void, Never>? {
        if waitForStart {
            return await prepareSpeechPlayback(value)
        }
        return Task { [weak self] in
            guard let completion = await self?.prepareSpeechPlayback(value) else { return }
            await completion.value
        }
    }

    private func prepareSpeechPlayback(_ value: String) async -> Task<Void, Never>? {
        guard let session, ttsEnabled else { return nil }
        let speechText = textForSpeech(value)
        guard !speechText.isEmpty else { return nil }
        if session.isDemo {
            return prepareDemoSpeechPlayback(speechText)
        }
        stopSpeech()
        ttsStatus = "Preparing voice..."

        do {
            let data = try await api.fetchSpeech(session: session, text: speechText)
            guard ttsEnabled else { return nil }
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
            let player = try AVAudioPlayer(data: data)
            player.prepareToPlay()
            audioPlayer = player
            player.play()
            ttsStatus = "Speaking..."

            let duration = max(0.2, player.duration + 0.25)
            return Task { [weak self, weak player] in
                try? await Task.sleep(nanoseconds: UInt64(min(duration, 3600) * 1_000_000_000))
                await MainActor.run {
                    guard let self, let player, self.audioPlayer === player else { return }
                    self.audioPlayer = nil
                    self.ttsStatus = self.ttsEnabled ? "TTS on" : ""
                }
            }
        } catch {
            ttsStatus = "TTS failed."
            statusText = "TTS failed: \(error.localizedDescription)"
            statusKind = "error"
            return nil
        }
    }

    private func prepareDemoSpeechPlayback(_ speechText: String) -> Task<Void, Never>? {
        stopSpeech()
        ttsStatus = "Speaking..."
        let utterance = AVSpeechUtterance(string: speechText)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        speechSynthesizer.speak(utterance)

        let estimatedSeconds = min(90.0, max(1.0, Double(speechText.count) / 18.0))
        return Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(estimatedSeconds * 1_000_000_000))
            await MainActor.run {
                guard let self else { return }
                if self.isDemoMode {
                    self.ttsStatus = self.ttsEnabled ? "TTS on" : ""
                }
            }
        }
    }

    private func stopSpeech() {
        audioPlayer?.stop()
        audioPlayer = nil
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func textForSpeech(_ value: String) -> String {
        var text = value
        text = text.replacingOccurrences(of: #"```[\s\S]*?```"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\!\[[^\]]*\]\([^)]*\)"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"https?://\S+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[`*_#>~|]+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
    }

    private func sortAndLimitMessages() {
        messages.sort { $0.createdAt < $1.createdAt }
        if messages.count > 80 {
            messages = Array(messages.suffix(80))
        }
    }

    private func loadSession() {
        do {
            let stored = try KeychainStore.load(LittleSpudSession.self, account: sessionAccount)
            session = stored
            hubConnected = stored != nil
            userName = stored?.userName ?? userName
            deviceName = stored?.deviceName ?? deviceName
            hubUrl = stored?.hubUrl ?? hubUrl
        } catch {
            hubConnected = false
            statusText = error.localizedDescription
            statusKind = "error"
        }
    }

    private func saveSession() {
        guard let session else { return }
        do {
            try KeychainStore.save(session, account: sessionAccount)
        } catch {
            statusText = error.localizedDescription
            statusKind = "error"
        }
    }

    private func loadMessages() {
        guard let data = UserDefaults.standard.data(forKey: messagesKey) else { return }
        messages = (try? JSONDecoder.littleSpud.decode([LittleSpudMessage].self, from: data)) ?? []
    }

    private func saveMessages() {
        let trimmed = Array(messages.suffix(80))
        guard let data = try? JSONEncoder.littleSpud.encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: messagesKey)
    }
}
