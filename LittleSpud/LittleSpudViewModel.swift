import AVFoundation
import CryptoKit
import Foundation
import MediaPlayer
import SwiftUI
import UIKit

actor LittleSpudMusicArtworkCache {
    static let shared = LittleSpudMusicArtworkCache()

    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let directory: URL

    private init() {
        memory.countLimit = 320
        memory.totalCostLimit = 48 * 1024 * 1024
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("LittleSpudAlbumArtwork-v1", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func image(for url: URL, cacheKey rawCacheKey: String) async -> UIImage? {
        let cacheKey = rawCacheKey.isEmpty ? url.absoluteString : rawCacheKey
        if let cached = memory.object(forKey: cacheKey as NSString) {
            return cached
        }
        if let task = inFlight[cacheKey] {
            return await task.value
        }

        let fileURL = directory.appendingPathComponent(Self.fileName(for: cacheKey))
        let task = Task.detached(priority: .utility) {
            await Self.loadImage(from: url, fileURL: fileURL, directory: fileURL.deletingLastPathComponent())
        }
        inFlight[cacheKey] = task
        let image = await task.value
        inFlight.removeValue(forKey: cacheKey)
        if let image {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            memory.setObject(image, forKey: cacheKey as NSString, cost: cost)
        }
        return image
    }

    private static func loadImage(
        from url: URL,
        fileURL: URL,
        directory: URL
    ) async -> UIImage? {
        let fileManager = FileManager.default
        if let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
           let modified = values.contentModificationDate,
           Date().timeIntervalSince(modified) < 30 * 24 * 60 * 60,
           let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            return image
        }
        try? fileManager.removeItem(at: fileURL)

        do {
            var request = URLRequest(
                url: url,
                cachePolicy: .returnCacheDataElseLoad,
                timeoutInterval: 30
            )
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                return nil
            }
            guard !data.isEmpty,
                  data.count <= 20 * 1024 * 1024,
                  let image = UIImage(data: data) else {
                return nil
            }
            try? data.write(to: fileURL, options: .atomic)
            pruneDiskCache(in: directory)
            return image
        } catch {
            return nil
        }
    }

    private static func fileName(for cacheKey: String) -> String {
        SHA256.hash(data: Data(cacheKey.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func pruneDiskCache(in directory: URL) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }
        let rows = files.compactMap { url -> (URL, Date, Int)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }.sorted { $0.1 < $1.1 }
        var totalBytes = rows.reduce(0) { $0 + $1.2 }
        var totalFiles = rows.count
        for row in rows where totalBytes > 128 * 1024 * 1024 || totalFiles > 500 {
            try? FileManager.default.removeItem(at: row.0)
            totalBytes -= row.2
            totalFiles -= 1
        }
    }
}

@MainActor
final class LittleSpudViewModel: ObservableObject {
    @Published var userName = ""
    @Published var deviceName = UIDevice.current.name
    @Published var hubUrl = ""
    @Published var syncCode = ""
    @Published var session: LittleSpudSession?
    @Published var messages: [LittleSpudMessage] = []
    @Published var notifications: [LittleSpudMessage] = []
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
    @Published var notificationUnreadCount = 0
    @Published var homeSnapshot: LittleSpudHomeSnapshot = .empty
    @Published var homeLoading = false
    @Published var homeError = ""
    @Published var homeControlsInFlight: Set<String> = []
    @Published var homeCameraSnapshots: [String: UIImage] = [:]
    @Published var homeCameraLoading: Set<String> = []
    @Published var homeCameraErrors: [String: String] = [:]
    @Published var musicSnapshot: LittleSpudMusicSnapshot = .empty
    @Published var musicLoading = false
    @Published private(set) var musicTransportLoading = false
    @Published var musicError = ""
    @Published var musicQuery = ""
    @Published var selectedMusicTargetIDs: Set<String> = []
    @Published var musicVolumePercent = 75
    @Published var musicProgressSeconds: Double = 0
    @Published var localMusicTrack: LittleSpudMusicTrack?
    @Published var localMusicStatus = "idle"
    @Published private(set) var localMusicQueue: [LittleSpudMusicTrack] = []
    @Published private(set) var localMusicQueueIndex = -1
    @Published private(set) var localMusicContinuationPending = false
    @Published private(set) var localMusicRadioName = "Little Spud Continuous Radio"
    @Published var temperatureUnitPreference: LittleSpudTemperatureUnitPreference = .automatic
    @Published private(set) var temperatureRoomLocationOverrides: [String: LittleSpudTemperatureRoomLocation] = [:]
    @Published var activeLane: LittleSpudLane = .chat {
        didSet {
            if activeLane != .music {
                stopMusicStateSync()
            }
            if activeLane == .notifications {
                markNotificationsRead()
            } else if activeLane == .home {
                refreshHome()
            } else if activeLane == .music {
                refreshMusic()
                startMusicStateSync()
            }
        }
    }

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

    var selectedMusicTargets: [LittleSpudMusicTarget] {
        musicSnapshot.targets.filter { selectedMusicTargetIDs.contains($0.id) }
    }

    var selectedMusicTarget: LittleSpudMusicTarget? {
        selectedMusicTargets.first
    }

    var usesLocalMusicPlayback: Bool {
        selectedMusicTargets.contains { $0.isLocal }
    }

    var musicTargetSummary: String {
        let targets = selectedMusicTargets
        if targets.isEmpty { return "Choose players" }
        if targets.count == 1 { return targets[0].label }
        return "\(targets.count) players"
    }

    var musicCurrentTrack: LittleSpudMusicTrack? {
        usesLocalMusicPlayback
            ? localMusicTrack
            : musicSnapshot.player.current
    }

    var musicPlaybackStatus: String {
        usesLocalMusicPlayback
            ? localMusicStatus
            : musicSnapshot.player.status
    }

    var musicQueue: [LittleSpudMusicTrack] {
        if usesLocalMusicPlayback {
            if !localMusicQueue.isEmpty {
                return localMusicQueue
            }
            return musicSnapshot.player.queue.isEmpty
                ? musicSnapshot.tracks
                : musicSnapshot.player.queue
        }
        return musicSnapshot.player.queue
    }

    var musicQueueIndex: Int {
        if usesLocalMusicPlayback, !localMusicQueue.isEmpty {
            return localMusicQueueIndex
        }
        return musicSnapshot.player.queueIndex
    }

    var musicContinuousRadio: Bool {
        usesLocalMusicPlayback || musicSnapshot.player.continuousRadio
    }

    var musicRadioName: String {
        usesLocalMusicPlayback
            ? localMusicRadioName
            : musicSnapshot.player.radioName
    }

    var musicDurationSeconds: Double {
        if usesLocalMusicPlayback {
            return localMusicTrack?.durationSeconds ?? 0
        }
        return max(
            musicSnapshot.player.durationSeconds,
            musicCurrentTrack?.durationSeconds ?? 0
        )
    }

    var musicProviderLabel: String {
        musicSnapshot.provider?.label ?? "Music Core"
    }

    var connectedTitle: String {
        guard let session else { return "Offline" }
        return session.displayNodeName
    }

    var assistantDisplayName: String {
        session?.assistantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? session?.assistantName.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Tater"
            : "Tater"
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
    private let notificationMessagesKey = "little-spud-ios:notification-messages:v1"
    private let notificationsKey = "little-spud-ios:notifications"
    private let remotePushTokenKey = "little-spud-ios:remote-push-token"
    private let remotePushRegistrationAccount = "little-spud-remote-push-registration"
    private let legacyRemotePushRegistrationKey = "little-spud-ios:remote-push-registration"
    private let ttsKey = "little-spud-ios:tts-enabled"
    private let temperatureUnitPreferenceKey = "little-spud-ios:temperature-unit"
    private let temperatureRoomLocationsKey = "little-spud-ios:temperature-room-locations"
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
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    private var backgroundGraceTask: Task<Void, Never>?
    private var pushRegistrationTask: Task<Void, Never>?
    private var pushRegistrationGeneration = 0
    private var pushRegistrationFingerprintInFlight = ""
    private var remotePushRegistrationUnsupported = false
    private var pendingNotificationAckIDs: Set<String> = []
    private var lastStreamHapticByMessageId: [String: Date] = [:]
    private var homeTask: Task<Void, Never>?
    private var musicTask: Task<Void, Never>?
    private var musicStateSyncTask: Task<Void, Never>?
    private var musicProgressTask: Task<Void, Never>?
    private var localMusicContinuationTask: Task<Void, Never>?
    private var localMusicQueueSessionID = ""
    private var localMusicPlayer: AVPlayer?
    private var localMusicFinishedObserver: NSObjectProtocol?
    private var nowPlayingCommandsConfigured = false
    private var nowPlayingArtworkTask: Task<Void, Never>?

    func start() {
        guard !didStart else { return }
        didStart = true
        configureNowPlayingCommands()
        notificationsEnabled = UserDefaults.standard.bool(forKey: notificationsKey)
        ttsEnabled = UserDefaults.standard.bool(forKey: ttsKey)
        temperatureUnitPreference = LittleSpudTemperatureUnitPreference(
            rawValue: UserDefaults.standard.string(forKey: temperatureUnitPreferenceKey) ?? ""
        ) ?? .automatic
        let savedTemperatureRoomLocations = UserDefaults.standard.dictionary(
            forKey: temperatureRoomLocationsKey
        ) as? [String: String] ?? [:]
        temperatureRoomLocationOverrides = savedTemperatureRoomLocations.reduce(into: [:]) {
            result,
            item in
            if let location = LittleSpudTemperatureRoomLocation(rawValue: item.value) {
                result[item.key] = location
            }
        }
        ttsStatus = ttsEnabled ? "TTS on" : ""
        loadSession()
        loadNotifications()
        loadMessages()
        importSharedResolvedNotifications()
        if notificationsEnabled {
            requestRemoteNotifications()
        }
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
        endBackgroundGracePeriod()
        if isDemoMode {
            hubConnected = true
            if activeLane == .home {
                refreshHome()
            } else if activeLane == .music {
                refreshMusic()
            }
            return
        }
        importSharedResolvedNotifications()
        startNotificationPoll()
        startRouteProbe()
        if activeLane == .music {
            refreshMusic()
            startMusicStateSync()
        }
        syncRemotePushRegistrationIfPossible()
        Task { [weak self] in
            await self?.refreshFromHub(showStatus: false)
        }
    }

    func pauseForegroundWork() {
        routeProbeTask?.cancel()
        routeProbeTask = nil
        stopMusicStateSync()
        demoVoiceTask?.cancel()
        demoVoiceTask = nil
        cancelVoiceInput()
        if pollTask != nil || activeChatRunCount > 0 {
            beginBackgroundGracePeriod()
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
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
                remotePushRegistrationUnsupported = false
                saveSession()
                UserDefaults.standard.set(userName, forKey: "little-spud-ios:user-name")
                syncRemotePushRegistrationIfPossible(force: true)
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
        homeSnapshot = demoHomeSnapshot()
        homeError = ""
        homeCameraSnapshots = [:]
        homeCameraLoading = []
        homeCameraErrors = [:]
        musicSnapshot = demoMusicSnapshot()
        selectedMusicTargetIDs = Set(musicSnapshot.targets.prefix(1).map(\.id))
        musicError = ""
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
        let userCreatedAt = Date()
        let assistantCreatedAt = userCreatedAt.addingTimeInterval(0.001)
        let userMessage = LittleSpudMessage(
            id: UUID().uuidString,
            role: .user,
            content: userContent,
            createdAt: userCreatedAt,
            kind: nil,
            attachments: outgoingAttachments
        )
        messages.append(userMessage)
        messages.append(LittleSpudMessage(
            id: assistantId,
            role: .assistant,
            content: "Tater is thinking",
            createdAt: assistantCreatedAt,
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
            var shouldFinishChatRun = true
            defer {
                if shouldFinishChatRun {
                    self.finishChatRun()
                }
                self.saveMessages()
            }
            do {
                let chatSession = try await api.sendHeartbeat(session: currentSession, messageCount: messages.count, preferHome: true)
                session = chatSession
                hubUrl = chatSession.hubUrl
                hubConnected = true
                saveSession()

                let response = try await api.sendChat(
                    session: chatSession,
                    messages: priorMessages,
                    text: text,
                    attachments: outgoingAttachments,
                    onToolNotice: { notice in
                        Task { @MainActor [weak self] in
                            self?.appendToolNotice(notice, beforeAssistantId: assistantId)
                        }
                    },
                    onResponseChunk: { [weak self] chunk in
                        self?.appendAssistantResponseChunk(
                            id: assistantId,
                            chunk: chunk
                        )
                    }
                )
                let reply = response.content
                guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !response.attachments.isEmpty else {
                    throw SpudLinkAPIError.message("Tater returned no message content.")
                }
                if let messageIndex = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[messageIndex].content = reply
                    messages[messageIndex].kind = nil
                    messages[messageIndex].attachments = response.attachments
                }
                let ttsTask = await beginSpeechPlayback(reply, waitForStart: true)
                await completeAssistantResponse(id: assistantId)
                await refreshFromHub(showStatus: false)
                if fromVoice && response.reopenMic {
                    if let ttsTask {
                        await ttsTask.value
                    }
                    reopenMicAfterReply()
                }
            } catch {
                if self.isRecoverableChatDisconnect(error) {
                    shouldFinishChatRun = false
                    self.finishChatRun()
                    await self.markChatRunDetached(assistantId: assistantId)
                    self.saveMessages()
                    return
                }
                let errorMessage = "Request failed: \(error.localizedDescription)"
                lastStreamHapticByMessageId.removeValue(forKey: assistantId)
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

    func setTemperatureUnitPreference(_ preference: LittleSpudTemperatureUnitPreference) {
        temperatureUnitPreference = preference
        UserDefaults.standard.set(preference.rawValue, forKey: temperatureUnitPreferenceKey)
    }

    var temperatureRooms: [LittleSpudHomeRoom] {
        homeRooms.filter { room in
            room.categories.contains { ["temperature", "climate"].contains($0.id) }
        }
    }

    func temperatureRoomLocation(
        for room: LittleSpudHomeRoom
    ) -> LittleSpudTemperatureRoomLocation {
        temperatureRoomLocationOverrides[room.id]
            ?? Self.suggestedTemperatureRoomLocation(name: room.name)
    }

    func hasTemperatureRoomLocationOverride(roomID: String) -> Bool {
        temperatureRoomLocationOverrides[roomID] != nil
    }

    func setTemperatureRoomLocation(
        _ location: LittleSpudTemperatureRoomLocation,
        roomID: String
    ) {
        temperatureRoomLocationOverrides[roomID] = location
        persistTemperatureRoomLocations()
    }

    func resetTemperatureRoomLocations() {
        temperatureRoomLocationOverrides = [:]
        UserDefaults.standard.removeObject(forKey: temperatureRoomLocationsKey)
    }

    func showChatLane() {
        activeLane = .chat
    }

    func showNotificationLane() {
        activeLane = .notifications
    }

    func showHomeLane() {
        activeLane = .home
    }

    func showMusicLane() {
        activeLane = .music
    }

    func toggleNotificationLane() {
        activeLane = activeLane == .notifications ? .chat : .notifications
    }

    var homeRooms: [LittleSpudHomeRoom] {
        homeSnapshot.rooms
    }

    func homeRoom(id: String) -> LittleSpudHomeRoom? {
        homeSnapshot.rooms.first { $0.id == id }
    }

    private func persistTemperatureRoomLocations() {
        let values = temperatureRoomLocationOverrides.mapValues(\.rawValue)
        UserDefaults.standard.set(values, forKey: temperatureRoomLocationsKey)
    }

    private static func suggestedTemperatureRoomLocation(
        name: String
    ) -> LittleSpudTemperatureRoomLocation {
        let normalized = name
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let outdoorNames = [
            "outside",
            "outdoor",
            "backyard",
            "back yard",
            "front yard",
            "side yard",
            "yard",
            "patio",
            "porch",
            "deck",
            "balcony",
            "garden",
            "greenhouse",
            "pool",
            "driveway",
            "carport",
            "front door",
            "back door",
            "shed",
            "weather",
        ]
        return outdoorNames.contains(where: normalized.contains)
            ? .outdoor
            : .indoor
    }

    func isHomeControlInFlight(roomID: String, categoryID: String) -> Bool {
        homeControlsInFlight.contains(homeControlKey(roomID: roomID, categoryID: categoryID))
    }

    func homeCameraSnapshot(roomID: String, cameraID: String) -> UIImage? {
        homeCameraSnapshots[homeCameraKey(roomID: roomID, cameraID: cameraID)]
    }

    func isHomeCameraLoading(roomID: String, cameraID: String) -> Bool {
        homeCameraLoading.contains(homeCameraKey(roomID: roomID, cameraID: cameraID))
    }

    func homeCameraError(roomID: String, cameraID: String) -> String {
        homeCameraErrors[homeCameraKey(roomID: roomID, cameraID: cameraID)] ?? ""
    }

    func refreshHomeCameraSnapshot(roomID: String, cameraID: String) async {
        guard UIApplication.shared.applicationState == .active else { return }
        guard let currentSession = session, !currentSession.isDemo else { return }
        let key = homeCameraKey(roomID: roomID, cameraID: cameraID)
        guard !homeCameraLoading.contains(key) else { return }
        homeCameraLoading.insert(key)
        defer {
            homeCameraLoading.remove(key)
        }
        do {
            let data = try await api.fetchHomeCameraSnapshot(
                session: currentSession,
                roomID: roomID,
                cameraID: cameraID
            )
            guard !Task.isCancelled else { return }
            guard let image = UIImage(data: data) else {
                throw SpudLinkAPIError.message("Camera snapshot failed: Tater returned an unsupported image.")
            }
            homeCameraSnapshots[key] = image
            homeCameraErrors.removeValue(forKey: key)
        } catch {
            guard !Task.isCancelled, !isExpectedCancellation(error) else { return }
            homeCameraErrors[key] = error.localizedDescription
        }
    }

    func refreshMusic(force: Bool = false, query: String? = nil, limit: Int? = nil) {
        guard let currentSession = session else { return }
        if currentSession.isDemo {
            musicSnapshot = demoMusicSnapshot(query: query ?? musicQuery)
            ensureMusicTargetSelection()
            syncMusicProgress()
            musicError = ""
            musicLoading = false
            return
        }
        musicTask?.cancel()
        musicLoading = true
        if force {
            musicError = ""
        }
        let search = (query ?? musicQuery)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        musicTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.musicLoading = false
                self.musicTask = nil
            }
            do {
                let snapshot = try await api.fetchMusic(
                    session: currentSession,
                    query: search,
                    refresh: force,
                    limit: limit
                )
                guard !Task.isCancelled else { return }
                applyRemoteMusicSnapshot(snapshot)
                musicError = snapshot.provider?.connected == false
                    ? "Connect \(snapshot.provider?.label ?? "the active provider") in Music Core."
                    : ""
            } catch {
                guard !Task.isCancelled, !isExpectedCancellation(error) else { return }
                if (error as? SpudLinkAPIError)?.statusCode == 404 {
                    musicError = "Install Music Core 2.0 or newer from Tater Shop."
                } else if (error as? SpudLinkAPIError)?.statusCode == 409 {
                    musicError = "Start Music Core in Tater before using this player."
                } else {
                    musicError = error.localizedDescription
                }
            }
        }
    }

    func searchMusic() {
        refreshMusic(query: musicQuery)
    }

    func toggleMusicTarget(_ targetID: String) {
        guard let target = musicSnapshot.targets.first(where: { $0.id == targetID }) else {
            return
        }
        if target.isLocal {
            selectedMusicTargetIDs = [targetID]
            localMusicPlayer?.volume = Float(musicVolumePercent) / 100
            return
        }
        if usesLocalMusicPlayback, localMusicPlayer != nil {
            stopLocalMusic(clearTrack: true)
        }
        selectedMusicTargetIDs = Set(selectedMusicTargetIDs.filter { id in
            musicSnapshot.targets.first(where: { $0.id == id })?.isLocal != true
        })
        if selectedMusicTargetIDs.contains(targetID) {
            if selectedMusicTargetIDs.count > 1 {
                selectedMusicTargetIDs.remove(targetID)
            }
        } else {
            selectedMusicTargetIDs.insert(targetID)
        }
        if session?.isDemo != true {
            runRemoteMusicAction("set_targets")
        }
    }

    func setMusicVolume(_ value: Double) {
        musicVolumePercent = max(0, min(100, Int(value.rounded())))
        localMusicPlayer?.volume = Float(musicVolumePercent) / 100
    }

    func commitMusicVolume() {
        guard !usesLocalMusicPlayback else { return }
        // Keep every subsequent transport command on the newly selected volume,
        // even if the set-volume request and a fast follow-up tap overlap.
        musicSnapshot.player.volumePercent = musicVolumePercent
        if session?.isDemo == true {
            return
        }
        runRemoteMusicAction("set_volume")
    }

    func playMusic(_ track: LittleSpudMusicTrack) {
        guard let currentSession = session else { return }
        ensureMusicTargetSelection()
        guard !selectedMusicTargets.isEmpty else {
            musicError = "Choose where the music should play."
            return
        }
        if usesLocalMusicPlayback {
            startLocalMusicQueue([track], at: 0)
            playMusicLocally(track, session: currentSession)
            return
        }
        if localMusicPlayer != nil {
            stopLocalMusic(clearTrack: true)
        }
        let targetIDs = selectedMusicTargets.map(\.id)
        guard !currentSession.isDemo else {
            musicSnapshot.player.current = track
            musicSnapshot.player.status = "playing"
            musicSnapshot.player.targets = targetIDs
            musicSnapshot.player.queue = musicSnapshot.tracks
            musicSnapshot.player.queueCount = musicSnapshot.tracks.count
            musicSnapshot.player.queueIndex = musicSnapshot.tracks.firstIndex(of: track) ?? 0
            musicSnapshot.player.durationSeconds = track.durationSeconds
            musicSnapshot.player.positionSeconds = 0
            syncMusicProgress()
            musicError = ""
            HapticManager.shared.play("messageComplete")
            return
        }
        runRemoteMusicAction("play", trackID: track.id)
    }

    func playMusicAlbum(_ tracks: [LittleSpudMusicTrack]) {
        var seen = Set<String>()
        let queue = tracks.filter { track in
            !track.id.isEmpty && seen.insert(track.id).inserted
        }
        guard let first = queue.first, let currentSession = session else { return }
        ensureMusicTargetSelection()
        guard !selectedMusicTargets.isEmpty else {
            musicError = "Choose where the music should play."
            return
        }
        if usesLocalMusicPlayback {
            startLocalMusicQueue(queue, at: 0)
            localMusicRadioName = first.album.isEmpty ? "Album" : first.album
            playMusicLocally(first, session: currentSession)
            return
        }
        if localMusicPlayer != nil {
            stopLocalMusic(clearTrack: true)
        }
        let targetIDs = selectedMusicTargets.map(\.id)
        guard !currentSession.isDemo else {
            musicSnapshot.player.current = first
            musicSnapshot.player.status = "playing"
            musicSnapshot.player.targets = targetIDs
            musicSnapshot.player.queue = queue
            musicSnapshot.player.queueCount = queue.count
            musicSnapshot.player.queueIndex = 0
            musicSnapshot.player.radioName = first.album
            musicSnapshot.player.durationSeconds = first.durationSeconds
            musicSnapshot.player.positionSeconds = 0
            syncMusicProgress()
            musicError = ""
            HapticManager.shared.play("messageComplete")
            return
        }
        runRemoteMusicAction("play_queue", trackIDs: queue.map(\.id))
    }

    func playMusicRecommendation(_ recommendation: LittleSpudMusicRecommendation) {
        guard let currentSession = session else { return }
        ensureMusicTargetSelection()
        guard !selectedMusicTargets.isEmpty else {
            musicError = "Choose where the music should play."
            return
        }
        if usesLocalMusicPlayback {
            guard let first = recommendation.tracks.first else { return }
            startLocalMusicQueue(recommendation.tracks, at: 0)
            localMusicRadioName = recommendation.name
            playMusicLocally(first, session: currentSession)
            return
        }
        guard !currentSession.isDemo else {
            guard let first = recommendation.tracks.first else { return }
            musicSnapshot.player.current = first
            musicSnapshot.player.status = "playing"
            musicSnapshot.player.targets = selectedMusicTargets.map(\.id)
            musicSnapshot.player.queue = recommendation.tracks
            musicSnapshot.player.queueCount = recommendation.tracks.count
            musicSnapshot.player.queueIndex = 0
            musicSnapshot.player.radioName = recommendation.name
            musicSnapshot.player.durationSeconds = first.durationSeconds
            musicSnapshot.player.positionSeconds = 0
            syncMusicProgress()
            return
        }
        runRemoteMusicAction(
            "play_recommendation",
            recommendationID: recommendation.id
        )
    }

    func browseMusic(_ value: String) {
        musicQuery = value
        refreshMusic(query: value, limit: 200)
    }

    func clearMusicBrowse() {
        musicQuery = ""
        refreshMusic(query: "")
    }

    func playMusicQueueTrack(at index: Int) {
        guard let currentSession = session else { return }
        let queue = musicQueue
        guard queue.indices.contains(index) else { return }
        ensureMusicTargetSelection()
        guard !selectedMusicTargets.isEmpty else {
            musicError = "Choose where the music should play."
            return
        }

        let track = queue[index]
        if usesLocalMusicPlayback {
            if localMusicQueue.map(\.id) != queue.map(\.id) {
                startLocalMusicQueue(queue, at: index)
            } else {
                localMusicQueueIndex = index
            }
            playMusicLocally(track, session: currentSession)
            return
        }

        if currentSession.isDemo {
            musicSnapshot.player.current = track
            musicSnapshot.player.status = "playing"
            musicSnapshot.player.queue = queue
            musicSnapshot.player.queueCount = queue.count
            musicSnapshot.player.queueIndex = index
            musicSnapshot.player.durationSeconds = track.durationSeconds
            musicSnapshot.player.positionSeconds = 0
            syncMusicProgress()
            musicError = ""
            HapticManager.shared.play("messageComplete")
            return
        }

        // Music Core starts play_queue at its first entry. Rotate the existing
        // queue so the selected song starts immediately while preserving its
        // circular play order.
        let selectedQueue = Array(queue[index...]) + Array(queue[..<index])
        runRemoteMusicAction("play_queue", trackIDs: selectedQueue.map(\.id))
    }

    func toggleMusicPlayback() {
        if usesLocalMusicPlayback {
            guard let player = localMusicPlayer else {
                if let track = localMusicTrack ?? musicSnapshot.tracks.first {
                    playMusic(track)
                }
                return
            }
            if localMusicStatus == "playing" {
                player.pause()
                localMusicStatus = "paused"
            } else {
                player.play()
                localMusicStatus = "playing"
            }
            syncMusicProgress()
            updateNowPlayingPlaybackState()
            return
        }
        let status = musicPlaybackStatus.lowercased()
        if session?.isDemo == true {
            musicSnapshot.player.status = status == "playing" ? "paused" : "playing"
            syncMusicProgress()
            return
        }
        switch status {
        case "playing":
            runRemoteMusicAction("pause")
        default:
            // Resume is also used for a stopped player with a staged timeline
            // position. Music Core decides whether that means resume-from-seek
            // or a normal start from the beginning.
            runRemoteMusicAction("resume")
        }
    }

    func stopMusic() {
        if usesLocalMusicPlayback {
            localMusicContinuationTask?.cancel()
            localMusicContinuationTask = nil
            localMusicContinuationPending = false
            stopLocalMusic()
            syncMusicProgress()
        } else {
            runRemoteMusicAction("stop")
        }
    }

    func skipMusic(_ direction: Int) {
        if usesLocalMusicPlayback {
            let queue = musicQueue
            guard !queue.isEmpty, let currentSession = session else { return }
            let currentIndex = queue.indices.contains(localMusicQueueIndex)
                ? localMusicQueueIndex
                : queue.firstIndex { $0.id == localMusicTrack?.id }
                    ?? (direction > 0 ? -1 : 0)
            localMusicQueueIndex = (
                currentIndex + (direction >= 0 ? 1 : -1) + queue.count
            ) % queue.count
            playMusicLocally(queue[localMusicQueueIndex], session: currentSession)
        } else {
            runRemoteMusicAction(direction >= 0 ? "next" : "previous")
        }
    }

    func seekMusic(to value: Double) {
        let position = max(0, min(musicDurationSeconds, value))
        musicProgressSeconds = position
        if usesLocalMusicPlayback {
            localMusicPlayer?.seek(
                to: CMTime(seconds: position, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            updateNowPlayingPlaybackState(elapsedTime: position)
            return
        }
        if session?.isDemo == true {
            musicSnapshot.player.positionSeconds = position
            syncMusicProgress()
            return
        }
        runRemoteMusicAction("seek", positionSeconds: position)
    }

    private func runRemoteMusicAction(
        _ action: String,
        trackID: String = "",
        trackIDs: [String] = [],
        recommendationID: String = "",
        positionSeconds: Double? = nil
    ) {
        guard let currentSession = session, !currentSession.isDemo else { return }
        guard !musicLoading else { return }
        let isTransportAction = [
            "play", "play_queue", "play_recommendation",
            "pause", "resume", "replay", "stop", "next", "previous"
        ].contains(action)
        musicLoading = true
        musicTransportLoading = isTransportAction
        musicError = ""
        if isTransportAction {
            HapticManager.shared.play("buttonPress")
        }
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.musicLoading = false
                if isTransportAction {
                    self.musicTransportLoading = false
                }
            }
            do {
                let snapshot = try await api.controlMusic(
                    session: currentSession,
                    action: action,
                    trackID: trackID,
                    trackIDs: trackIDs,
                    recommendationID: recommendationID,
                    targets: selectedMusicTargets.map(\.id),
                    provider: musicSnapshot.provider?.id ?? "",
                    volumePercent: musicVolumePercent,
                    positionSeconds: positionSeconds
                )
                applyRemoteMusicSnapshot(snapshot)
                if !isTransportAction {
                    HapticManager.shared.play("messageComplete")
                }
            } catch {
                musicError = error.localizedDescription
            }
        }
    }

    private func playMusicLocally(
        _ track: LittleSpudMusicTrack,
        session currentSession: LittleSpudSession
    ) {
        guard !currentSession.isDemo else {
            localMusicTrack = track
            localMusicStatus = "playing"
            musicProgressSeconds = 0
            syncMusicProgress()
            scheduleLocalMusicContinuationIfNeeded(session: currentSession)
            musicError = ""
            HapticManager.shared.play("messageComplete")
            return
        }
        do {
            let streamURL = try api.musicStreamURL(
                session: currentSession,
                track: track
            )
            stopLocalMusic(clearTrack: false)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            let item = AVPlayerItem(url: streamURL)
            let player = AVPlayer(playerItem: item)
            player.volume = Float(musicVolumePercent) / 100
            localMusicPlayer = player
            localMusicTrack = track
            localMusicStatus = "playing"
            musicProgressSeconds = 0
            localMusicFinishedObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.localMusicStatus = "finished"
                    self.skipMusic(1)
                }
            }
            player.play()
            syncMusicProgress()
            publishNowPlayingInfo(for: track)
            reportLocalMusicStarted(track, session: currentSession)
            scheduleLocalMusicContinuationIfNeeded(session: currentSession)
            musicError = ""
            HapticManager.shared.play("messageComplete")
        } catch {
            localMusicStatus = "error"
            musicError = error.localizedDescription
            clearNowPlayingInfo()
        }
    }

    private func stopLocalMusic(clearTrack: Bool = false) {
        localMusicPlayer?.pause()
        localMusicPlayer = nil
        if let observer = localMusicFinishedObserver {
            NotificationCenter.default.removeObserver(observer)
            localMusicFinishedObserver = nil
        }
        localMusicStatus = "stopped"
        musicProgressTask?.cancel()
        musicProgressTask = nil
        musicProgressSeconds = 0
        clearNowPlayingInfo()
        if clearTrack {
            localMusicContinuationTask?.cancel()
            localMusicContinuationTask = nil
            localMusicContinuationPending = false
            localMusicTrack = nil
            localMusicQueue = []
            localMusicQueueIndex = -1
            localMusicQueueSessionID = ""
            localMusicRadioName = "Little Spud Continuous Radio"
        }
        deactivateAudioSessionIfIdle()
    }

    private func startLocalMusicQueue(
        _ tracks: [LittleSpudMusicTrack],
        at index: Int
    ) {
        localMusicContinuationTask?.cancel()
        localMusicContinuationTask = nil
        localMusicContinuationPending = false
        localMusicQueue = tracks
        localMusicQueueIndex = tracks.isEmpty
            ? -1
            : max(0, min(index, tracks.count - 1))
        localMusicQueueSessionID = UUID().uuidString
        localMusicRadioName = "Little Spud Continuous Radio"
    }

    private func reportLocalMusicStarted(
        _ track: LittleSpudMusicTrack,
        session currentSession: LittleSpudSession
    ) {
        guard !currentSession.isDemo else { return }
        Task { [api] in
            try? await api.reportLocalMusicStarted(
                session: currentSession,
                provider: track.provider,
                trackID: track.id
            )
        }
    }

    private func scheduleLocalMusicContinuationIfNeeded(
        session currentSession: LittleSpudSession
    ) {
        guard usesLocalMusicPlayback, !localMusicQueue.isEmpty else { return }
        let remaining = max(0, localMusicQueue.count - localMusicQueueIndex - 1)
        guard remaining <= 2, localMusicContinuationTask == nil else { return }

        if currentSession.isDemo {
            let demoTracks = musicSnapshot.tracks.filter { candidate in
                !localMusicQueue.contains(where: { $0.id == candidate.id })
            }
            localMusicQueue.append(contentsOf: demoTracks.isEmpty ? musicSnapshot.tracks : demoTracks)
            return
        }

        if localMusicQueueIndex > 30 {
            let trimCount = localMusicQueueIndex - 2
            localMusicQueue.removeFirst(trimCount)
            localMusicQueueIndex -= trimCount
        }
        let sessionID = localMusicQueueSessionID
        let queueIDs = localMusicQueue.map(\.id)
        let currentTrackID = localMusicTrack?.id
            ?? localMusicQueue[max(0, localMusicQueueIndex)].id
        let provider = localMusicTrack?.provider
            ?? musicSnapshot.provider?.id
            ?? ""
        let index = max(0, localMusicQueueIndex)
        localMusicContinuationPending = true
        localMusicContinuationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let continuation = try await api.fetchLocalMusicContinuation(
                    session: currentSession,
                    provider: provider,
                    trackIDs: queueIDs,
                    currentTrackID: currentTrackID,
                    queueIndex: index,
                    queueSessionID: sessionID
                )
                guard !Task.isCancelled, localMusicQueueSessionID == sessionID else { return }
                let existing = Set(localMusicQueue.map(\.id))
                let uniqueTracks = continuation.tracks.filter { !existing.contains($0.id) }
                localMusicQueue.append(
                    contentsOf: uniqueTracks.isEmpty ? continuation.tracks : uniqueTracks
                )
                if !continuation.stationName.isEmpty {
                    localMusicRadioName = continuation.stationName
                }
                if musicError.hasPrefix("Continuous radio will retry:") {
                    musicError = ""
                }
            } catch {
                guard !Task.isCancelled, localMusicQueueSessionID == sessionID else { return }
                musicError = "Continuous radio will retry: \(error.localizedDescription)"
            }
            guard localMusicQueueSessionID == sessionID else { return }
            localMusicContinuationPending = false
            localMusicContinuationTask = nil
        }
    }

    private func ensureMusicTargetSelection() {
        let available = Set(musicSnapshot.targets.map(\.id))
        let validSelection = selectedMusicTargetIDs.intersection(available)
        let localSelection = validSelection.filter { id in
            musicSnapshot.targets.first(where: { $0.id == id })?.isLocal == true
        }
        if !localSelection.isEmpty {
            selectedMusicTargetIDs = Set(localSelection)
            return
        }
        let serverTargets = musicSnapshot.player.targets.filter { available.contains($0) }
        if !serverTargets.isEmpty {
            selectedMusicTargetIDs = Set(serverTargets)
            return
        }
        if !validSelection.isEmpty {
            selectedMusicTargetIDs = validSelection
            return
        }
        if let first = musicSnapshot.targets.first(where: { !$0.isLocal }) {
            selectedMusicTargetIDs = [first.id]
        } else if let local = musicSnapshot.targets.first(where: { $0.isLocal }) {
            selectedMusicTargetIDs = [local.id]
        }
    }

    private func startMusicStateSync() {
        guard activeLane == .music,
              let currentSession = session,
              !currentSession.isDemo,
              musicStateSyncTask == nil else {
            return
        }
        let client = api
        musicStateSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard self.activeLane == .music else { return }
                guard !self.musicLoading,
                      let latestSession = self.session,
                      !latestSession.isDemo else {
                    continue
                }
                do {
                    let snapshot = try await client.fetchMusic(
                        session: latestSession,
                        query: self.musicQuery,
                        refresh: false
                    )
                    guard !Task.isCancelled,
                          self.activeLane == .music,
                          !self.musicLoading,
                          self.session?.token == latestSession.token else {
                        continue
                    }
                    self.applyRemoteMusicSnapshot(snapshot)
                } catch {
                    if Task.isCancelled || self.isExpectedCancellation(error) {
                        return
                    }
                    // Foreground sync is best-effort; the manual refresh button
                    // remains responsible for surfacing connection errors.
                }
            }
        }
    }

    private func stopMusicStateSync() {
        musicStateSyncTask?.cancel()
        musicStateSyncTask = nil
    }

    /// Applies Music Core's shared player state consistently. In particular,
    /// volume is server-authoritative for speaker playback, so opening either
    /// phone after changing Tater immediately reflects the same value.
    private func applyRemoteMusicSnapshot(_ snapshot: LittleSpudMusicSnapshot) {
        musicSnapshot = snapshot
        ensureMusicTargetSelection()
        guard !usesLocalMusicPlayback else {
            syncMusicProgress()
            return
        }
        musicVolumePercent = snapshot.player.volumePercent
        syncMusicProgress()
    }

    private func syncMusicProgress() {
        musicProgressTask?.cancel()
        musicProgressTask = nil
        let localPosition = localMusicPlayer?.currentTime().seconds ?? 0
        musicProgressSeconds = usesLocalMusicPlayback
            ? (localPosition.isFinite ? max(0, localPosition) : 0)
            : max(0, musicSnapshot.player.positionSeconds)
        guard musicPlaybackStatus == "playing" else { return }
        musicProgressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                let duration = self.musicDurationSeconds
                if self.usesLocalMusicPlayback,
                   let seconds = self.localMusicPlayer?.currentTime().seconds,
                   seconds.isFinite {
                    self.musicProgressSeconds = max(0, min(duration, seconds))
                } else {
                    self.musicProgressSeconds = min(
                        duration > 0 ? duration : .greatestFiniteMagnitude,
                        self.musicProgressSeconds + 1
                    )
                    if duration > 0, self.musicProgressSeconds >= duration {
                        self.refreshMusic()
                        return
                    }
                }
            }
        }
    }

    private func configureNowPlayingCommands() {
        guard !nowPlayingCommandsConfigured else { return }
        nowPlayingCommandsConfigured = true
        let commands = MPRemoteCommandCenter.shared()

        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.localMusicStatus != "playing" else { return }
                self.toggleMusicPlayback()
            }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.localMusicStatus == "playing" else { return }
                self.toggleMusicPlayback()
            }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.toggleMusicPlayback()
            }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skipMusic(1)
            }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skipMusic(-1)
            }
            return .success
        }
        commands.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopMusic()
            }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = event.positionTime
            Task { @MainActor [weak self] in
                self?.seekMusic(to: position)
            }
            return .success
        }

        commands.skipForwardCommand.isEnabled = false
        commands.skipBackwardCommand.isEnabled = false
        setNowPlayingCommandsEnabled(false)
    }

    private func setNowPlayingCommandsEnabled(_ enabled: Bool) {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = enabled
        commands.pauseCommand.isEnabled = enabled
        commands.togglePlayPauseCommand.isEnabled = enabled
        commands.stopCommand.isEnabled = enabled
        commands.nextTrackCommand.isEnabled = enabled && musicQueue.count > 1
        commands.previousTrackCommand.isEnabled = enabled && musicQueue.count > 1
        commands.changePlaybackPositionCommand.isEnabled = enabled && musicDurationSeconds > 0
    }

    private func publishNowPlayingInfo(for track: LittleSpudMusicTrack) {
        guard localMusicPlayer != nil else { return }
        let duration = max(0, track.durationSeconds)
        let elapsed = localMusicPlayer?.currentTime().seconds ?? 0
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title.isEmpty ? "Little Spud" : track.title,
            MPMediaItemPropertyArtist: track.displayArtist.isEmpty ? musicProviderLabel : track.displayArtist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed.isFinite ? max(0, elapsed) : 0,
            MPNowPlayingInfoPropertyPlaybackRate: localMusicStatus == "playing" ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackQueueCount: musicQueue.count,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: max(0, localMusicQueueIndex),
            MPNowPlayingInfoPropertyExternalContentIdentifier: track.id,
        ]
        if let fallbackImage = UIImage(named: "LittleSpudMascot") {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                boundsSize: fallbackImage.size,
                requestHandler: { _ in fallbackImage }
            )
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        setNowPlayingCommandsEnabled(true)

        nowPlayingArtworkTask?.cancel()
        guard let artworkURL = musicArtworkURL(for: track) else { return }
        let trackID = track.id
        nowPlayingArtworkTask = Task { [weak self] in
            guard let self else { return }
            let image = await LittleSpudMusicArtworkCache.shared.image(
                for: artworkURL,
                cacheKey: musicArtworkCacheKey(for: track)
            )
            guard !Task.isCancelled,
                  let image,
                  localMusicTrack?.id == trackID
            else { return }
            var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? info
            updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                boundsSize: image.size,
                requestHandler: { _ in image }
            )
            MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
        }
    }

    private func updateNowPlayingPlaybackState(elapsedTime: Double? = nil) {
        guard localMusicPlayer != nil,
              var info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        else { return }
        let current = elapsedTime ?? localMusicPlayer?.currentTime().seconds ?? musicProgressSeconds
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = current.isFinite ? max(0, current) : 0
        info[MPNowPlayingInfoPropertyPlaybackRate] = localMusicStatus == "playing" ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyPlaybackQueueCount] = musicQueue.count
        info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = max(0, localMusicQueueIndex)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        setNowPlayingCommandsEnabled(true)
    }

    private func clearNowPlayingInfo() {
        nowPlayingArtworkTask?.cancel()
        nowPlayingArtworkTask = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        setNowPlayingCommandsEnabled(false)
    }

    func musicArtworkURL(for track: LittleSpudMusicTrack?) -> URL? {
        guard let track else { return nil }
        return resolveMusicArtworkURL(track.artworkURL)
    }

    func musicArtworkURL(for recommendation: LittleSpudMusicRecommendation) -> URL? {
        let artwork = recommendation.artworkURL.isEmpty
            ? recommendation.tracks.first?.artworkURL ?? ""
            : recommendation.artworkURL
        return resolveMusicArtworkURL(artwork)
    }

    func musicArtworkCacheKey(for track: LittleSpudMusicTrack?) -> String {
        guard let track else { return "music-artwork:empty" }
        return "music-artwork:v1:\(session?.hubUrl ?? "demo"):\(track.artworkCacheKey)"
    }

    func musicArtworkCacheKey(for recommendation: LittleSpudMusicRecommendation) -> String {
        let customArtwork = recommendation.artworkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = customArtwork.isEmpty
            ? recommendation.tracks.first?.artworkCacheKey ?? "recommendation:\(recommendation.id)"
            : "recommendation:\(recommendation.id):\(customArtwork)"
        return "music-artwork:v1:\(session?.hubUrl ?? "demo"):\(identity)"
    }

    private func resolveMusicArtworkURL(_ rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.lowercased().hasPrefix("data:") else { return nil }
        if let absolute = URL(string: value), absolute.scheme != nil {
            return absolute
        }
        guard let baseValue = session?.hubUrl, let base = URL(string: baseValue) else {
            return nil
        }
        return URL(string: value, relativeTo: base)?.absoluteURL
    }

    func refreshHome(force: Bool = false) {
        guard let currentSession = session else { return }
        if currentSession.isDemo {
            homeSnapshot = demoHomeSnapshot()
            homeError = ""
            homeLoading = false
            return
        }
        if homeTask != nil {
            return
        }
        homeLoading = true
        if force {
            homeError = ""
        }
        homeTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.homeLoading = false
                self.homeTask = nil
            }
            do {
                let snapshot = try await api.fetchHome(session: currentSession, refresh: force)
                guard !Task.isCancelled else { return }
                homeSnapshot = snapshot
                pruneHomeCameraCache(for: snapshot)
                homeError = ""
            } catch {
                guard !Task.isCancelled else { return }
                if (error as? SpudLinkAPIError)?.statusCode == 404 {
                    homeError = "Update Tater to use Little Spud Home controls."
                } else {
                    homeError = error.localizedDescription
                }
            }
        }
    }

    func toggleHomePower(roomID: String, category: LittleSpudHomeCategory) {
        let action = ["on", "mixed"].contains(category.state) ? "turn_off" : "turn_on"
        performHomeAction(roomID: roomID, category: category, action: action)
    }

    func performHomeAction(
        roomID: String,
        category: LittleSpudHomeCategory,
        action: String,
        value: Double? = nil,
        mode: String? = nil,
        temperatureUnit: String? = nil
    ) {
        guard let currentSession = session else { return }
        guard category.supports(action) else {
            homeError = "\(category.name) do not support that control."
            return
        }
        let controlKey = homeControlKey(roomID: roomID, categoryID: category.id)
        guard !homeControlsInFlight.contains(controlKey) else { return }
        if currentSession.isDemo {
            applyDemoHomeAction(
                roomID: roomID,
                categoryID: category.id,
                action: action,
                value: value,
                mode: mode,
                temperatureUnit: temperatureUnit
            )
            return
        }

        homeControlsInFlight.insert(controlKey)
        homeError = ""
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.homeControlsInFlight.remove(controlKey)
            }
            do {
                let snapshot = try await api.controlHomeCategory(
                    session: currentSession,
                    roomID: roomID,
                    categoryID: category.id,
                    action: action,
                    value: value,
                    mode: mode,
                    temperatureUnit: temperatureUnit
                )
                homeSnapshot = snapshot
                pruneHomeCameraCache(for: snapshot)
                HapticManager.shared.play("messageComplete")
            } catch {
                homeError = error.localizedDescription
            }
        }
    }

    private func homeControlKey(roomID: String, categoryID: String) -> String {
        "\(roomID)|\(categoryID)"
    }

    private func homeCameraKey(roomID: String, cameraID: String) -> String {
        "\(roomID)|\(cameraID)"
    }

    private func pruneHomeCameraCache(for snapshot: LittleSpudHomeSnapshot) {
        let validKeys = Set(
            snapshot.rooms.flatMap { room in
                (room.cameras?.cameraPreviews ?? []).map {
                    homeCameraKey(roomID: room.id, cameraID: $0.id)
                }
            }
        )
        homeCameraSnapshots = homeCameraSnapshots.filter { validKeys.contains($0.key) }
        homeCameraErrors = homeCameraErrors.filter { validKeys.contains($0.key) }
        homeCameraLoading = homeCameraLoading.intersection(validKeys)
    }

    private func demoHomeSnapshot() -> LittleSpudHomeSnapshot {
        LittleSpudHomeSnapshot(
            rooms: [
                LittleSpudHomeRoom(
                    id: "office",
                    name: "Office",
                    deviceCount: 5,
                    summary: ["All 2 lights on", "Fan on"],
                    categories: [
                        LittleSpudHomeCategory(
                            id: "light", name: "Lights", count: 2, state: "on", summary: "2 of 2 on",
                            controlType: "light", availableActions: ["turn_on", "turn_off", "set_brightness"],
                            controllable: true, readOnly: false, supportsBrightness: true, brightness: 68
                        ),
                        LittleSpudHomeCategory(
                            id: "fan", name: "Fans", count: 1, state: "on", summary: "On",
                            controlType: "power", availableActions: ["turn_on", "turn_off"],
                            controllable: true, readOnly: false, supportsBrightness: false, brightness: nil
                        ),
                        LittleSpudHomeCategory(
                            id: "climate", name: "Climate", count: 1, state: "heat", summary: "72°F · Heat",
                            controlType: "thermostat", availableActions: ["set_temperature", "set_hvac_mode"],
                            controllable: true, readOnly: false, supportsBrightness: false, brightness: nil,
                            currentTemperature: 72, targetTemperature: 70, temperatureUnit: "F",
                            hvacMode: "heat", availableHVACModes: ["off", "heat", "cool", "auto"],
                            minimumTemperature: 45, maximumTemperature: 90, temperatureStep: 1
                        ),
                        LittleSpudHomeCategory(
                            id: "temperature", name: "Temperature", count: 1, state: "72_f", summary: "72°F",
                            controlType: "read_only", availableActions: [],
                            controllable: false, readOnly: true, supportsBrightness: false, brightness: nil
                        ),
                        LittleSpudHomeCategory(
                            id: "humidity", name: "Humidity", count: 1, state: "43", summary: "43%",
                            controlType: "read_only", availableActions: [],
                            controllable: false, readOnly: true, supportsBrightness: false, brightness: nil
                        ),
                        LittleSpudHomeCategory(
                            id: "motion", name: "Motion", count: 1, state: "clear", summary: "Clear",
                            controlType: "read_only", availableActions: [],
                            controllable: false, readOnly: true, supportsBrightness: false, brightness: nil
                        )
                    ]
                ),
                LittleSpudHomeRoom(
                    id: "living_room",
                    name: "Living Room",
                    deviceCount: 4,
                    summary: ["1 of 3 lights on", "Fan off"],
                    categories: [
                        LittleSpudHomeCategory(
                            id: "light", name: "Lights", count: 3, state: "mixed", summary: "1 of 3 on",
                            controlType: "light", availableActions: ["turn_on", "turn_off", "set_brightness"],
                            controllable: true, readOnly: false, supportsBrightness: true, brightness: 42
                        ),
                        LittleSpudHomeCategory(
                            id: "fan", name: "Fans", count: 1, state: "off", summary: "Off",
                            controlType: "power", availableActions: ["turn_on", "turn_off"],
                            controllable: true, readOnly: false, supportsBrightness: false, brightness: nil
                        )
                    ]
                ),
                LittleSpudHomeRoom(
                    id: "garage",
                    name: "Garage",
                    deviceCount: 3,
                    summary: ["Garage Door closed"],
                    categories: [
                        LittleSpudHomeCategory(
                            id: "garage_door", name: "Garage Doors", count: 1, state: "closed", summary: "Closed",
                            controlType: "cover", availableActions: ["open", "close"],
                            controllable: true, readOnly: false, supportsBrightness: false, brightness: nil
                        ),
                        LittleSpudHomeCategory(
                            id: "entry_sensor", name: "Door & Window Sensors", count: 1, state: "all_closed", summary: "All closed",
                            controlType: "read_only", availableActions: [],
                            controllable: false, readOnly: true, supportsBrightness: false, brightness: nil
                        ),
                        LittleSpudHomeCategory(
                            id: "temperature", name: "Temperature", count: 1, state: "65_f", summary: "65°F",
                            controlType: "read_only", availableActions: [],
                            controllable: false, readOnly: true, supportsBrightness: false, brightness: nil
                        )
                    ]
                )
            ],
            generatedAt: Date()
        )
    }

    private func demoMusicSnapshot(query: String = "") -> LittleSpudMusicSnapshot {
        let allTracks = [
            LittleSpudMusicTrack(
                id: "demo:three-little-birds",
                title: "Three Little Birds",
                artist: "Bob Marley & The Wailers",
                albumArtist: "Bob Marley & The Wailers",
                album: "Exodus",
                genre: "Reggae",
                durationSeconds: 180,
                durationDisplay: "3:00",
                provider: "tater_tube",
                artworkURL: ""
            ),
            LittleSpudMusicTrack(
                id: "demo:blue-in-green",
                title: "Blue in Green",
                artist: "Miles Davis",
                albumArtist: "Miles Davis",
                album: "Kind of Blue",
                genre: "Jazz",
                durationSeconds: 220,
                durationDisplay: "3:40",
                provider: "tater_tube",
                artworkURL: ""
            ),
            LittleSpudMusicTrack(
                id: "demo:morning-sun",
                title: "Morning Sun",
                artist: "Little Spud Radio",
                albumArtist: "Little Spud Radio",
                album: "Wake Up",
                genre: "Chill",
                durationSeconds: 194,
                durationDisplay: "3:14",
                provider: "tater_tube",
                artworkURL: ""
            ),
        ]
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let tracks = cleanQuery.isEmpty
            ? allTracks
            : allTracks.filter {
                [$0.title, $0.artist, $0.album, $0.genre]
                    .joined(separator: " ")
                    .lowercased()
                    .contains(cleanQuery)
            }
        let provider = LittleSpudMusicProvider(
            id: "tater_tube",
            label: "Tater Tube Server",
            connected: true,
            active: true,
            localPlayback: true
        )
        return LittleSpudMusicSnapshot(
            available: true,
            provider: provider,
            providers: [provider],
            tracks: tracks,
            trackFeedKind: cleanQuery.isEmpty ? "personalized" : "search",
            trackFeedTitle: cleanQuery.isEmpty ? "For You" : "Results",
            trackFeedSummary: cleanQuery.isEmpty
                ? "Tater blended your AI picks with the artists, albums, and genres you play."
                : "",
            trackCount: allTracks.count,
            artists: ["Bob Marley & The Wailers", "Little Spud Radio", "Miles Davis"],
            albums: ["Exodus", "Kind of Blue", "Wake Up"],
            genres: ["Chill", "Jazz", "Reggae"],
            recommendations: [
                LittleSpudMusicRecommendation(
                    id: "demo:easy-morning",
                    name: "Easy Morning Roots",
                    description: "A warm Tater mix built from your recent reggae and mellow morning plays.",
                    tracks: [allTracks[0], allTracks[2]],
                    artworkURL: ""
                ),
                LittleSpudMusicRecommendation(
                    id: "demo:blue-hour",
                    name: "Blue Hour",
                    description: "Relaxed jazz and gentle tracks for the end of the day.",
                    tracks: [allTracks[1], allTracks[2]],
                    artworkURL: ""
                ),
            ],
            recommendationSummary: "Tater picks made from what you have been listening to.",
            recommendationGeneratedAt: Date(),
            targets: [
                LittleSpudMusicTarget(
                    id: "little_spud:local",
                    label: "This iPhone",
                    kind: "local"
                ),
                LittleSpudMusicTarget(
                    id: "voice_core:native:kitchen",
                    label: "Tater Satellite: Kitchen",
                    kind: "satellite"
                ),
                LittleSpudMusicTarget(
                    id: "voice_core:native:living-room",
                    label: "Tater Satellite: Living Room",
                    kind: "satellite"
                ),
            ],
            player: .idle,
            syncedAt: Date()
        )
    }

    private func applyDemoHomeAction(
        roomID: String,
        categoryID: String,
        action: String,
        value: Double?,
        mode: String?,
        temperatureUnit: String?
    ) {
        guard let roomIndex = homeSnapshot.rooms.firstIndex(where: { $0.id == roomID }),
              let categoryIndex = homeSnapshot.rooms[roomIndex].categories.firstIndex(where: { $0.id == categoryID })
        else { return }
        var room = homeSnapshot.rooms[roomIndex]
        var category = room.categories[categoryIndex]
        switch action {
        case "turn_on":
            category.state = "on"
            category.summary = category.count == 1 ? "On" : "\(category.count) of \(category.count) on"
        case "turn_off":
            category.state = "off"
            category.summary = category.count == 1 ? "Off" : "0 of \(category.count) on"
        case "set_brightness":
            let brightness = max(0, min(100, value ?? category.brightness ?? 50))
            category.brightness = brightness
            category.state = brightness > 0 ? "on" : "off"
            category.summary = category.count == 1
                ? (brightness > 0 ? "On" : "Off")
                : "\(brightness > 0 ? category.count : 0) of \(category.count) on"
        case "set_temperature":
            let minimum = category.minimumTemperature ?? (category.temperatureUnit == "C" ? 7 : 45)
            let maximum = category.maximumTemperature ?? (category.temperatureUnit == "C" ? 32 : 90)
            let reportedUnit = category.temperatureUnit == "C" ? "C" : "F"
            let requestedUnit = temperatureUnit == "C" ? "C" : "F"
            let requestedTemperature = value.map {
                convertHomeTemperature($0, from: requestedUnit, to: reportedUnit)
            }
            let temperature = max(
                minimum,
                min(
                    maximum,
                    requestedTemperature
                        ?? category.targetTemperature
                        ?? category.currentTemperature
                        ?? (reportedUnit == "C" ? 21 : 70)
                )
            )
            category.targetTemperature = temperature
            category.summary = "\(homeTemperatureText(category.currentTemperature, unit: category.temperatureUnit)) · \(category.hvacMode.replacingOccurrences(of: "_", with: " ").capitalized)"
        case "set_hvac_mode":
            guard let mode, !mode.isEmpty else { return }
            category.hvacMode = mode
            category.state = mode
            category.summary = "\(homeTemperatureText(category.currentTemperature, unit: category.temperatureUnit)) · \(mode.replacingOccurrences(of: "_", with: " ").capitalized)"
        case "open":
            category.state = "open"
            category.summary = "Open"
        case "close":
            category.state = "closed"
            category.summary = "Closed"
        case "lock":
            category.state = "locked"
            category.summary = "Locked"
        case "unlock":
            category.state = "unlocked"
            category.summary = "Unlocked"
        default:
            return
        }
        room.categories[categoryIndex] = category
        room.summary = demoRoomSummary(room.categories)
        homeSnapshot.rooms[roomIndex] = room
        homeSnapshot.generatedAt = Date()
        HapticManager.shared.play("messageComplete")
    }

    private func homeTemperatureText(_ value: Double?, unit: String) -> String {
        guard let value else { return "Temperature unavailable" }
        let rounded = value.rounded()
        let number = abs(value - rounded) < 0.05
            ? String(Int(rounded))
            : String(format: "%.1f", value)
        return "\(number)°\(unit == "C" ? "C" : "F")"
    }

    private func convertHomeTemperature(
        _ value: Double,
        from sourceUnit: String,
        to targetUnit: String
    ) -> Double {
        let source = sourceUnit == "C" ? "C" : "F"
        let target = targetUnit == "C" ? "C" : "F"
        guard source != target else { return value }
        return target == "C"
            ? (value - 32) * 5 / 9
            : value * 9 / 5 + 32
    }

    private func demoRoomSummary(_ categories: [LittleSpudHomeCategory]) -> [String] {
        categories.filter { !$0.readOnly }.prefix(3).map { category in
            if category.controlType == "light" || category.controlType == "power" {
                let label = category.count == 1 ? String(category.name.dropLast(category.name.hasSuffix("s") ? 1 : 0)) : category.name
                return "\(label) \(category.summary.lowercased())"
            }
            let label = category.count == 1 ? String(category.name.dropLast(category.name.hasSuffix("s") ? 1 : 0)) : category.name
            return "\(label) \(category.summary.lowercased())"
        }
    }

    func markNotificationsRead() {
        notificationUnreadCount = 0
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
            setDeviceNotificationsEnabled(false)
            statusText = "Device notifications paused."
            statusKind = ""
            disableRemotePushRegistration()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let granted = await LocalNotificationManager.shared.requestAuthorization()
            setDeviceNotificationsEnabled(granted)
            if granted {
                statusText = "Device notifications enabled."
                statusKind = "ok"
                requestRemoteNotifications()
                syncRemotePushRegistrationIfPossible(force: true)
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

    func handleRemotePushToken(_ token: String) {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let previous = UserDefaults.standard.string(forKey: remotePushTokenKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        UserDefaults.standard.set(clean, forKey: remotePushTokenKey)
        syncRemotePushRegistrationIfPossible(force: previous != clean)
    }

    func handleRemotePushRegistrationFailure(_ message: String?) {
        guard notificationsEnabled else { return }
        let clean = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            print("Little Spud remote notification registration failed: \(clean)")
        }
    }

    func disconnect() {
        let currentSession = session
        if notificationsEnabled {
            setDeviceNotificationsEnabled(false)
            disableRemotePushRegistration()
        } else {
            pushRegistrationTask?.cancel()
            pushRegistrationTask = nil
            clearStoredRemotePushRegistration()
        }
        pauseForegroundWork()
        homeTask?.cancel()
        homeTask = nil
        musicTask?.cancel()
        musicTask = nil
        stopLocalMusic(clearTrack: true)
        stopSpeech()
        cancelVoiceInput()
        KeychainStore.delete(account: sessionAccount)
        LittleSpudShared.clearNotificationContext()
        _ = LittleSpudShared.consumeResolvedNotifications()
        clearLocalMessages()
        session = nil
        hubConnected = false
        hubUrl = ""
        syncCode = ""
        homeSnapshot = .empty
        homeLoading = false
        homeError = ""
        homeControlsInFlight = []
        homeCameraSnapshots = [:]
        homeCameraLoading = []
        homeCameraErrors = [:]
        musicSnapshot = .empty
        musicLoading = false
        musicTransportLoading = false
        musicError = ""
        musicQuery = ""
        selectedMusicTargetIDs = []
        musicProgressSeconds = 0
        statusText = "Little Spud forgot this pairing."
        statusKind = ""

        guard let currentSession, !currentSession.isDemo else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await api.forgetPairing(session: currentSession)
            } catch {
                print("Little Spud remote forget failed: \(error.localizedDescription)")
            }
        }
    }

    private var remotePushEnvironment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }

    private func requestRemoteNotifications() {
        Task { [weak self] in
            guard let self else { return }
            let granted = await LocalNotificationManager.shared.requestAuthorization()
            guard granted else {
                setDeviceNotificationsEnabled(false)
                return
            }
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    private func setDeviceNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: notificationsKey)
    }

    private func syncRemotePushRegistrationIfPossible(force: Bool = false) {
        guard notificationsEnabled else { return }
        guard let currentSession = session, !currentSession.isDemo else { return }
        guard force || !remotePushRegistrationUnsupported else { return }
        guard let token = UserDefaults.standard.string(forKey: remotePushTokenKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            requestRemoteNotifications()
            return
        }
        let fingerprint = String(token.suffix(24))
        if pushRegistrationTask != nil {
            if pushRegistrationFingerprintInFlight == fingerprint || !force {
                return
            }
            pushRegistrationTask?.cancel()
        }
        pushRegistrationGeneration += 1
        let generation = pushRegistrationGeneration
        pushRegistrationFingerprintInFlight = fingerprint
        pushRegistrationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.pushRegistrationGeneration == generation {
                    self.pushRegistrationTask = nil
                    self.pushRegistrationFingerprintInFlight = ""
                }
            }
            do {
                var registration = loadStoredRemotePushRegistration()
                if force || registration?.tokenFingerprint != fingerprint || registration?.isComplete != true {
                    registration = try await api.registerPushGateway(
                        fcmToken: token,
                        session: currentSession,
                        environment: remotePushEnvironment
                    )
                    guard !Task.isCancelled else { return }
                    if let registration {
                        saveStoredRemotePushRegistration(registration)
                    }
                }
                guard let registration, registration.isComplete else { return }
                let updated = try await api.updatePushRegistration(
                    session: currentSession,
                    registration: registration,
                    enabled: true
                )
                guard !Task.isCancelled else { return }
                session = updated
                hubUrl = updated.hubUrl
                hubConnected = true
                saveSession()
            } catch {
                if Task.isCancelled || isExpectedCancellation(error) {
                    return
                }
                if (error as? SpudLinkAPIError)?.statusCode == 404 {
                    remotePushRegistrationUnsupported = true
                    print("Little Spud push sync skipped: paired Tater does not support push registration yet.")
                    return
                }
                print("Little Spud push sync failed: \(error.localizedDescription)")
            }
        }
    }

    private func disableRemotePushRegistration() {
        pushRegistrationTask?.cancel()
        pushRegistrationTask = nil
        guard let currentSession = session, !currentSession.isDemo else {
            clearStoredRemotePushRegistration()
            return
        }
        clearStoredRemotePushRegistration()
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await api.updatePushRegistration(session: currentSession, registration: nil, enabled: false)
            } catch {
                print("Little Spud push disable failed: \(error.localizedDescription)")
            }
        }
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
            syncRemotePushRegistrationIfPossible()
            let syncState = try await api.fetchHistoryState(session: updated)
            updateAssistantName(syncState.assistantName)
            mergeHubHistory(syncState.messages)
            mergeActiveRuns(syncState.activeRuns)
            if activeLane == .home {
                refreshHome()
            }
            if showStatus {
                statusText = "Synced with Tater."
                statusKind = "ok"
            }
        } catch {
            if Task.isCancelled || isExpectedCancellation(error) {
                return
            }
            markHubDisconnectedIfIdle()
            if showStatus {
                statusText = error.localizedDescription
                statusKind = "error"
            }
        }
    }

    private func updateAssistantName(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, var current = session, current.assistantName != clean else { return }
        current.assistantName = clean
        session = current
        saveSession()
    }

    private func beginBackgroundGracePeriod() {
        guard backgroundTaskId == .invalid else { return }
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "Little Spud Sync") { [weak self] in
            Task { @MainActor in
                self?.pollTask?.cancel()
                self?.pollTask = nil
                self?.endBackgroundGracePeriod()
            }
        }
        guard backgroundTaskId != .invalid else { return }

        backgroundGraceTask?.cancel()
        backgroundGraceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            await MainActor.run {
                guard let self else { return }
                self.pollTask?.cancel()
                self.pollTask = nil
                self.endBackgroundGracePeriod()
            }
        }
    }

    private func endBackgroundGracePeriod() {
        backgroundGraceTask?.cancel()
        backgroundGraceTask = nil
        let taskId = backgroundTaskId
        backgroundTaskId = .invalid
        if taskId != .invalid {
            UIApplication.shared.endBackgroundTask(taskId)
        }
    }

    private func startNotificationPoll() {
        guard session != nil, !isDemoMode, pollTask == nil else { return }
        let client = self.api
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let state = await MainActor.run { () -> (LittleSpudSession?, Bool) in
                    guard let self else { return (nil, false) }
                    return (self.session, self.notificationsEnabled)
                }
                guard let snapshot = state.0 else { return }
                let consumeNotification = !state.1
                do {
                    if let notification = try await client.pollNotification(session: snapshot, consume: consumeNotification) {
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            self?.hubConnected = true
                            self?.appendHubNotification(notification)
                            if !consumeNotification {
                                self?.schedulePeekedNotificationAck(notification, session: snapshot)
                            }
                        }
                        if !consumeNotification {
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                        }
                    }
                } catch {
                    if Task.isCancelled || self?.isExpectedCancellation(error) == true {
                        return
                    }
                    await MainActor.run {
                        self?.markHubDisconnectedIfIdle()
                        Task { [weak self] in
                            await self?.refreshFromHub(showStatus: false)
                        }
                    }
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
    }

    private func schedulePeekedNotificationAck(_ notification: HubNotification, session: LittleSpudSession) {
        let eventID = notification.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eventID.isEmpty, !pendingNotificationAckIDs.contains(eventID) else { return }
        pendingNotificationAckIDs.insert(eventID)
        let client = api
        Task { [weak self, client, session, eventID] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            try? await client.acknowledgeNotification(session: session, eventID: eventID)
            await MainActor.run {
                _ = self?.pendingNotificationAckIDs.remove(eventID)
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

    private func markHubDisconnectedIfIdle() {
        guard activeChatRunCount <= 0 else { return }
        hubConnected = false
    }

    private func markChatRunDetached(assistantId: String) async {
        lastStreamHapticByMessageId.removeValue(forKey: assistantId)
        if let messageIndex = messages.firstIndex(where: { $0.id == assistantId }) {
            messages[messageIndex].content = "Tater is thinking"
            messages[messageIndex].kind = "pending"
        } else {
            messages.append(LittleSpudMessage(
                id: assistantId,
                role: .assistant,
                content: "Tater is thinking",
                createdAt: Date(),
                kind: "pending"
            ))
        }
        statusText = "Tater is still working on that."
        statusKind = "ok"
        await refreshFromHub(showStatus: false)
    }

    private func isRecoverableChatDisconnect(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                NSURLErrorCancelled,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost:
                return true
            default:
                break
            }
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("timed out")
            || message.contains("cancelled")
            || message.contains("network connection was lost")
            || message.contains("offline")
            || message.contains("not connected")
    }

    private func isExpectedCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }
        return error.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "cancelled"
    }

    private func appendToolNotice(_ notice: SpudLinkToolNotice, beforeAssistantId: String) {
        let clean = notice.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let exists = messages.contains { $0.id == notice.id }
        guard !exists else { return }
        if let assistantIndex = messages.firstIndex(where: { $0.id == beforeAssistantId }) {
            let existingToolCount = messages[..<assistantIndex].reversed().prefix { message in
                message.role == .assistant && message.kind == "tool_notice"
            }.count
            let anchoredDate = messages[assistantIndex].createdAt
                .addingTimeInterval(-0.25 + (Double(existingToolCount) * 0.01))
            let message = LittleSpudMessage(
                id: notice.id,
                role: .assistant,
                content: "",
                createdAt: anchoredDate,
                kind: "tool_notice"
            )
            messages.insert(message, at: assistantIndex)
        } else {
            let message = LittleSpudMessage(
                id: notice.id,
                role: .assistant,
                content: "",
                createdAt: notice.createdAt,
                kind: "tool_notice"
            )
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

    private func appendAssistantResponseChunk(id: String, chunk: String) {
        guard !chunk.isEmpty else { return }
        guard let messageIndex = messages.firstIndex(where: { $0.id == id }) else { return }
        guard messages[messageIndex].role == .assistant else { return }

        if messages[messageIndex].kind != "streaming" {
            messages[messageIndex].content = ""
            messages[messageIndex].kind = "streaming"
        }
        messages[messageIndex].content += chunk

        let now = Date()
        let lastHaptic = lastStreamHapticByMessageId[id] ?? .distantPast
        if now.timeIntervalSince(lastHaptic) > 0.085 {
            HapticManager.shared.play("replyTick")
            lastStreamHapticByMessageId[id] = now
        }
    }

    private func completeAssistantResponse(id: String) async {
        lastStreamHapticByMessageId.removeValue(forKey: id)
        completedMessageId = id
        HapticManager.shared.play("messageComplete")
        saveMessages()
        try? await Task.sleep(nanoseconds: 420_000_000)
        if completedMessageId == id {
            completedMessageId = nil
        }
    }

    private func appendHubNotification(_ notification: HubNotification) {
        let message = LittleSpudMessage(
            id: notification.id,
            role: .system,
            content: notification.content.isEmpty ? "Notification" : notification.content,
            createdAt: notification.createdAt,
            kind: "notification",
            attachments: notification.attachments,
            notificationTitle: notification.title,
            notificationBody: notification.message,
            notificationPriority: notification.priority
        )
        appendNotificationMessage(message)
        // Remote push owns device notifications on iOS. Polling only updates chat
        // history so a pushed notification is not duplicated by a local alert.
    }

    private func mergeHubHistory(_ history: [HubHistoryMessage]) {
        guard !history.isEmpty else { return }
        var changed = false
        let newestLocalBeforeMerge = messages.map(\.createdAt).max()
        for incoming in history {
            let softDuplicate = messages.contains { existing in
                isHubHistoryDuplicate(existing: existing, incoming: incoming)
            }
            guard !messages.contains(where: { $0.id == incoming.id }) && !softDuplicate else { continue }
            if shouldSkipStaleHubHistory(incoming, newestLocalBeforeMerge: newestLocalBeforeMerge) {
                continue
            }
            if incoming.kind == "notification" {
                appendNotificationMessage(LittleSpudMessage(
                    id: incoming.id,
                    role: .system,
                    content: incoming.content,
                    createdAt: incoming.createdAt,
                    kind: "notification",
                    attachments: incoming.attachments
                ), markUnread: false)
                continue
            }
            if incoming.role == .assistant, incoming.kind != "tool_notice" {
                if reconcileIncomingAssistant(incoming) {
                    changed = true
                    continue
                }
            }
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

    private func shouldSkipStaleHubHistory(_ incoming: HubHistoryMessage, newestLocalBeforeMerge: Date?) -> Bool {
        guard let newestLocalBeforeMerge, !messages.isEmpty else { return false }
        guard incoming.createdAt < newestLocalBeforeMerge.addingTimeInterval(-2) else { return false }
        return true
    }

    private func isHubHistoryDuplicate(existing: LittleSpudMessage, incoming: HubHistoryMessage) -> Bool {
        guard existing.role == incoming.role else { return false }
        guard existing.kind != "tool_notice" || incoming.kind == "tool_notice" else { return false }

        let existingContent = existing.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let incomingContent = incoming.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard existingContent == incomingContent else { return false }

        if incoming.attachments.isEmpty && existing.attachments.isEmpty {
            return true
        }

        guard existing.role == .user else { return false }
        let existingKeys = attachmentIdentityKeys(existing.attachments)
        let incomingKeys = attachmentIdentityKeys(incoming.attachments)
        if !existingKeys.isEmpty && !incomingKeys.isEmpty && !existingKeys.isDisjoint(with: incomingKeys) {
            return true
        }

        let secondsApart = abs(existing.createdAt.timeIntervalSince(incoming.createdAt))
        return secondsApart <= 45 && (!existing.attachments.isEmpty || !incoming.attachments.isEmpty)
    }

    private func attachmentIdentityKeys(_ attachments: [LittleSpudAttachment]) -> Set<String> {
        Set(attachments.compactMap { item in
            let name = item.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let type = item.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !name.isEmpty || !type.isEmpty || item.size > 0 else { return nil }
            return "\(name)|\(type)|\(item.size)"
        })
    }

    private func mergeActiveRuns(_ activeRuns: [HubActiveRun]) {
        let running = activeRuns.filter { run in
            let status = run.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return status.isEmpty || status == "queued" || status == "running"
        }
        guard let latest = running.sorted(by: { $0.updatedAt > $1.updatedAt }).first else { return }

        let pendingText = latest.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Tater is thinking"
            : latest.text

        if let pendingIndex = messages.lastIndex(where: { message in
            message.role == .assistant && message.kind == "pending"
        }) {
            messages[pendingIndex].content = pendingText
            messages[pendingIndex].kind = "pending"
            saveMessages()
            return
        }

        let activeMessageId = "active-\(latest.id)"
        guard !messages.contains(where: { $0.id == activeMessageId }) else { return }
        messages.append(LittleSpudMessage(
            id: activeMessageId,
            role: .assistant,
            content: pendingText,
            createdAt: latest.startedAt,
            kind: "pending"
        ))
        sortAndLimitMessages()
        saveMessages()
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
        guard incoming.createdAt >= pendingMessage.createdAt.addingTimeInterval(-2) else {
            return false
        }

        if activeChatRunCount > 0 {
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

                try configureAudioSessionForVoiceInput()

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
        deactivateAudioSessionIfIdle()
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
            try configureAudioSessionForSpeechPlayback()
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
                    self.deactivateAudioSessionIfIdle()
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
        try? configureAudioSessionForSpeechPlayback()
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
                self.deactivateAudioSessionIfIdle()
            }
        }
    }

    private func stopSpeech() {
        audioPlayer?.stop()
        audioPlayer = nil
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        deactivateAudioSessionIfIdle()
    }

    private func configureAudioSessionForSpeechPlayback() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
        try audioSession.setActive(true)
    }

    private func configureAudioSessionForVoiceInput() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP, .allowBluetoothA2DP, .mixWithOthers, .duckOthers]
        )
        try audioSession.setActive(true)
    }

    private func deactivateAudioSessionIfIdle() {
        if localMusicPlayer != nil {
            let audioSession = AVAudioSession.sharedInstance()
            try? audioSession.setCategory(.playback, mode: .default)
            try? audioSession.setActive(true)
            return
        }
        guard audioPlayer == nil,
              audioEngine == nil,
              !speechSynthesizer.isSpeaking
        else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
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
        messages.sort { lhs, rhs in
            let delta = lhs.createdAt.timeIntervalSince(rhs.createdAt)
            if abs(delta) > 0.0005 {
                return delta < 0
            }
            let lhsRank = messageSortRank(lhs)
            let rhsRank = messageSortRank(rhs)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.id < rhs.id
        }
        if messages.count > 80 {
            messages = Array(messages.suffix(80))
        }
    }

    private func sortAndLimitNotifications() {
        notifications.sort {
            if $0.createdAt == $1.createdAt {
                return $0.id < $1.id
            }
            return $0.createdAt < $1.createdAt
        }
        if notifications.count > 120 {
            notifications = Array(notifications.suffix(120))
        }
    }

    private func messageSortRank(_ message: LittleSpudMessage) -> Int {
        switch message.role {
        case .user:
            return 0
        case .assistant:
            if message.kind == "tool_notice" {
                return 1
            }
            if message.kind == "pending" {
                return 2
            }
            return 3
        case .system:
            return 4
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
            if let stored, !stored.isDemo {
                saveSharedNotificationContext(for: stored)
            }
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
            if session.isDemo {
                LittleSpudShared.clearNotificationContext()
            } else {
                saveSharedNotificationContext(for: session)
            }
        } catch {
            statusText = error.localizedDescription
            statusKind = "error"
        }
    }

    private func saveSharedNotificationContext(for session: LittleSpudSession) {
        LittleSpudShared.saveNotificationContext(LittleSpudShared.NotificationContext(
            hubUrl: session.hubUrl,
            homeHubUrl: session.homeHubUrl,
            awayHubUrl: session.awayHubUrl,
            token: session.token,
            userName: session.userName,
            deviceName: session.deviceName,
            updatedAt: Date()
        ))
    }

    private func importSharedResolvedNotifications() {
        let resolved = LittleSpudShared.consumeResolvedNotifications()
        guard !resolved.isEmpty else { return }
        for item in resolved {
            let notification = HubNotification(
                id: item.id,
                title: item.title,
                message: item.message,
                createdAt: item.createdAt,
                priority: item.priority,
                attachments: (item.attachments ?? []).map { attachment in
                    LittleSpudAttachment(
                        id: attachment.id,
                        name: attachment.name,
                        type: attachment.type,
                        size: attachment.size,
                        previewUrl: attachment.url,
                        dataUrl: ""
                    )
                }
            )
            appendNotificationMessage(LittleSpudMessage(
                id: notification.id,
                role: .system,
                content: notification.content.isEmpty ? "Notification" : notification.content,
                createdAt: notification.createdAt,
                kind: "notification",
                attachments: notification.attachments,
                notificationTitle: notification.title,
                notificationBody: notification.message,
                notificationPriority: notification.priority
            ))
        }
    }

    private func appendNotificationMessage(_ message: LittleSpudMessage, markUnread: Bool = true) {
        let normalized = LittleSpudMessage(
            id: message.id,
            role: .system,
            content: message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Notification" : message.content,
            createdAt: message.createdAt,
            kind: "notification",
            attachments: message.attachments,
            notificationTitle: message.notificationTitle,
            notificationBody: message.notificationBody,
            notificationPriority: message.notificationPriority
        )
        guard mergeStoredNotificationMessage(normalized) else { return }
        sortAndLimitNotifications()
        saveNotifications()
        if markUnread && activeLane != .notifications {
            notificationUnreadCount += 1
        }
    }

    @discardableResult
    private func mergeStoredNotificationMessage(_ message: LittleSpudMessage) -> Bool {
        let exists = notifications.contains { existing in
            existing.id == message.id || (existing.kind == "notification" && existing.content == message.content)
        }
        guard !exists else { return false }
        notifications.append(message)
        return true
    }

    private func loadNotifications() {
        if let url = notificationsStoreURL(), let data = try? Data(contentsOf: url) {
            notifications = (try? JSONDecoder.littleSpud.decode([LittleSpudMessage].self, from: data)) ?? []
            sortAndLimitNotifications()
            return
        }

        guard let data = UserDefaults.standard.data(forKey: notificationMessagesKey) else { return }
        notifications = (try? JSONDecoder.littleSpud.decode([LittleSpudMessage].self, from: data)) ?? []
        sortAndLimitNotifications()
        UserDefaults.standard.removeObject(forKey: notificationMessagesKey)
        saveNotifications()
    }

    private func loadMessages() {
        if let url = messagesStoreURL(), let data = try? Data(contentsOf: url) {
            messages = (try? JSONDecoder.littleSpud.decode([LittleSpudMessage].self, from: data)) ?? []
            migrateNotificationsOutOfChatHistory()
            sortAndLimitMessages()
            return
        }

        guard let data = UserDefaults.standard.data(forKey: messagesKey) else { return }
        messages = (try? JSONDecoder.littleSpud.decode([LittleSpudMessage].self, from: data)) ?? []
        migrateNotificationsOutOfChatHistory()
        sortAndLimitMessages()
        UserDefaults.standard.removeObject(forKey: messagesKey)
        saveMessages()
    }

    private func loadStoredRemotePushRegistration() -> LittleSpudPushRegistration? {
        if let stored = try? KeychainStore.load(LittleSpudPushRegistration.self, account: remotePushRegistrationAccount) {
            return stored
        }
        guard let data = UserDefaults.standard.data(forKey: legacyRemotePushRegistrationKey),
              let legacy = try? JSONDecoder.littleSpud.decode(LittleSpudPushRegistration.self, from: data)
        else { return nil }
        saveStoredRemotePushRegistration(legacy)
        UserDefaults.standard.removeObject(forKey: legacyRemotePushRegistrationKey)
        return legacy
    }

    private func saveStoredRemotePushRegistration(_ registration: LittleSpudPushRegistration) {
        do {
            try KeychainStore.save(registration, account: remotePushRegistrationAccount)
            UserDefaults.standard.removeObject(forKey: legacyRemotePushRegistrationKey)
        } catch {
            print("Little Spud push registration save failed: \(error.localizedDescription)")
        }
    }

    private func clearStoredRemotePushRegistration() {
        KeychainStore.delete(account: remotePushRegistrationAccount)
        UserDefaults.standard.removeObject(forKey: legacyRemotePushRegistrationKey)
    }

    private func hasStoredRemotePushRegistration() -> Bool {
        loadStoredRemotePushRegistration()?.isComplete == true
    }

    private func saveMessages() {
        messages = Array(messages.suffix(80))
        guard let data = try? JSONEncoder.littleSpud.encode(messages), let url = messagesStoreURL() else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            UserDefaults.standard.removeObject(forKey: messagesKey)
        } catch {
            print("Little Spud message history save failed: \(error.localizedDescription)")
        }
    }

    private func saveNotifications() {
        notifications = Array(notifications.suffix(120))
        guard let data = try? JSONEncoder.littleSpud.encode(notifications), let url = notificationsStoreURL() else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            UserDefaults.standard.removeObject(forKey: notificationMessagesKey)
        } catch {
            print("Little Spud notification history save failed: \(error.localizedDescription)")
        }
    }

    private func migrateNotificationsOutOfChatHistory() {
        let migrated = messages.filter { $0.kind == "notification" }
        guard !migrated.isEmpty else { return }
        messages.removeAll { $0.kind == "notification" }
        var changed = false
        for message in migrated {
            changed = mergeStoredNotificationMessage(message) || changed
        }
        if changed {
            sortAndLimitNotifications()
            saveNotifications()
        }
        saveMessages()
    }

    private func clearLocalMessages() {
        messages = []
        notifications = []
        pendingAttachments = []
        draft = ""
        completedMessageId = nil
        notificationUnreadCount = 0
        activeLane = .chat
        homeSnapshot = .empty
        homeLoading = false
        homeError = ""
        homeControlsInFlight = []
        homeCameraSnapshots = [:]
        homeCameraLoading = []
        homeCameraErrors = [:]
        UserDefaults.standard.removeObject(forKey: messagesKey)
        UserDefaults.standard.removeObject(forKey: notificationMessagesKey)
        if let url = messagesStoreURL() {
            try? FileManager.default.removeItem(at: url)
        }
        if let url = notificationsStoreURL() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func messagesStoreURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base
            .appendingPathComponent("LittleSpud", isDirectory: true)
            .appendingPathComponent("messages-v1.json")
    }

    private func notificationsStoreURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base
            .appendingPathComponent("LittleSpud", isDirectory: true)
            .appendingPathComponent("notifications-v1.json")
    }
}
