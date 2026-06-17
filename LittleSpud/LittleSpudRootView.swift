import AVKit
import SwiftUI
import UIKit

struct LittleSpudRootView: View {
    @EnvironmentObject private var model: LittleSpudViewModel

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            if model.session == nil {
                PairingView()
            } else {
                ChatView()
            }
        }
        .foregroundStyle(AppTheme.text)
    }
}

private struct PairingView: View {
    @EnvironmentObject private var model: LittleSpudViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 16)

            VStack(spacing: 12) {
                Image("LittleSpudMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .accessibilityHidden(true)
                VStack(spacing: 3) {
                    Text("Little Spud")
                        .font(.system(size: 34, weight: .bold))
                    Text("Pair with Tater")
                        .font(.callout)
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 14) {
                FieldRow(title: "User Name", text: $model.userName, placeholder: "Your name")
                FieldRow(title: "Device", text: $model.deviceName, placeholder: "iPhone")
            }

            Button {
                model.showScanner = true
            } label: {
                Label(model.isPairing ? "Connecting" : "Scan QR", systemImage: model.isPairing ? "link" : "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isPairing)

            Button {
                model.startDemoMode()
            } label: {
                Label("Try Demo", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.isPairing)

            if !model.statusText.isEmpty {
                StatusLine(text: model.statusText, kind: model.statusKind)
            }

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $model.showScanner) {
            QRCodeScannerSheet { result in
                model.showScanner = false
                switch result {
                case .success(let value):
                    model.applyScannedCode(value)
                case .cancelled:
                    model.statusText = "QR scan cancelled."
                    model.statusKind = ""
                case .failure(let message):
                    model.statusText = message
                    model.statusKind = "error"
                }
            }
            .ignoresSafeArea()
        }
    }
}

private struct ChatView: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ChatHeader()
            Rectangle()
                .fill(AppTheme.line)
                .frame(height: 1)
            MessageList(composerFocused: composerFocused)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Composer(focused: $composerFocused)
                }
        }
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 1)
        }
    }
}

private struct ChatHeader: View {
    @EnvironmentObject private var model: LittleSpudViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image("LittleSpudMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)
            HeaderStatus()
            Spacer(minLength: 8)
            Button {
                model.enableNotifications()
            } label: {
                Image(systemName: model.notificationsEnabled ? "bell.fill" : "bell")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(SecondaryIconButtonStyle(active: model.notificationsEnabled))
            .accessibilityLabel("Notifications")

            Button {
                model.toggleTTS()
            } label: {
                Image(systemName: model.ttsEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(SecondaryIconButtonStyle(active: model.ttsEnabled))
            .disabled(model.session == nil)
            .accessibilityLabel(model.ttsEnabled ? "Disable TTS" : "Enable TTS")
            .accessibilityAddTraits(model.ttsEnabled ? .isSelected : [])

            Menu {
                Button(role: .destructive) {
                    model.disconnect()
                } label: {
                    Label("Forget Pairing", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(SecondaryIconButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.background)
    }
}

private struct HeaderStatus: View {
    @EnvironmentObject private var model: LittleSpudViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !model.ttsStatus.isEmpty {
                Text(model.ttsStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.ttsStatus == "TTS failed." ? AppTheme.danger : AppTheme.green)
                    .lineLimit(1)
            }
            Text(model.connectionStatusText)
                .font(.caption)
                .foregroundStyle(connectionColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectionColor: Color {
        if model.isDemoMode { return AppTheme.accent2 }
        guard model.hubConnected else { return AppTheme.danger }
        return model.connectionRoute == .away ? AppTheme.accent2 : AppTheme.green
    }
}

private struct MessageList: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    let composerFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if model.messages.isEmpty {
                        EmptyChatView()
                    }
                    ForEach(model.messages) { message in
                        MessageBubble(message: message, completed: model.completedMessageId == message.id)
                            .id(message.id)
                    }
                    if model.isTyping {
                        TypingBubble()
                            .id("typing")
                    }
                    Color.clear
                        .frame(height: 8)
                        .id("message-bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: model.messages.last?.content ?? "") { _ in
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: model.isTyping) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: composerFocused) { focused in
                scrollToBottom(proxy, animated: focused)
            }
            .onAppear {
                scrollToBottom(proxy, animated: false)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let delays: [Double] = [0, 0.05, 0.18, 0.35]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let scroll = {
                    proxy.scrollTo("message-bottom", anchor: .bottom)
                }
                if animated {
                    withAnimation(.easeOut(duration: 0.22)) {
                        scroll()
                    }
                } else {
                    scroll()
                }
            }
        }
    }
}

private struct EmptyChatView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "message.badge.waveform")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(AppTheme.accent2)
            Text("Pocket Tater, ready.")
                .font(.headline)
            Text("Messages from this device arrive at your Spud Hub with your Little Spud identity.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.muted)
                .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
    }
}

private struct MessageBubble: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    let message: LittleSpudMessage
    let completed: Bool

    private var isUser: Bool { message.role == .user }
    private var isSystem: Bool { message.role == .system }
    private var isPending: Bool { message.kind == "pending" }
    private var hasText: Bool { !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                Text(message.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                if isPending {
                    ThinkingBubbleContent()
                } else if hasText {
                    Text(message.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .foregroundStyle(isUser ? Color.white : AppTheme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(background, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(completed ? AppTheme.accent2.opacity(0.95) : Color.clear, lineWidth: 2)
                        )
                        .scaleEffect(completed ? 1.015 : 1)
                        .animation(.spring(response: 0.28, dampingFraction: 0.55), value: completed)
                }
                MediaAttachmentGrid(attachments: mediaAttachments)
            }
            .frame(maxWidth: 360, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity)
    }

    private var mediaAttachments: [LittleSpudAttachment] {
        dedupeAttachments(message.attachments + linkedMediaAttachments)
    }

    private var linkedMediaAttachments: [LittleSpudAttachment] {
        guard message.role == .assistant || message.role == .system else { return [] }
        let patterns = [
            #"https?://[^\s<>()]+"#,
            #"\]\((/[^)\s]+)\)"#
        ]
        var matches: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(message.content.startIndex..<message.content.endIndex, in: message.content)
            for match in regex.matches(in: message.content, range: range) {
                let captureIndex = match.numberOfRanges > 1 ? 1 : 0
                guard let swiftRange = Range(match.range(at: captureIndex), in: message.content) else { continue }
                matches.append(String(message.content[swiftRange]).trimmingCharacters(in: CharacterSet(charactersIn: "),.")))
            }
        }
        return matches.compactMap { mediaAttachment(from: $0) }
    }

    private func mediaAttachment(from value: String) -> LittleSpudAttachment? {
        let lower = value.lowercased()
        let type: String
        if lower.range(of: #"\.(png|jpe?g|gif|webp)(\?|#|$)"#, options: .regularExpression) != nil {
            type = "image/remote"
        } else if lower.range(of: #"\.(mp4|webm|mov)(\?|#|$)"#, options: .regularExpression) != nil {
            type = "video/remote"
        } else if lower.range(of: #"\.(mp3|wav|ogg|m4a)(\?|#|$)"#, options: .regularExpression) != nil {
            type = "audio/remote"
        } else {
            return nil
        }
        let previewURL = spudLinkMediaURL(value)
        guard !previewURL.isEmpty else { return nil }
        return LittleSpudAttachment(
            id: previewURL,
            name: URL(string: value)?.lastPathComponent.isEmpty == false ? URL(string: value)?.lastPathComponent ?? "attachment" : "attachment",
            type: type,
            size: 0,
            previewUrl: previewURL,
            dataUrl: ""
        )
    }

    private func spudLinkMediaURL(_ value: String) -> String {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        let absolute = raw.hasPrefix("/") && model.session != nil ? "\(model.session?.hubUrl ?? "")\(raw)" : raw
        guard
            var components = URLComponents(string: absolute),
            let path = components.url?.path,
            path.hasPrefix("/api/spudlink/"),
            let token = model.session?.token,
            !token.isEmpty
        else {
            return absolute
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "token" }
        queryItems.append(URLQueryItem(name: "token", value: token))
        components.queryItems = queryItems
        return components.url?.absoluteString ?? absolute
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

    private var background: Color {
        if isUser { return AppTheme.accent }
        if isSystem { return AppTheme.panel }
        if message.kind == "tool_notice" { return AppTheme.panel.opacity(0.82) }
        return AppTheme.panelRaised
    }
}

private struct MediaAttachmentGrid: View {
    let attachments: [LittleSpudAttachment]

    var body: some View {
        if !attachments.isEmpty {
            VStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    MediaAttachmentCard(attachment: attachment)
                }
            }
        }
    }
}

private enum MediaAttachmentKind: Equatable {
    case image
    case video
    case audio
    case file
}

private struct MediaAttachmentCard: View {
    let attachment: LittleSpudAttachment

    private var remoteURL: URL? {
        URL(string: attachment.previewUrl)
    }

    private var imageFromDataURL: UIImage? {
        guard attachment.dataUrl.hasPrefix("data:"), let comma = attachment.dataUrl.firstIndex(of: ",") else { return nil }
        let payload = String(attachment.dataUrl[attachment.dataUrl.index(after: comma)...])
        guard let data = Data(base64Encoded: payload) else { return nil }
        return UIImage(data: data)
    }

    private var mediaKind: MediaAttachmentKind {
        let lowerType = attachment.type.lowercased()
        if lowerType.hasPrefix("image/") { return .image }
        if lowerType.hasPrefix("video/") { return .video }
        if lowerType.hasPrefix("audio/") { return .audio }
        if attachment.dataUrl.lowercased().hasPrefix("data:image/") { return .image }
        if attachment.dataUrl.lowercased().hasPrefix("data:video/") { return .video }
        if attachment.dataUrl.lowercased().hasPrefix("data:audio/") { return .audio }

        let probe = [attachment.name, attachment.previewUrl]
            .joined(separator: " ")
            .lowercased()
        if probe.range(of: #"\.(png|jpe?g|gif|webp)(\?|#|$)"#, options: .regularExpression) != nil {
            return .image
        }
        if probe.range(of: #"\.(mp4|m4v|webm|mov)(\?|#|$)"#, options: .regularExpression) != nil {
            return .video
        }
        if probe.range(of: #"\.(mp3|wav|ogg|m4a|aac|flac)(\?|#|$)"#, options: .regularExpression) != nil {
            return .audio
        }
        return .file
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if mediaKind == .image {
                imageBody
            } else if mediaKind == .video, let remoteURL {
                InlineVideoPlayerView(url: remoteURL)
            } else if mediaKind == .audio, let remoteURL {
                InlineAudioPlayerView(
                    url: remoteURL,
                    title: attachment.displayName,
                    subtitle: [attachment.type, formattedSize].filter { !$0.isEmpty }.joined(separator: " / ")
                )
            } else {
                fileBody
            }
            if mediaKind != .audio {
                Text(attachment.displayName)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(AppTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.line, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var imageBody: some View {
        if let imageFromDataURL {
            Image(uiImage: imageFromDataURL)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let remoteURL {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    fileBody
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                @unknown default:
                    EmptyView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            fileBody
        }
    }

    @ViewBuilder
    private var fileBody: some View {
        if let remoteURL {
            Link(destination: remoteURL) {
                mediaRow
            }
        } else {
            mediaRow
        }
    }

    private var mediaRow: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(AppTheme.accent2)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)
                Text([attachment.type, formattedSize].filter { !$0.isEmpty }.joined(separator: " / "))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var iconName: String {
        if attachment.type.hasPrefix("audio/") { return "waveform" }
        if attachment.type.hasPrefix("video/") { return "play.rectangle" }
        return "doc"
    }

    private var formattedSize: String {
        guard attachment.size > 0 else { return "" }
        if attachment.size < 1024 { return "\(attachment.size) B" }
        let kb = Double(attachment.size) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}

private struct InlineVideoPlayerView: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
                .frame(maxWidth: .infinity, minHeight: 190)
            }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            configurePlayer()
        }
        .onDisappear {
            player?.pause()
        }
        .onChange(of: url) { _ in
            player?.pause()
            player = nil
            configurePlayer()
        }
    }

    private func configurePlayer() {
        guard player == nil else { return }
        player = AVPlayer(url: url)
    }
}

private struct InlineAudioPlayerView: View {
    let url: URL
    let title: String
    let subtitle: String

    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var finishObserver: NSObjectProtocol?
    @State private var isPlaying = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 38, height: 38)
                        .foregroundStyle(AppTheme.background)
                        .background(AppTheme.accent2, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause audio" : "Play audio")

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.text)
                        .lineLimit(1)
                    Text(subtitle.isEmpty ? "Audio" : subtitle)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }

            AudioWaveformView(active: isPlaying)
        }
        .padding(10)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8))
        .onAppear {
            configurePlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
        .onChange(of: url) { _ in
            cleanupPlayer()
            configurePlayer()
        }
    }

    private func togglePlayback() {
        configurePlayer()
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            return
        }

        configureAudioSession()
        player.play()
        isPlaying = true
    }

    private func configurePlayer() {
        guard player == nil else { return }
        let item = AVPlayerItem(url: url)
        let nextPlayer = AVPlayer(playerItem: item)
        player = nextPlayer
        addTimeObserver(to: nextPlayer)
        finishObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            isPlaying = false
            nextPlayer.seek(to: .zero)
        }
    }

    private func addTimeObserver(to player: AVPlayer) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { _ in
            isPlaying = player.timeControlStatus == .playing
        }
    }

    private func cleanupPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let finishObserver {
            NotificationCenter.default.removeObserver(finishObserver)
        }
        player?.pause()
        player = nil
        timeObserver = nil
        finishObserver = nil
        isPlaying = false
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            // The player can still attempt playback if the session setup fails.
        }
    }

}

private struct AudioWaveformView: View {
    let active: Bool
    @State private var animate = false

    private let heights: [CGFloat] = [7, 15, 10, 22, 13, 18, 8, 20, 12, 16, 9, 19, 11, 15]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill((active ? AppTheme.accent2 : AppTheme.muted).opacity(active ? 0.95 : 0.42))
                    .frame(
                        width: 3,
                        height: active ? (animate ? heights[index] : max(5, heights[heights.count - 1 - index] * 0.55)) : 5
                    )
                    .animation(
                        active
                            ? .easeInOut(duration: 0.42)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.035)
                            : .easeOut(duration: 0.16),
                        value: animate
                    )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .onAppear {
            animate = active
        }
        .onChange(of: active) { playing in
            animate = playing
        }
    }
}

private struct TypingBubble: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Tater")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                ThinkingBubbleContent()
            }
            .frame(maxWidth: 360, alignment: .leading)
            Spacer(minLength: 48)
        }
    }
}

private struct ThinkingBubbleContent: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 8) {
            Text("Tater is thinking")
                .font(.body)
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(AppTheme.accent2)
                        .frame(width: 5, height: 5)
                        .opacity(animate ? 1 : 0.35)
                        .animation(
                            .easeInOut(duration: 0.55)
                                .repeatForever()
                                .delay(Double(index) * 0.12),
                            value: animate
                        )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(AppTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
        .onAppear { animate = true }
    }
}

private struct Composer: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    var focused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 8) {
            if !model.speechStatus.isEmpty {
                StatusLine(text: model.speechStatus, kind: model.speechStatus == "No speech recognized." ? "" : "ok")
                    .padding(.horizontal, 4)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message your Spud Hub", text: $model.draft, axis: .vertical)
                    .focused(focused)
                    .lineLimit(1...5)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 12)
                    .background(AppTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.line, lineWidth: 1)
                    )

                Button {
                    model.toggleVoiceInput()
                } label: {
                    Image(systemName: model.isVoiceSubmitting ? "waveform" : model.isVoiceRecording ? "mic.fill" : "mic")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(SecondaryIconButtonStyle(active: model.isVoiceRecording || model.isVoiceSubmitting))
                .disabled(!model.canUseVoiceInput)
                .accessibilityLabel(model.isVoiceRecording ? "Stop voice input" : model.isVoiceSubmitting ? "Cancel voice input" : "Start voice input")
                .accessibilityAddTraits(model.isVoiceRecording || model.isVoiceSubmitting ? .isSelected : [])

                Button {
                    focused.wrappedValue = false
                    model.sendMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(SendButtonStyle(enabled: model.canSend))
                .disabled(!model.canSend)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(AppTheme.background)
    }
}

private struct FieldRow: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var keyboard: UIKeyboardType = .default
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
            TextField(placeholder, text: $text, axis: axis)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .URL ? .never : .words)
                .autocorrectionDisabled(keyboard == .URL)
                .lineLimit(axis == .vertical ? 2...5 : 1...1)
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .background(AppTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.line, lineWidth: 1)
                )
        }
    }
}

private struct StatusLine: View {
    let text: String
    let kind: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(kind == "error" ? AppTheme.danger : kind == "ok" ? AppTheme.green : AppTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(AppTheme.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SecondaryIconButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(active ? AppTheme.background : AppTheme.text)
            .background((active ? AppTheme.accent2 : AppTheme.panelRaised).opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppTheme.text)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(AppTheme.panelRaised.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.line, lineWidth: 1)
            )
    }
}

private struct SendButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? Color.white : AppTheme.muted)
            .background((enabled ? AppTheme.accent : AppTheme.panelRaised).opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}
