import AVKit
import PhotosUI
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
    @State private var navigationOpen = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                VStack(spacing: 0) {
                    ChatHeader {
                        openNavigation()
                    }
                    Rectangle()
                        .fill(AppTheme.line)
                        .frame(height: 1)
                    laneContent
                }
                .disabled(navigationOpen)
                .contentShape(Rectangle())
                .simultaneousGesture(openNavigationGesture)

                if navigationOpen {
                    Color.black.opacity(0.52)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeNavigation()
                        }
                        .transition(.opacity)
                        .zIndex(1)

                    AppNavigationDrawer(
                        onSelect: { lane in
                            model.activeLane = lane
                            closeNavigation()
                        },
                        onClose: closeNavigation
                    )
                    .frame(width: min(340, proxy.size.width * 0.86))
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .leading))
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 12, coordinateSpace: .global)
                            .onEnded { value in
                                if value.translation.width < -44,
                                   abs(value.translation.width) > abs(value.translation.height) {
                                    closeNavigation()
                                }
                            }
                    )
                    .zIndex(2)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 1)
        }
        .onChange(of: model.activeLane) { lane in
            if lane != .chat {
                composerFocused = false
            }
        }
    }

    @ViewBuilder
    private var laneContent: some View {
        switch model.activeLane {
        case .notifications:
            NotificationList()
        case .chat:
            MessageList(composerFocused: composerFocused)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Composer(focused: $composerFocused)
                }
        case .home:
            HomeRoomsView()
        case .music:
            MusicPlayerView()
        }
    }

    private func closeNavigation() {
        withAnimation(.easeOut(duration: 0.22)) {
            navigationOpen = false
        }
    }

    private func openNavigation() {
        withAnimation(.easeOut(duration: 0.22)) {
            navigationOpen = true
        }
    }

    private var openNavigationGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onEnded { value in
                guard !navigationOpen,
                      value.startLocation.x <= 64,
                      value.translation.width > 44,
                      abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }
                openNavigation()
            }
    }
}

private struct ChatHeader: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    @State private var showSettings = false
    let onOpenNavigation: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpenNavigation) {
                Image(systemName: "line.3.horizontal")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(SecondaryIconButtonStyle())
            .accessibilityLabel("Open navigation menu")

            HeaderStatus()
            Spacer(minLength: 8)
            if model.activeLane == .notifications {
                Button {
                    model.toggleNotifications()
                } label: {
                    Image(systemName: model.notificationsEnabled ? "bell.fill" : "bell")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(SecondaryIconButtonStyle(active: model.notificationsEnabled))
                .accessibilityLabel(model.notificationsEnabled ? "Disable Notifications" : "Enable Notifications")
                .accessibilityAddTraits(model.notificationsEnabled ? .isSelected : [])
            } else if model.activeLane == .home {
                Button {
                    model.refreshHome(force: true)
                } label: {
                    Group {
                        if model.homeLoading {
                            ProgressView()
                                .tint(AppTheme.text)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(SecondaryIconButtonStyle())
                .disabled(model.homeLoading)
                .accessibilityLabel("Refresh rooms")
            } else if model.activeLane == .music {
                Button {
                    model.refreshMusic(force: true)
                } label: {
                    Group {
                        if model.musicLoading {
                            ProgressView()
                                .tint(AppTheme.text)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(SecondaryIconButtonStyle())
                .disabled(model.musicLoading)
                .accessibilityLabel("Refresh music")
            } else {
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
            }

            Menu {
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Divider()
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
        .sheet(isPresented: $showSettings) {
            LittleSpudSettingsView()
                .environmentObject(model)
        }
    }
}

private struct AppNavigationDrawer: View {
    @EnvironmentObject private var model: LittleSpudViewModel

    let onSelect: (LittleSpudLane) -> Void
    let onClose: () -> Void

    private let lanes: [LittleSpudLane] = [.notifications, .chat, .home, .music]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Image("TaterLogoPrimary")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 178)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .accessibilityLabel("Tater")

                    HStack(spacing: 9) {
                        Circle()
                            .fill(model.hubConnected ? AppTheme.green : AppTheme.muted)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Little Spud")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(AppTheme.text)
                            Text(model.connectionStatusText)
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)

                    Rectangle()
                        .fill(AppTheme.line)
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)

                    ForEach(lanes, id: \.rawValue) { lane in
                        drawerButton(for: lane)
                    }

                    Spacer(minLength: 24)
                }
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(SecondaryIconButtonStyle())
            .padding(.top, 10)
            .padding(.trailing, 10)
            .accessibilityLabel("Close navigation menu")
        }
        .background(AppTheme.panel)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppTheme.line)
                .frame(width: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 20, x: 8, y: 0)
    }

    private func drawerButton(for lane: LittleSpudLane) -> some View {
        let selected = model.activeLane == lane

        return Button {
            onSelect(lane)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: laneIcon(lane))
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 24)
                Text(laneTitle(lane))
                    .font(.body.weight(selected ? .semibold : .medium))
                Spacer()
                if lane == .notifications, model.notificationUnreadCount > 0 {
                    Text(String(min(model.notificationUnreadCount, 99)))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.accent2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.accent.opacity(0.14), in: Capsule())
                }
            }
            .foregroundStyle(selected ? AppTheme.text : AppTheme.muted)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                selected ? AppTheme.accent.opacity(0.15) : Color.clear,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppTheme.accent.opacity(0.38), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func laneTitle(_ lane: LittleSpudLane) -> String {
        switch lane {
        case .notifications:
            return "Notifications"
        case .chat:
            return "Chat"
        case .home:
            return "Home"
        case .music:
            return "Music"
        }
    }

    private func laneIcon(_ lane: LittleSpudLane) -> String {
        switch lane {
        case .notifications:
            return "bell.fill"
        case .chat:
            return "bubble.left.and.bubble.right.fill"
        case .home:
            return "house.fill"
        case .music:
            return "music.note"
        }
    }
}

private struct LittleSpudSettingsView: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    @Environment(\.dismiss) private var dismiss

    private var temperatureSelection: Binding<LittleSpudTemperatureUnitPreference> {
        Binding(
            get: { model.temperatureUnitPreference },
            set: { model.setTemperatureUnitPreference($0) }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Temperature", systemImage: "thermometer.medium")
                            .font(.headline)
                        Text("Choose how Little Spud displays room temperatures, thermostat controls, and whole-home averages.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                    }

                    Picker("Temperature unit", selection: temperatureSelection) {
                        ForEach(LittleSpudTemperatureUnitPreference.allCases) { preference in
                            Text(preference.title)
                                .tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(model.temperatureUnitPreference.description)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)

                    NavigationLink {
                        TemperatureRoomLocationsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "house.and.flag.fill")
                                .foregroundStyle(AppTheme.accent2)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Inside & outside rooms")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.text)
                                Text("Choose where each temperature belongs")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.muted)
                        }
                        .padding(13)
                        .background(AppTheme.panelRaised, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(AppTheme.line, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Text("Automatic follows the thermostat's reported unit. If no thermostat is available, it follows the first current room reading.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.panelRaised, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(AppTheme.line, lineWidth: 1)
                        )
                }
                .padding(18)
            }
            .background(AppTheme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.accent2)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            model.refreshHome()
        }
    }
}

private struct TemperatureRoomLocationsView: View {
    @EnvironmentObject private var model: LittleSpudViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 11) {
                Text("Little Spud suggests a location from each room name. Tap either choice to remember your preference.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .padding(.bottom, 3)

                if model.temperatureRooms.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "thermometer.medium.slash")
                            .font(.system(size: 30))
                            .foregroundStyle(AppTheme.muted)
                        Text("No temperature rooms are available yet.")
                            .font(.subheadline.weight(.semibold))
                        Text("Refresh Home after Tater reports its rooms and sensors.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    ForEach(model.temperatureRooms) { room in
                        TemperatureRoomLocationRow(room: room)
                    }

                    if !model.temperatureRoomLocationOverrides.isEmpty {
                        Button {
                            model.resetTemperatureRoomLocations()
                        } label: {
                            Label("Reset to suggested locations", systemImage: "arrow.counterclockwise")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.accent2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
        }
        .background(AppTheme.background)
        .navigationTitle("Temperature Rooms")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct TemperatureRoomLocationRow: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    let room: LittleSpudHomeRoom

    private var location: Binding<LittleSpudTemperatureRoomLocation> {
        Binding(
            get: { model.temperatureRoomLocation(for: room) },
            set: { model.setTemperatureRoomLocation($0, roomID: room.id) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "thermometer.medium")
                    .foregroundStyle(AppTheme.green)
                Text(room.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if !model.hasTemperatureRoomLocationOverride(roomID: room.id) {
                    Text("Suggested")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                }
            }

            Picker("Room location", selection: location) {
                ForEach(LittleSpudTemperatureRoomLocation.allCases) { location in
                    Text(location.title)
                        .tag(location)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(13)
        .background(AppTheme.panelRaised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.line, lineWidth: 1)
        )
    }
}

private struct HeaderStatus: View {
    @EnvironmentObject private var model: LittleSpudViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(laneTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.text)
                .lineLimit(1)
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 7, height: 7)
                Text(model.connectionStatusText)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var laneTitle: String {
        switch model.activeLane {
        case .notifications:
            return "Notifications"
        case .home:
            return "Home"
        case .music:
            return "Music Core"
        case .chat:
            return model.assistantDisplayName
        }
    }

    private var connectionColor: Color {
        model.hubConnected ? AppTheme.green : AppTheme.muted
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
                followLatestContent(proxy)
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

    private func followLatestContent(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo("message-bottom", anchor: .bottom)
        }
    }
}

private struct NotificationList: View {
    @EnvironmentObject private var model: LittleSpudViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if model.notifications.isEmpty {
                        EmptyNotificationsView()
                    }
                    ForEach(model.notifications) { message in
                        NotificationCard(message: message)
                            .id(message.id)
                    }
                    Color.clear
                        .frame(height: 28)
                        .id("notification-bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.notifications.count) { _ in
                scrollToBottom(proxy)
            }
            .onAppear {
                model.markNotificationsRead()
                scrollToBottom(proxy, animated: false)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let delays: [Double] = [0, 0.05, 0.18]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let scroll = {
                    proxy.scrollTo("notification-bottom", anchor: .bottom)
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

private struct NotificationCard: View {
    let message: LittleSpudMessage

    private var title: String {
        let explicit = message.notificationTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicit.isEmpty {
            return explicit
        }
        guard let divider = message.content.range(of: "\n\n") else {
            return "Tater alert"
        }
        let parsed = String(message.content[..<divider.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return parsed.isEmpty ? "Tater alert" : parsed
    }

    private var bodyText: String {
        message.notificationDisplayBody
    }

    private var faceIDSummary: String? {
        message.notificationFaceIDSummary
    }

    private var faceIDAccent: Color {
        guard let faceIDSummary else { return AppTheme.accent2 }
        return faceIDSummary.localizedCaseInsensitiveContains("recognized")
            ? AppTheme.green
            : AppTheme.accent2
    }

    private var isUrgent: Bool {
        let priority = message.notificationPriority?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return ["critical", "emergency", "high", "urgent"].contains(priority)
    }

    private var accent: Color {
        isUrgent ? AppTheme.danger : AppTheme.accent2
    }

    private var timestamp: String {
        if Calendar.current.isDateInToday(message.createdAt) {
            return message.createdAt.formatted(date: .omitted, time: .shortened)
        }
        return message.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.16))
                    Image("LittleSpudMascot")
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                }
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isUrgent ? "Urgent Tater alert" : "Tater alert")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                        .textCase(.uppercase)
                        .tracking(0.65)
                    Text(timestamp)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer(minLength: 8)

                Image(systemName: isUrgent ? "exclamationmark.triangle.fill" : "bell.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(accent.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.55), AppTheme.line, Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                if !bodyText.isEmpty && bodyText != title {
                    Text(bodyText)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.text.opacity(0.88))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let faceIDSummary {
                HStack(spacing: 8) {
                    Image(
                        systemName: faceIDSummary.localizedCaseInsensitiveContains("recognized")
                            ? "person.crop.circle.badge.checkmark"
                            : "person.crop.circle.badge.questionmark"
                    )
                    .font(.system(size: 16, weight: .semibold))
                    Text(faceIDSummary)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(faceIDAccent)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(faceIDAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(faceIDAccent.opacity(0.24), lineWidth: 1)
                )
                .accessibilityLabel("Face ID: \(faceIDSummary)")
            }

            if !message.attachments.isEmpty {
                MediaAttachmentGrid(attachments: message.attachments, compact: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    accent.opacity(isUrgent ? 0.17 : 0.12),
                    AppTheme.panelRaised,
                    AppTheme.panel,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 19)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 19)
                .stroke(accent.opacity(isUrgent ? 0.52 : 0.25), lineWidth: 1)
        )
        .shadow(color: accent.opacity(0.08), radius: 12, y: 5)
        .accessibilityElement(children: .combine)
    }
}

private struct HomeOverviewContributor: Identifiable {
    let id: String
    let roomName: String
    let sourceName: String
    let reportedValue: String
    let usedValue: String
    let temperatureLocation: LittleSpudTemperatureRoomLocation?
    let included: Bool
    let controlRoomID: String?
    let controlCategoryID: String?

    init(
        id: String,
        roomName: String,
        sourceName: String,
        reportedValue: String,
        usedValue: String,
        temperatureLocation: LittleSpudTemperatureRoomLocation? = nil,
        included: Bool = true,
        controlRoomID: String? = nil,
        controlCategoryID: String? = nil
    ) {
        self.id = id
        self.roomName = roomName
        self.sourceName = sourceName
        self.reportedValue = reportedValue
        self.usedValue = usedValue
        self.temperatureLocation = temperatureLocation
        self.included = included
        self.controlRoomID = controlRoomID
        self.controlCategoryID = controlCategoryID
    }
}

private struct HomeOverviewThermostatReference: Identifiable {
    let roomID: String
    let roomName: String
    let categoryID: String

    var id: String {
        "\(roomID)-\(categoryID)"
    }
}

private struct HomeOverviewStat: Identifiable {
    let id: String
    let value: String
    let label: String
    let symbol: String
    let color: Color
    let contributors: [HomeOverviewContributor]
    let thermostats: [HomeOverviewThermostatReference]

    init(
        id: String,
        value: String,
        label: String,
        symbol: String,
        color: Color,
        contributors: [HomeOverviewContributor] = [],
        thermostats: [HomeOverviewThermostatReference] = []
    ) {
        self.id = id
        self.value = value
        self.label = label
        self.symbol = symbol
        self.color = color
        self.contributors = contributors
        self.thermostats = thermostats
    }
}

private struct HomeOverviewCard: View {
    let stats: [HomeOverviewStat]
    @State private var selectedStat: HomeOverviewStat?

    private var prioritizedStats: [HomeOverviewStat] {
        stats.enumerated().sorted { lhs, rhs in
            let lhsPriority = priority(for: lhs.element)
            let rhsPriority = priority(for: rhs.element)
            return lhsPriority == rhsPriority ? lhs.offset < rhs.offset : lhsPriority < rhsPriority
        }.map(\.element)
    }

    private var hasSafetyAlert: Bool {
        stats.contains { ["leak", "doors", "locks"].contains($0.id) }
    }

    private var hasMotion: Bool {
        stats.contains { $0.id == "motion" }
    }

    private var statusTitle: String {
        if hasSafetyAlert { return "Attention" }
        if hasMotion { return "Activity" }
        return "Live"
    }

    private var statusColor: Color {
        hasSafetyAlert ? AppTheme.danger : (hasMotion ? AppTheme.accent2 : AppTheme.green)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: "house.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Home snapshot")
                        .font(.subheadline.weight(.bold))
                    Text(hasSafetyAlert ? "Check the highlighted items" : "Live from your Tater")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusTitle)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(statusColor)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.11), in: Capsule())
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(prioritizedStats) { stat in
                    if stat.contributors.isEmpty {
                        HomeOverviewMetric(stat: stat)
                    } else {
                        Button {
                            selectedStat = stat
                        } label: {
                            HomeOverviewMetric(stat: stat, showsInfo: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows more details")
                    }
                }
            }
        }
        .padding(13)
        .background(
            LinearGradient(
                colors: [AppTheme.panelRaised, AppTheme.panel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.accent.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .sheet(item: $selectedStat) { stat in
            HomeOverviewDetailsSheet(stat: stat)
        }
    }

    private func priority(for stat: HomeOverviewStat) -> Int {
        switch stat.id {
        case "leak": return 0
        case "doors": return 1
        case "locks": return 2
        case "motion": return 3
        case "lights": return 4
        case "fans": return 5
        case let id where id.hasPrefix("temperature-"): return 6
        case "humidity": return 7
        default: return 8
        }
    }
}

private struct PillFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = proposal.width ?? .greatestFiniteMagnitude
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0
        var contentHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = rowWidth == 0 ? size.width : rowWidth + horizontalSpacing + size.width
            if rowWidth > 0 && nextWidth > availableWidth {
                contentWidth = max(contentWidth, rowWidth)
                contentHeight += rowHeight + verticalSpacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth = nextWidth
                rowHeight = max(rowHeight, size.height)
            }
        }

        contentWidth = max(contentWidth, rowWidth)
        contentHeight += rowHeight
        return CGSize(
            width: proposal.width ?? contentWidth,
            height: contentHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct HomeOverviewMetric: View {
    let stat: HomeOverviewStat
    var showsInfo = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: stat.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(stat.color)
                .frame(width: 27, height: 27)
                .background(stat.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 0) {
                Text(stat.value)
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .lineLimit(1)
                Text(stat.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if showsInfo {
                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(stat.color.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct HomeOverviewDetailsSheet: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    @Environment(\.dismiss) private var dismiss
    let stat: HomeOverviewStat

    private var liveThermostats: [(
        reference: HomeOverviewThermostatReference,
        category: LittleSpudHomeCategory
    )] {
        stat.thermostats.compactMap { reference in
            guard let room = model.homeRoom(id: reference.roomID),
                  let category = room.categories.first(where: {
                      $0.id == reference.categoryID
                          && $0.controlType == "thermostat"
                          && !$0.readOnly
                  }) else {
                return nil
            }
            return (reference, category)
        }
    }

    private var includedContributorCount: Int {
        stat.contributors.filter(\.included).count
    }

    private var liveLightsOn: Int {
        guard stat.id == "lights" else { return 0 }
        return stat.contributors.reduce(0) { total, contributor in
            guard let roomID = contributor.controlRoomID,
                  let categoryID = contributor.controlCategoryID,
                  let room = model.homeRoom(id: roomID),
                  let category = room.categories.first(where: { $0.id == categoryID }) else {
                return total
            }
            return total + homePoweredOnCount(category)
        }
    }

    private var displayValue: String {
        stat.id == "lights" ? "\(liveLightsOn)" : stat.value
    }

    private var displayLabel: String {
        guard stat.id == "lights" else { return stat.label }
        return liveLightsOn == 1 ? "light on" : "lights on"
    }

    private var selectedTemperatureTitle: String {
        stat.id == "temperature-outdoor" ? "Outside" : "Inside"
    }

    private var selectedTemperatureContributors: [HomeOverviewContributor] {
        stat.contributors.filter(\.included)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 13) {
                        Image(systemName: stat.symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(stat.color)
                            .frame(width: 48, height: 48)
                            .background(stat.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayValue)
                                .font(.system(size: 25, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text(displayLabel.capitalized)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.muted)
                        }
                    }

                    if !liveThermostats.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(liveThermostats.count == 1 ? "Thermostat" : "Thermostats")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.muted)
                                .textCase(.uppercase)
                                .tracking(0.7)
                            ForEach(liveThermostats, id: \.reference.id) { item in
                                if liveThermostats.count > 1 {
                                    Text(item.reference.roomName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.muted)
                                }
                                HomeControlCard(
                                    roomID: item.reference.roomID,
                                    category: item.category
                                )
                            }
                        }
                    }

                    Text(
                        stat.id.hasPrefix("temperature-")
                            ? "\(includedContributorCount) reading\(includedContributorCount == 1 ? "" : "s") used"
                            : "\(stat.contributors.count) contributing room\(stat.contributors.count == 1 ? "" : "s")"
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                        .textCase(.uppercase)
                        .tracking(0.7)

                    if stat.id == "lights" {
                        LazyVStack(spacing: 9) {
                            ForEach(stat.contributors) { contributor in
                                HomeOverviewLightControlRow(contributor: contributor)
                            }
                        }
                    } else if stat.id.hasPrefix("temperature-") {
                        temperatureContributorSection(
                            title: selectedTemperatureTitle,
                            contributors: selectedTemperatureContributors
                        )
                    } else {
                        LazyVStack(spacing: 9) {
                            ForEach(stat.contributors) { contributor in
                                HomeOverviewContributorRow(
                                    contributor: contributor,
                                    color: stat.color
                                )
                            }
                        }
                    }
                }
                .padding(18)
            }
            .background(Color.clear)
            .navigationTitle(displayLabel.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.accent2)
                }
            }
        }
        .background(Color.clear)
        .modifier(HomeOverviewSheetPresentation())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func temperatureContributorSection(
        title: String,
        contributors: [HomeOverviewContributor]
    ) -> some View {
        if !contributors.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                    .textCase(.uppercase)
                    .tracking(0.7)
                ForEach(contributors) { contributor in
                    HomeOverviewContributorRow(
                        contributor: contributor,
                        color: stat.color
                    )
                }
            }
        }
    }
}

private struct HomeOverviewSheetPresentation: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationBackground {
                    HomeOverviewSheetGlassBackground()
                }
                .presentationCornerRadius(30)
        } else {
            content
        }
    }
}

private struct HomeOverviewSheetGlassBackground: View {
    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(
                    .regular.tint(AppTheme.background.opacity(0.14)),
                    in: Rectangle()
                )
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(AppTheme.background.opacity(0.28))
        }
    }
}

private struct HomeOverviewLightControlRow: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    let contributor: HomeOverviewContributor
    @State private var brightnessPreview: Double?

    private var liveControl: (
        roomID: String,
        category: LittleSpudHomeCategory
    )? {
        guard let roomID = contributor.controlRoomID,
              let categoryID = contributor.controlCategoryID,
              let room = model.homeRoom(id: roomID),
              let category = room.categories.first(where: { $0.id == categoryID }) else {
            return nil
        }
        return (roomID, category)
    }

    var body: some View {
        if let control = liveControl {
            let onCount = homePoweredOnCount(control.category)
            let anyOn = onCount > 0
            let action = anyOn ? "turn_off" : "turn_on"
            let busy = model.isHomeControlInFlight(
                roomID: control.roomID,
                categoryID: control.category.id
            )
            let supportsBrightness = control.category.supportsBrightness
                && control.category.supports("set_brightness")
            let shownBrightness = brightnessPreview ?? control.category.brightness
            VStack(spacing: supportsBrightness ? 8 : 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(contributor.roomName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.text)
                        Text(contributor.sourceName)
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    Spacer(minLength: 10)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(
                            onCount == 0
                                ? "All off"
                                : "\(onCount) of \(max(onCount, control.category.count)) on"
                        )
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(anyOn ? AppTheme.accent2 : AppTheme.muted)
                        HStack(spacing: 5) {
                            if busy {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(AppTheme.accent2)
                            } else {
                                Image(systemName: "power")
                            }
                            Text(anyOn ? "Tap off" : "Tap on")
                            if supportsBrightness, let shownBrightness {
                                Text("·")
                                Image(systemName: "sun.max.fill")
                                Text("\(Int(shownBrightness.rounded()))%")
                                    .monospacedDigit()
                            }
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !busy, control.category.supports(action) else { return }
                    model.toggleHomePower(
                        roomID: control.roomID,
                        category: control.category
                    )
                }

                if supportsBrightness {
                    HStack(spacing: 9) {
                        Image(systemName: "sun.min.fill")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.muted)
                        Slider(
                            value: brightnessBinding(category: control.category),
                            in: 1...100,
                            step: 1
                        ) { editing in
                            guard !editing, let brightnessPreview else { return }
                            model.performHomeAction(
                                roomID: control.roomID,
                                category: control.category,
                                action: "set_brightness",
                                value: brightnessPreview
                            )
                        }
                        .tint(AppTheme.accent2)
                        .controlSize(.small)
                        .disabled(busy)
                        Image(systemName: "sun.max.fill")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.accent2)
                    }
                    .accessibilityLabel("\(contributor.roomName) brightness")
                    .accessibilityValue(
                        "\(Int((shownBrightness ?? 50).rounded())) percent"
                    )
                }
            }
            .padding(13)
            .background(AppTheme.panelRaised, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(anyOn ? AppTheme.accent2.opacity(0.35) : AppTheme.line, lineWidth: 1)
            )
            .onChange(of: busy) { isBusy in
                if !isBusy {
                    brightnessPreview = nil
                }
            }
            .onChange(of: control.category.brightness) { _ in
                if !busy {
                    brightnessPreview = nil
                }
            }
            .opacity(busy ? 0.72 : 1)
            .accessibilityLabel(
                "\(contributor.roomName), \(onCount) lights on, \(anyOn ? "turn all off" : "turn all on")"
            )
            .accessibilityHint(
                supportsBrightness
                    ? "Tap the room to toggle it. Use the brightness slider below to adjust it."
                    : "Tap to toggle the room."
            )
        } else {
            HomeOverviewContributorRow(
                contributor: contributor,
                color: AppTheme.accent2
            )
        }
    }

    private func brightnessBinding(
        category: LittleSpudHomeCategory
    ) -> Binding<Double> {
        Binding(
            get: {
                max(1, min(100, brightnessPreview ?? category.brightness ?? 50))
            },
            set: { value in
                brightnessPreview = max(1, min(100, value))
            }
        )
    }
}

private struct HomeOverviewContributorRow: View {
    let contributor: HomeOverviewContributor
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(contributor.roomName)
                    .font(.subheadline.weight(.semibold))
                Text(contributor.sourceName)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                if contributor.reportedValue != contributor.usedValue {
                    Text("Reported \(contributor.reportedValue)")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                }
                if !contributor.included {
                    Text("Not included in this average")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                }
            }
            Spacer(minLength: 10)
            Text(contributor.usedValue)
                .font(.headline.monospacedDigit())
                .foregroundStyle(contributor.included ? color : AppTheme.muted)
        }
        .padding(13)
        .background(AppTheme.panelRaised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.line, lineWidth: 1)
        )
        .opacity(contributor.included ? 1 : 0.68)
    }
}

private struct HomeRoomsView: View {
    @EnvironmentObject private var model: LittleSpudViewModel

    private var overviewStats: [HomeOverviewStat] {
        let outdoorRoomIDs = Set(
            model.homeRooms
                .filter { model.temperatureRoomLocation(for: $0) == .outdoor }
                .map(\.id)
        )
        return homeOverviewStats(
            model.homeRooms,
            temperaturePreference: model.temperatureUnitPreference,
            outdoorRoomIDs: outdoorRoomIDs
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !model.homeError.isEmpty {
                        HomeErrorBanner(message: model.homeError) {
                            model.refreshHome(force: true)
                        }
                    }

                    if model.homeLoading && model.homeRooms.isEmpty {
                        HomeLoadingView()
                    } else if model.homeRooms.isEmpty {
                        EmptyHomeView()
                    } else {
                        if !overviewStats.isEmpty {
                            HomeOverviewCard(stats: overviewStats)
                        }
                        ForEach(model.homeRooms) { room in
                            NavigationLink {
                                HomeRoomDetailView(roomID: room.id)
                            } label: {
                                HomeRoomCard(room: room)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Color.clear.frame(height: 28)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 18)
            }
            .background(AppTheme.background)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            model.refreshHome()
        }
    }
}

private struct HomeRoomCard: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    let room: LittleSpudHomeRoom

    private var displaySummary: [String] {
        room.summary.map { line in
            for category in room.categories where ["temperature", "climate"].contains(category.id) {
                guard let currentTemperature = category.currentTemperature else { continue }
                let prefix = "\(category.name):"
                guard line.lowercased().hasPrefix(prefix.lowercased()) else { continue }
                let displayUnit = model.temperatureUnitPreference.resolvedUnit(
                    reportedUnit: category.temperatureUnit
                )
                let temperature = homeConvertTemperature(
                    currentTemperature,
                    from: category.temperatureUnit,
                    to: displayUnit
                )
                var value = homeTemperatureDisplay(temperature, unit: displayUnit)
                if category.id == "climate", !category.hvacMode.isEmpty {
                    value += " · \(category.hvacMode.replacingOccurrences(of: "_", with: " ").capitalized)"
                }
                return "\(category.name): \(value)"
            }
            return line
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppTheme.accent.opacity(0.14))
                Image(systemName: roomIcon)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(AppTheme.accent2)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(room.name)
                        .font(.headline)
                    Text("\(room.deviceCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }
                if displaySummary.isEmpty {
                    Text("Connected devices ready")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(displaySummary.prefix(3).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.muted)
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.muted)
        }
        .padding(15)
        .background(
            LinearGradient(
                colors: [AppTheme.panelRaised, AppTheme.panel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.line, lineWidth: 1)
        )
    }

    private var roomIcon: String {
        let lower = room.name.lowercased()
        if lower.contains("garage") { return "door.garage.closed" }
        if lower.contains("bed") { return "bed.double.fill" }
        if lower.contains("kitchen") { return "fork.knife" }
        if lower.contains("office") { return "desktopcomputer" }
        if lower.contains("living") { return "sofa.fill" }
        if lower.contains("bath") { return "shower.fill" }
        return "house.fill"
    }
}

private struct HomeRoomDetailView: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    @Environment(\.dismiss) private var dismiss
    let roomID: String

    var body: some View {
        Group {
            if let room = model.homeRoom(id: roomID) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(room.name)
                                .font(.system(size: 30, weight: .bold))
                            Text("\(room.deviceCount) connected device\(room.deviceCount == 1 ? "" : "s")")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if !model.homeError.isEmpty {
                            HomeErrorBanner(message: model.homeError) {
                                model.refreshHome(force: true)
                            }
                        }

                        if !room.sensors.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("At a glance")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.muted)
                                    .textCase(.uppercase)
                                    .tracking(0.8)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(room.sensors) { sensor in
                                            HomeSensorCard(category: sensor)
                                        }
                                    }
                                }
                            }
                        }

                        if !room.controls.isEmpty || room.cameras != nil {
                            VStack(alignment: .leading, spacing: 10) {
                                if !room.controls.isEmpty {
                                    Text("Controls")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.muted)
                                        .textCase(.uppercase)
                                        .tracking(0.8)
                                }
                                ForEach(room.controls) { category in
                                    HomeControlCard(roomID: room.id, category: category)
                                }
                                if let cameras = room.cameras {
                                    HomeCameraSection(roomID: room.id, category: cameras)
                                }
                            }
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "sensor.fill")
                                    .font(.system(size: 30))
                                    .foregroundStyle(AppTheme.accent2)
                                Text("This room is read-only")
                                    .font(.headline)
                                Text("Tater is receiving device status, but no controls are available.")
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(AppTheme.muted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 18))
                        }

                        Color.clear.frame(height: 28)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
                }
                .background(AppTheme.background)
                .navigationTitle(room.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbarBackground(AppTheme.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "house.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(AppTheme.muted)
                    Text("Room no longer available")
                        .font(.headline)
                    Button("Back to rooms") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.accent2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.background)
            }
        }
    }
}

private struct HomeCameraSection: View {
    let roomID: String
    let category: LittleSpudHomeCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.accent2)
                Text(category.name)
                    .font(.headline)
                Spacer()
                Text("\(category.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }

            if category.cameraPreviews.isEmpty {
                HStack(spacing: 11) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(AppTheme.muted)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Snapshots unavailable")
                            .font(.subheadline.weight(.semibold))
                        Text("This camera integration reports status but does not provide snapshots yet.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                .padding(.vertical, 10)
            } else {
                ForEach(category.cameraPreviews) { camera in
                    HomeCameraSnapshotCard(roomID: roomID, camera: camera)
                }
            }
        }
        .padding(15)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.line, lineWidth: 1)
        )
    }
}

private struct HomeCameraSnapshotCard: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    let roomID: String
    let camera: LittleSpudCameraPreview

    private var snapshot: UIImage? {
        model.homeCameraSnapshot(roomID: roomID, cameraID: camera.id)
    }

    private var loading: Bool {
        model.isHomeCameraLoading(roomID: roomID, cameraID: camera.id)
    }

    private var error: String {
        model.homeCameraError(roomID: roomID, cameraID: camera.id)
    }

    var body: some View {
        ZStack {
            AppTheme.panelRaised

            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 8) {
                    if loading {
                        ProgressView()
                            .tint(AppTheme.accent2)
                    } else {
                        Image(systemName: error.isEmpty ? "camera.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(error.isEmpty ? AppTheme.muted : AppTheme.danger)
                    }
                    Text(error.isEmpty ? "Loading snapshot…" : "Snapshot unavailable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        Task {
                            await model.refreshHomeCameraSnapshot(roomID: roomID, cameraID: camera.id)
                        }
                    } label: {
                        Group {
                            if loading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.white)
                        .background(Color.black.opacity(0.48), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(loading)
                    .accessibilityLabel("Refresh \(camera.label) snapshot")
                }
                Spacer()
                HStack {
                    Label(camera.label, systemImage: "camera.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.52), in: Capsule())
                    Spacer()
                    if !error.isEmpty && snapshot != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.danger)
                            .padding(7)
                            .background(Color.black.opacity(0.52), in: Circle())
                            .accessibilityLabel("The last snapshot refresh failed")
                    }
                }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.line, lineWidth: 1)
        )
        .task(id: "\(roomID)|\(camera.id)") {
            while !Task.isCancelled {
                await model.refreshHomeCameraSnapshot(roomID: roomID, cameraID: camera.id)
                do {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                } catch {
                    return
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct HomeSensorCard: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    let category: LittleSpudHomeCategory

    private var displaySummary: String {
        guard category.id == "temperature",
              let currentTemperature = category.currentTemperature else {
            return category.summary
        }
        let displayUnit = model.temperatureUnitPreference.resolvedUnit(
            reportedUnit: category.temperatureUnit
        )
        return homeTemperatureDisplay(
            homeConvertTemperature(
                currentTemperature,
                from: category.temperatureUnit,
                to: displayUnit
            ),
            unit: displayUnit
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: homeCategorySymbol(category))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(homeCategoryColor(category))
                Text(category.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
            Text(displaySummary)
                .font(.headline)
                .lineLimit(1)
        }
        .frame(minWidth: 128, alignment: .leading)
        .padding(13)
        .background(AppTheme.panelRaised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.line, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct HomeControlCard: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    let roomID: String
    let category: LittleSpudHomeCategory

    private var busy: Bool {
        model.isHomeControlInFlight(roomID: roomID, categoryID: category.id)
    }

    private var displayName: String {
        category.controlType == "thermostat" ? "Thermostat" : category.name
    }

    private var displayTemperatureUnit: String {
        model.temperatureUnitPreference.resolvedUnit(reportedUnit: category.temperatureUnit)
    }

    private var displaySummary: String {
        guard category.controlType == "thermostat",
              let currentTemperature = category.currentTemperature else {
            return category.summary
        }
        let temperature = homeConvertTemperature(
            currentTemperature,
            from: category.temperatureUnit,
            to: displayTemperatureUnit
        )
        let mode = category.hvacMode
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        return [
            homeTemperatureDisplay(temperature, unit: displayTemperatureUnit),
            mode,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(homeCategoryColor(category).opacity(0.14))
                    Image(systemName: homeCategorySymbol(category))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(homeCategoryColor(category))
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.headline)
                    Text(displaySummary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 8)
                if busy {
                    ProgressView()
                        .tint(AppTheme.accent2)
                } else {
                    Text("\(category.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }
            }

            switch category.controlType {
            case "light":
                HomePowerButton(
                    isOn: category.state == "on",
                    mixed: category.state == "mixed",
                    disabled: busy || !category.supports("turn_on") || !category.supports("turn_off")
                ) {
                    model.toggleHomePower(roomID: roomID, category: category)
                }
                if category.supportsBrightness {
                    HomeBrightnessControl(roomID: roomID, category: category, disabled: busy)
                }
            case "power":
                HomePowerButton(
                    isOn: category.state == "on",
                    mixed: category.state == "mixed",
                    disabled: busy || !category.supports("turn_on") || !category.supports("turn_off")
                ) {
                    model.toggleHomePower(roomID: roomID, category: category)
                }
            case "cover":
                HStack(spacing: 10) {
                    HomeActionButton(
                        title: "Open",
                        symbol: "arrow.up",
                        selected: category.state == "open" || category.state == "opening",
                        disabled: busy || !category.supports("open")
                    ) {
                        model.performHomeAction(roomID: roomID, category: category, action: "open")
                    }
                    HomeActionButton(
                        title: "Close",
                        symbol: "arrow.down",
                        selected: category.state == "closed" || category.state == "closing",
                        disabled: busy || !category.supports("close")
                    ) {
                        model.performHomeAction(roomID: roomID, category: category, action: "close")
                    }
                }
            case "lock":
                HStack(spacing: 10) {
                    HomeActionButton(
                        title: "Lock",
                        symbol: "lock.fill",
                        selected: category.state == "locked",
                        disabled: busy || !category.supports("lock")
                    ) {
                        model.performHomeAction(roomID: roomID, category: category, action: "lock")
                    }
                    HomeActionButton(
                        title: "Unlock",
                        symbol: "lock.open.fill",
                        selected: category.state == "unlocked",
                        disabled: busy || !category.supports("unlock")
                    ) {
                        model.performHomeAction(roomID: roomID, category: category, action: "unlock")
                    }
                }
            case "thermostat":
                HomeThermostatControl(
                    roomID: roomID,
                    category: category,
                    disabled: busy,
                    displayUnit: displayTemperatureUnit
                )
                .id("\(category.id)-\(displayTemperatureUnit)")
            default:
                EmptyView()
            }
        }
        .padding(15)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.line, lineWidth: 1)
        )
    }
}

private struct HomePowerButton: View {
    let isOn: Bool
    let mixed: Bool
    let disabled: Bool
    let action: () -> Void

    private var active: Bool {
        isOn || mixed
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .bold))
                Text(active ? "Turn Off" : "Turn On")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(active ? AppTheme.background : AppTheme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(active ? AppTheme.accent2 : AppTheme.panelRaised, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(active ? Color.clear : AppTheme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }
}

private struct HomeBrightnessControl: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    let roomID: String
    let category: LittleSpudHomeCategory
    let disabled: Bool
    @State private var brightness: Double
    @State private var editing = false

    init(roomID: String, category: LittleSpudHomeCategory, disabled: Bool) {
        self.roomID = roomID
        self.category = category
        self.disabled = disabled
        _brightness = State(initialValue: category.brightness ?? 50)
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Label("Brightness", systemImage: "sun.min.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                Text("\(Int(brightness.rounded()))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(AppTheme.accent2)
            }
            Slider(value: $brightness, in: 0...100, step: 1) { editingNow in
                editing = editingNow
                if !editingNow {
                    model.performHomeAction(
                        roomID: roomID,
                        category: category,
                        action: "set_brightness",
                        value: brightness
                    )
                }
            }
            .tint(AppTheme.accent2)
            .disabled(disabled)
        }
        .onChange(of: category.brightness) { value in
            guard !editing, let value else { return }
            brightness = value
        }
    }
}

private struct HomeThermostatControl: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    let roomID: String
    let category: LittleSpudHomeCategory
    let disabled: Bool
    let displayUnit: String
    @State private var targetTemperature: Double
    @State private var selectedMode: String

    init(
        roomID: String,
        category: LittleSpudHomeCategory,
        disabled: Bool,
        displayUnit: String
    ) {
        self.roomID = roomID
        self.category = category
        self.disabled = disabled
        self.displayUnit = displayUnit
        let reportedTarget = category.targetTemperature ?? category.currentTemperature
        _targetTemperature = State(
            initialValue: reportedTarget.map {
                homeConvertTemperature(
                    $0,
                    from: category.temperatureUnit,
                    to: displayUnit
                )
            } ?? (displayUnit == "C" ? 21 : 70)
        )
        _selectedMode = State(initialValue: category.hvacMode)
    }

    private var unit: String {
        displayUnit == "C" ? "C" : "F"
    }

    private var reportedUnit: String {
        category.temperatureUnit == "C" ? "C" : "F"
    }

    private var step: Double {
        if reportedUnit != unit {
            return unit == "C" ? 0.5 : 1
        }
        return max(0.5, category.temperatureStep ?? (unit == "C" ? 0.5 : 1))
    }

    private var minimum: Double {
        guard let minimum = category.minimumTemperature else {
            return unit == "C" ? 7 : 45
        }
        return homeConvertTemperature(minimum, from: reportedUnit, to: unit)
    }

    private var maximum: Double {
        guard let maximum = category.maximumTemperature else {
            return unit == "C" ? 32 : 90
        }
        return homeConvertTemperature(maximum, from: reportedUnit, to: unit)
    }

    private var currentTemperature: Double? {
        category.currentTemperature.map {
            homeConvertTemperature($0, from: reportedUnit, to: unit)
        }
    }

    var body: some View {
        VStack(spacing: 13) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Current")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                    Text(homeTemperatureDisplay(currentTemperature, unit: unit))
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                if category.supports("set_temperature") {
                    HStack(spacing: 8) {
                        thermostatStepButton(symbol: "minus") {
                            setTarget(targetTemperature - step)
                        }
                        VStack(spacing: 1) {
                            Text("Set to")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.muted)
                            Text(homeTemperatureDisplay(targetTemperature, unit: unit))
                                .font(.headline.monospacedDigit())
                        }
                        .frame(minWidth: 62)
                        thermostatStepButton(symbol: "plus") {
                            setTarget(targetTemperature + step)
                        }
                    }
                } else if let target = category.targetTemperature {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Set to")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.muted)
                        Text(homeTemperatureDisplay(target, unit: unit))
                            .font(.headline.monospacedDigit())
                    }
                }
            }

            if category.supports("set_hvac_mode") && !category.availableHVACModes.isEmpty {
                PillFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(category.availableHVACModes, id: \.self) { mode in
                        Button {
                            selectedMode = mode
                            model.performHomeAction(
                                roomID: roomID,
                                category: category,
                                action: "set_hvac_mode",
                                mode: mode
                            )
                        } label: {
                            Label(
                                mode.replacingOccurrences(of: "_", with: " ").capitalized,
                                systemImage: homeHVACModeSymbol(mode)
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                selectedMode == mode ? AppTheme.background : AppTheme.text
                            )
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(
                                selectedMode == mode ? AppTheme.accent2 : AppTheme.panelRaised,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(
                                    selectedMode == mode ? Color.clear : AppTheme.line,
                                    lineWidth: 1
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(disabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: category.targetTemperature) { value in
            guard let value else { return }
            targetTemperature = homeConvertTemperature(
                value,
                from: reportedUnit,
                to: unit
            )
        }
        .onChange(of: category.hvacMode) { value in
            selectedMode = value
        }
    }

    private func thermostatStepButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.text)
                .frame(width: 34, height: 34)
                .background(AppTheme.panelRaised, in: Circle())
                .overlay(Circle().stroke(AppTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private func setTarget(_ value: Double) {
        let next = max(minimum, min(maximum, value))
        targetTemperature = next
        model.performHomeAction(
            roomID: roomID,
            category: category,
            action: "set_temperature",
            value: next,
            temperatureUnit: unit
        )
    }
}

private struct HomeActionButton: View {
    let title: String
    let symbol: String
    let selected: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? AppTheme.background : AppTheme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(selected ? AppTheme.accent2 : AppTheme.panelRaised, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selected ? Color.clear : AppTheme.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }
}

private struct HomeErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.danger)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: retry)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent2)
        }
        .padding(12)
        .background(AppTheme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct HomeLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(AppTheme.accent2)
            Text("Loading rooms from Tater…")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 58)
    }
}

private struct EmptyHomeView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "house.and.flag")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(AppTheme.accent2)
            Text("No rooms yet.")
                .font(.headline)
            Text("Assign rooms to devices in Tater integrations, then refresh this page.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.muted)
                .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
    }
}

private struct MusicPlayerView: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    @State private var section: MusicLibrarySection = .search
    @State private var browseSelection: MusicBrowseSelection?
    @State private var playerExpanded = false
    @State private var showsPlayers = false

    private let collapsedPlayerHeight: CGFloat = 140

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if !model.musicError.isEmpty {
                            MusicErrorBanner(message: model.musicError) {
                                model.refreshMusic(force: true)
                            }
                        }

                        if browseSelection == nil {
                            MusicLibrarySectionPicker(selection: $section)
                        }
                        MusicLibraryContent(
                            section: $section,
                            browseSelection: $browseSelection
                        )
                        Color.clear.frame(height: 12)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 18)
                    .padding(.bottom, collapsedPlayerHeight + 12)
                }
                .scrollDisabled(playerExpanded)

                MusicExpandablePlayer(
                    isExpanded: $playerExpanded,
                    openPlayers: { showsPlayers = true }
                )
                .frame(
                    height: playerExpanded
                        ? max(collapsedPlayerHeight, proxy.size.height - 8)
                        : collapsedPlayerHeight,
                    alignment: .top
                )
                .padding(.horizontal, playerExpanded ? 0 : 10)
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: playerExpanded)
            }
            .background(AppTheme.background)
        }
        .sheet(isPresented: $showsPlayers) {
            MusicPlayerDestinationSheet(isPresented: $showsPlayers)
                .environmentObject(model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            model.refreshMusic()
        }
    }
}

private struct MusicBrowseSelection: Equatable {
    let section: MusicLibrarySection
    let value: String
}

private enum MusicLibrarySection: String, CaseIterable, Identifiable {
    case search = "Search"
    case genres = "Genres"
    case artists = "Artists"
    case albums = "Albums"
    case recommendations = "Tater Picks"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .search: return "magnifyingglass"
        case .genres: return "guitars.fill"
        case .artists: return "person.2.fill"
        case .albums: return "square.stack.fill"
        case .recommendations: return "sparkles"
        }
    }
}

private struct MusicLibrarySectionPicker: View {
    @Binding var selection: MusicLibrarySection

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MusicLibrarySection.allCases) { section in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            selection = section
                        }
                    } label: {
                        Label(section.rawValue, systemImage: section.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selection == section ? AppTheme.background : AppTheme.text)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(
                                selection == section ? AppTheme.accent2 : AppTheme.panel,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(selection == section ? Color.clear : AppTheme.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MusicLibraryContent: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    @Binding var section: MusicLibrarySection
    @Binding var browseSelection: MusicBrowseSelection?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var displayedTracks: [LittleSpudMusicTrack] {
        guard let browseSelection, browseSelection.section == .albums else {
            return model.musicSnapshot.tracks
        }
        return model.musicSnapshot.tracks.filter {
            $0.album.compare(
                browseSelection.value,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
    }

    var body: some View {
        switch section {
        case .search:
            search
        case .genres:
            facetGrid(title: "Genres", values: model.musicSnapshot.genres, symbol: "guitars.fill")
        case .artists:
            facetGrid(title: "Artists", values: model.musicSnapshot.artists, symbol: "person.fill")
        case .albums:
            facetGrid(title: "Albums", values: model.musicSnapshot.albums, symbol: "square.stack.fill")
        case .recommendations:
            recommendations
        }
    }

    private var search: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let browseSelection {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            self.browseSelection = nil
                            section = browseSelection.section
                        }
                        model.clearMusicBrowse()
                    } label: {
                        Label(browseSelection.section.rawValue, systemImage: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.accent2)
                    }
                    .buttonStyle(.plain)

                    Text(browseSelection.value)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if browseSelection.section == .albums {
                        Button {
                            model.playMusicAlbum(displayedTracks)
                        } label: {
                            Label("Play Album", systemImage: "play.fill")
                                .font(.headline)
                                .foregroundStyle(AppTheme.background)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(AppTheme.accent2, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            displayedTracks.isEmpty
                                || model.musicLoading
                                || model.selectedMusicTargets.isEmpty
                        )
                        .opacity(
                            displayedTracks.isEmpty
                                || model.musicLoading
                                || model.selectedMusicTargets.isEmpty
                                ? 0.55
                                : 1
                        )
                    }
                }
                .padding(14)
                .background(AppTheme.panelRaised, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.line, lineWidth: 1))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.muted)
                    TextField("Song, artist, album, or genre", text: $model.musicQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { model.searchMusic() }
                    if !model.musicQuery.isEmpty {
                        Button {
                            model.musicQuery = ""
                            model.searchMusic()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear music search")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(AppTheme.panelRaised, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.line, lineWidth: 1))
            }

            HStack {
                Label(
                    browseSelection?.value
                        ?? (model.musicQuery.isEmpty ? model.musicSnapshot.trackFeedTitle : "Results"),
                    systemImage: browseSelection?.section.symbol
                        ?? (model.musicQuery.isEmpty
                            && model.musicSnapshot.trackFeedKind == "personalized"
                            ? "sparkles"
                            : "music.note.list")
                )
                .font(.headline)
                Spacer()
                Text("\(displayedTracks.count) tracks")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
            }

            if browseSelection == nil
                && model.musicQuery.isEmpty
                && !model.musicSnapshot.trackFeedSummary.isEmpty {
                Text(model.musicSnapshot.trackFeedSummary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            }

            if model.musicLoading && (browseSelection != nil || displayedTracks.isEmpty) {
                MusicLoadingView()
            } else if displayedTracks.isEmpty {
                MusicEmptyView()
            } else {
                ForEach(displayedTracks) { track in
                    MusicTrackRow(track: track)
                }
            }
        }
    }

    private func facetGrid(title: String, values: [String], symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(values.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
            }
            if values.isEmpty {
                MusicFacetEmptyView(title: title)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(values, id: \.self) { value in
                        Button {
                            browseSelection = MusicBrowseSelection(
                                section: section,
                                value: value
                            )
                            model.browseMusic(value)
                            section = .search
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: symbol)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent2)
                                Text(value)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.text)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(14)
                            .frame(minHeight: 92)
                            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var recommendations: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tater Recommendations")
                .font(.headline)
            if !model.musicSnapshot.recommendationSummary.isEmpty {
                Text(model.musicSnapshot.recommendationSummary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            }
            if model.musicSnapshot.recommendations.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(AppTheme.accent2)
                    Text("Your Tater picks will appear after you listen for a while.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
                .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.line, lineWidth: 1))
            } else {
                ForEach(model.musicSnapshot.recommendations) { recommendation in
                    MusicRecommendationCard(recommendation: recommendation)
                }
            }
        }
    }
}

private struct MusicFacetEmptyView: View {
    let title: String

    var body: some View {
        Text("Sync your music catalog to browse \(title.lowercased()).")
            .font(.subheadline)
            .foregroundStyle(AppTheme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct MusicRecommendationCard: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    let recommendation: LittleSpudMusicRecommendation

    var body: some View {
        HStack(spacing: 13) {
            MusicArtworkView(
                url: model.musicArtworkURL(for: recommendation),
                cacheKey: model.musicArtworkCacheKey(for: recommendation),
                size: 76,
                cornerRadius: 15,
                symbol: "sparkles"
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(recommendation.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(recommendation.description)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(2)
                Text("\(recommendation.tracks.count) tracks")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent2)
            }
            Spacer(minLength: 4)
            Button {
                model.playMusicRecommendation(recommendation)
            } label: {
                Image(systemName: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.background)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accent2, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.selectedMusicTargets.isEmpty || model.musicLoading)
        }
        .padding(13)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.line, lineWidth: 1))
    }
}

private struct MusicPersistentPlayer: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    let openQueue: () -> Void
    let openPlayers: () -> Void

    private var isPlaying: Bool {
        model.musicPlaybackStatus == "playing"
    }

    var body: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(AppTheme.muted.opacity(0.45))
                .frame(width: 34, height: 4)
                .onTapGesture(perform: openQueue)

            HStack(spacing: 10) {
                Button(action: openQueue) {
                    MusicArtworkView(
                        url: model.musicArtworkURL(for: model.musicCurrentTrack),
                        cacheKey: model.musicArtworkCacheKey(for: model.musicCurrentTrack),
                        size: 46,
                        cornerRadius: 11,
                        symbol: isPlaying ? "waveform" : "music.note"
                    )
                }
                .buttonStyle(.plain)

                Button(action: openQueue) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.musicCurrentTrack?.title ?? "Nothing playing")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.text)
                            .lineLimit(1)
                        Text(
                            model.musicCurrentTrack?.displayArtist.isEmpty == false
                                ? model.musicCurrentTrack?.displayArtist ?? ""
                                : model.musicProviderLabel
                        )
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button { model.skipMusic(-1) } label: {
                    Image(systemName: "backward.fill")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 34)
                }
                .buttonStyle(MusicTransportPressStyle())
                .foregroundStyle(AppTheme.text)
                .disabled(model.musicCurrentTrack == nil || model.musicTransportLoading)

                Button { model.toggleMusicPlayback() } label: {
                    ZStack {
                        Circle().fill(AppTheme.accent2)
                        if model.musicTransportLoading {
                            ProgressView()
                                .tint(AppTheme.background)
                                .scaleEffect(0.72)
                        } else {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(AppTheme.background)
                        }
                    }
                    .frame(width: 38, height: 38)
                }
                .buttonStyle(MusicTransportPressStyle())
                .disabled(model.musicCurrentTrack == nil || model.musicTransportLoading)
                .accessibilityLabel(model.musicTransportLoading ? "Playback command in progress" : isPlaying ? "Pause" : "Play")

                Button { model.skipMusic(1) } label: {
                    Image(systemName: "forward.fill")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 34)
                }
                .buttonStyle(MusicTransportPressStyle())
                .foregroundStyle(AppTheme.text)
                .disabled(model.musicCurrentTrack == nil || model.musicTransportLoading)

                Button(action: openQueue) {
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.muted)
                        .frame(width: 24, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show current playlist")
            }

            HStack(spacing: 10) {
                Button(action: openPlayers) {
                    Label(model.musicTargetSummary, systemImage: "hifispeaker.2.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent2)
                        .lineLimit(1)
                        .frame(maxWidth: 132, alignment: .leading)
                }
                .buttonStyle(.plain)

                Image(systemName: "speaker.fill")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
                Slider(
                    value: Binding(
                        get: { Double(model.musicVolumePercent) },
                        set: { model.setMusicVolume($0) }
                    ),
                    in: 0...100,
                    step: 1,
                    onEditingChanged: { editing in
                        if !editing { model.commitMusicVolume() }
                    }
                )
                .tint(AppTheme.accent2)
                Text("\(model.musicVolumePercent)%")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 9)
        .background(.ultraThinMaterial)
        .background(AppTheme.panel.opacity(0.82))
        .overlay(alignment: .top) {
            Rectangle().fill(AppTheme.line).frame(height: 1)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 18).onEnded { value in
                if value.translation.height < -24 { openQueue() }
            }
        )
    }
}

private struct MusicExpandablePlayer: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    @Binding var isExpanded: Bool
    let openPlayers: () -> Void

    private var isPlaying: Bool {
        model.musicPlaybackStatus == "playing"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: isExpanded ? 5 : 3) {
                Capsule()
                    .fill(AppTheme.muted.opacity(0.5))
                    .frame(width: isExpanded ? 38 : 34, height: isExpanded ? 5 : 4)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, isExpanded ? 8 : 6)
            .padding(.bottom, isExpanded ? 5 : 3)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 12).onEnded { value in
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    if value.translation.height < -20 {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            isExpanded = true
                        }
                    } else if value.translation.height > 20 {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            isExpanded = false
                        }
                    }
                }
            )
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isExpanded ? "Collapse music player" : "Expand music player")
            .accessibilityAction {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                HStack(spacing: 12) {
                    MusicArtworkView(
                        url: model.musicArtworkURL(for: model.musicCurrentTrack),
                        cacheKey: model.musicArtworkCacheKey(for: model.musicCurrentTrack),
                        size: 62,
                        cornerRadius: 13,
                        symbol: isPlaying ? "waveform" : "music.note"
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.musicCurrentTrack?.title ?? "Nothing playing")
                            .font(.headline)
                            .lineLimit(1)
                        Text(model.musicCurrentTrack?.subtitle ?? model.musicProviderLabel)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                            .lineLimit(1)
                        Button(action: openPlayers) {
                            Label(model.musicTargetSummary, systemImage: "hifispeaker.2.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.accent2)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            } else {
                HStack(spacing: 10) {
                    MusicArtworkView(
                        url: model.musicArtworkURL(for: model.musicCurrentTrack),
                        cacheKey: model.musicArtworkCacheKey(for: model.musicCurrentTrack),
                        size: 48,
                        cornerRadius: 10,
                        symbol: isPlaying ? "waveform" : "music.note"
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.musicCurrentTrack?.title ?? "Nothing playing")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(
                            model.musicCurrentTrack?.displayArtist.isEmpty == false
                                ? model.musicCurrentTrack?.displayArtist ?? ""
                                : model.musicProviderLabel
                        )
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 0) {
                        MusicTransportButton(symbol: "backward.fill", label: "Previous", size: 34) {
                            model.skipMusic(-1)
                        }
                        MusicTransportButton(
                            symbol: isPlaying ? "pause.fill" : "play.fill",
                            label: isPlaying ? "Pause" : model.musicPlaybackStatus == "paused" ? "Resume" : "Play",
                            size: 42,
                            prominent: true,
                            isLoading: model.musicTransportLoading
                        ) {
                            model.toggleMusicPlayback()
                        }
                        MusicTransportButton(symbol: "forward.fill", label: "Next", size: 34) {
                            model.skipMusic(1)
                        }
                    }
                    .disabled(model.musicCurrentTrack == nil || model.musicTransportLoading)
                    .opacity(model.musicCurrentTrack == nil ? 0.45 : 1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 2)
            }

            if isExpanded {
                HStack(spacing: 22) {
                    MusicTransportButton(symbol: "backward.fill", label: "Previous", size: 38) {
                        model.skipMusic(-1)
                    }
                    MusicTransportButton(
                        symbol: isPlaying ? "pause.fill" : "play.fill",
                        label: isPlaying ? "Pause" : model.musicPlaybackStatus == "paused" ? "Resume" : "Play",
                        size: 48,
                        prominent: true,
                        isLoading: model.musicTransportLoading
                    ) {
                        model.toggleMusicPlayback()
                    }
                    MusicTransportButton(symbol: "stop.fill", label: "Stop", size: 38) {
                        model.stopMusic()
                    }
                    MusicTransportButton(symbol: "forward.fill", label: "Next", size: 38) {
                        model.skipMusic(1)
                    }
                }
                .padding(.vertical, 5)
                .disabled(model.musicCurrentTrack == nil || model.musicTransportLoading)
                .opacity(model.musicCurrentTrack == nil ? 0.65 : 1)

                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(AppTheme.muted)
                    Slider(
                        value: Binding(
                            get: { Double(model.musicVolumePercent) },
                            set: { model.setMusicVolume($0) }
                        ),
                        in: 0...100,
                        step: 1,
                        onEditingChanged: { editing in
                            if !editing { model.commitMusicVolume() }
                        }
                    )
                    .tint(AppTheme.accent2)
                    Text("\(model.musicVolumePercent)%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            } else {
                HStack(spacing: 8) {
                    Button(action: openPlayers) {
                        Label(model.musicTargetSummary, systemImage: "hifispeaker.2.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accent2)
                            .lineLimit(1)
                            .frame(maxWidth: 116, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Image(systemName: "speaker.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                    Slider(
                        value: Binding(
                            get: { Double(model.musicVolumePercent) },
                            set: { model.setMusicVolume($0) }
                        ),
                        in: 0...100,
                        step: 1,
                        onEditingChanged: { editing in
                            if !editing { model.commitMusicVolume() }
                        }
                    )
                    .tint(AppTheme.accent2)
                    Text("\(model.musicVolumePercent)%")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 7)
            }

            if isExpanded {
                Divider().overlay(AppTheme.line)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.musicRadioName.isEmpty ? "Current Playlist" : model.musicRadioName)
                            .font(.headline)
                        Text("\(model.musicQueue.count) tracks")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    if model.musicContinuousRadio {
                        Label(
                            model.localMusicContinuationPending ? "Adding more" : "Continuous",
                            systemImage: model.localMusicContinuationPending ? "sparkles" : "infinity"
                        )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accent2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if model.musicQueue.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "music.note.list")
                            .font(.title2)
                            .foregroundStyle(AppTheme.muted)
                        Text("Choose something from your library to build a playlist.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(28)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(Array(model.musicQueue.enumerated()), id: \.offset) { index, track in
                                MusicQueueTrackRow(
                                    track: track,
                                    index: index,
                                    isCurrent: index == model.musicQueueIndex
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .modifier(MusicPlayerGlassSurface())
        .shadow(color: Color.black.opacity(0.2), radius: 16, y: -3)
    }
}

private struct MusicPlayerGlassSurface: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular
                        .tint(AppTheme.background.opacity(0.16))
                        .interactive(),
                    in: shape
                )
                .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 0.75))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(AppTheme.background.opacity(0.34), in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 0.75))
        }
    }
}

private struct MusicQueueTrackRow: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    let track: LittleSpudMusicTrack
    let index: Int
    let isCurrent: Bool

    var body: some View {
        Button {
            model.playMusicQueueTrack(at: index)
        } label: {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isCurrent ? AppTheme.accent2 : AppTheme.muted)
                    .frame(width: 24, alignment: .trailing)
                MusicArtworkView(
                    url: model.musicArtworkURL(for: track),
                    cacheKey: model.musicArtworkCacheKey(for: track),
                    size: 38,
                    cornerRadius: 9,
                    symbol: isCurrent ? "waveform" : "music.note"
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(AppTheme.text)
                        .lineLimit(1)
                    Text(track.displayArtist)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(track.durationDisplay)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(isCurrent ? AppTheme.accent.opacity(0.12) : AppTheme.panel, in: RoundedRectangle(cornerRadius: 13))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(isCurrent ? AppTheme.accent.opacity(0.5) : AppTheme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(model.musicLoading)
        .accessibilityLabel("Play \(track.title) by \(track.displayArtist)")
        .accessibilityHint(isCurrent ? "Restarts the current song" : "Skips to this song")
    }
}

private struct MusicPlayerDestinationSheet: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 9) {
                    if model.musicSnapshot.targets.isEmpty {
                        Label("No playback devices are available", systemImage: "speaker.slash")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                            .padding(.vertical, 40)
                    } else {
                        ForEach(model.musicSnapshot.targets) { target in
                            Button {
                                model.toggleMusicTarget(target.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: target.systemImage)
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.accent2)
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(target.label)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppTheme.text)
                                            .lineLimit(2)
                                        Text(target.routeSummary)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.muted)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: model.selectedMusicTargetIDs.contains(target.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(
                                            model.selectedMusicTargetIDs.contains(target.id)
                                                ? AppTheme.accent2
                                                : AppTheme.muted
                                        )
                                }
                                .padding(13)
                                .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14)
            }
            .background(AppTheme.background)
            .navigationTitle("Play on")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                        .foregroundStyle(AppTheme.accent2)
                }
            }
        }
    }
}

private struct MusicArtworkView: View {
    let url: URL?
    let cacheKey: String
    let size: CGFloat
    let cornerRadius: CGFloat
    let symbol: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if url != nil {
                ZStack {
                    placeholder
                    ProgressView().tint(AppTheme.background)
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: "\(cacheKey)|\(url?.absoluteString ?? "")") {
            image = nil
            guard let url else { return }
            image = await LittleSpudMusicArtworkCache.shared.image(
                for: url,
                cacheKey: cacheKey
            )
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.accent, AppTheme.accent2],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: symbol)
                .font(.system(size: max(14, size * 0.32), weight: .bold))
                .foregroundStyle(AppTheme.background)
        }
    }
}

private struct MusicNowPlayingCard: View {
    @EnvironmentObject private var model: LittleSpudViewModel

    private var isPlaying: Bool {
        model.musicPlaybackStatus == "playing"
    }

    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accent, AppTheme.accent2],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "music.note")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(AppTheme.background)
                }
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.musicCurrentTrack?.title ?? "Nothing playing")
                        .font(.headline)
                        .lineLimit(1)
                    Text(
                        model.musicCurrentTrack?.subtitle.isEmpty == false
                            ? model.musicCurrentTrack?.subtitle ?? ""
                            : model.musicProviderLabel
                    )
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                    if let target = model.selectedMusicTarget {
                        Label(target.label, systemImage: target.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accent2)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
            }

            HStack(spacing: 20) {
                MusicTransportButton(
                    symbol: "backward.fill",
                    label: "Previous",
                    size: 42
                ) {
                    model.skipMusic(-1)
                }

                MusicTransportButton(
                    symbol: isPlaying ? "pause.fill" : "play.fill",
                    label: isPlaying ? "Pause" : model.musicPlaybackStatus == "paused" ? "Resume" : "Play",
                    size: 54,
                    prominent: true,
                    isLoading: model.musicTransportLoading
                ) {
                    model.toggleMusicPlayback()
                }

                MusicTransportButton(
                    symbol: "stop.fill",
                    label: "Stop",
                    size: 42
                ) {
                    model.stopMusic()
                }

                MusicTransportButton(
                    symbol: "forward.fill",
                    label: "Next",
                    size: 42
                ) {
                    model.skipMusic(1)
                }
            }
            .disabled(model.musicLoading || model.musicSnapshot.targets.isEmpty)
            .opacity(model.musicSnapshot.targets.isEmpty ? 0.5 : 1)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [AppTheme.panelRaised, AppTheme.panel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppTheme.line, lineWidth: 1)
        )
    }
}

private struct MusicTransportButton: View {
    let symbol: String
    let label: String
    let size: CGFloat
    var prominent = false
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(prominent ? AppTheme.accent2 : AppTheme.panelRaised)
                if isLoading {
                    ProgressView()
                        .tint(prominent ? AppTheme.background : AppTheme.text)
                        .scaleEffect(size >= 48 ? 0.82 : 0.68)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: prominent ? 18 : 14, weight: .bold))
                        .foregroundStyle(prominent ? AppTheme.background : AppTheme.text)
                }
            }
            .frame(width: size, height: size)
            .overlay(
                Circle().stroke(prominent ? Color.clear : AppTheme.line, lineWidth: 1)
            )
        }
        .buttonStyle(MusicTransportPressStyle())
        .accessibilityLabel(isLoading ? "Playback command in progress" : label)
    }
}

private struct MusicTransportPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct MusicTrackRow: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    let track: LittleSpudMusicTrack

    private var isCurrent: Bool {
        model.musicCurrentTrack?.id == track.id
    }

    var body: some View {
        Button {
            model.playMusic(track)
        } label: {
            HStack(spacing: 12) {
                MusicArtworkView(
                    url: model.musicArtworkURL(for: track),
                    cacheKey: model.musicArtworkCacheKey(for: track),
                    size: 44,
                    cornerRadius: 11,
                    symbol: isCurrent ? "waveform" : "music.note"
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.text)
                        .lineLimit(1)
                    Text(track.subtitle.isEmpty ? track.genre : track.subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if !track.durationDisplay.isEmpty {
                    Text(track.durationDisplay)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.muted)
                }
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accent2)
            }
            .padding(12)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 15))
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(isCurrent ? AppTheme.accent.opacity(0.55) : AppTheme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(model.musicLoading || model.selectedMusicTargets.isEmpty)
    }
}

private struct MusicErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.danger)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: retry)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent2)
        }
        .padding(12)
        .background(AppTheme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct MusicLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(AppTheme.accent2)
            Text("Loading music from Tater…")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
    }
}

private struct MusicEmptyView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(AppTheme.accent2)
            Text("No music found.")
                .font(.headline)
            Text("Connect and scan a library in Music Core, or try another search.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.muted)
                .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }
}

private func homeCategorySymbol(_ category: LittleSpudHomeCategory) -> String {
    switch category.id {
    case "light":
        return category.state == "off" ? "lightbulb" : "lightbulb.fill"
    case "fan":
        return "fan.fill"
    case "switch":
        return "switch.2"
    case "plug":
        return "powerplug.fill"
    case "garage_door":
        return ["open", "opening"].contains(category.state) ? "door.garage.open" : "door.garage.closed"
    case "cover":
        return ["open", "opening"].contains(category.state) ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
    case "entry_sensor":
        return "rectangle.portrait.and.arrow.right"
    case "lock":
        return category.state == "unlocked" ? "lock.open.fill" : "lock.fill"
    case "motion":
        return "figure.walk.motion"
    case "camera":
        return "camera.fill"
    case "leak":
        return "drop.triangle.fill"
    case "climate":
        return homeHVACModeSymbol(category.hvacMode)
    case "temperature":
        return "thermometer.medium"
    case "humidity":
        return "humidity.fill"
    case "illuminance":
        return "sun.max.fill"
    case "energy":
        return "bolt.fill"
    case "battery":
        return "battery.75"
    case "media_player":
        return "speaker.wave.2.fill"
    case "presence":
        return "person.crop.circle.fill"
    case "network_device":
        return "wifi"
    default:
        return "sensor.fill"
    }
}

private func homeCategoryColor(_ category: LittleSpudHomeCategory) -> Color {
    if category.id == "leak" && ["leak_detected", "wet", "active"].contains(category.state) {
        return AppTheme.danger
    }
    if category.id == "entry_sensor" && category.summary.lowercased().contains("open") && !category.summary.lowercased().contains("all closed") {
        return AppTheme.danger
    }
    if category.id == "climate" {
        return category.hvacMode == "off" ? AppTheme.muted : AppTheme.accent2
    }
    if category.state == "on" || category.state == "open" || category.state == "unlocked" || category.state == "mixed" {
        return AppTheme.accent2
    }
    if category.readOnly {
        return AppTheme.green
    }
    return AppTheme.muted
}

private func homeHVACModeSymbol(_ mode: String) -> String {
    switch mode.lowercased() {
    case "heat", "heating":
        return "flame.fill"
    case "cool", "cooling":
        return "snowflake"
    case "auto", "automatic":
        return "a.circle.fill"
    case "off":
        return "power"
    case "fan", "fan_only":
        return "fan.fill"
    default:
        return "thermometer.medium"
    }
}

private func homeTemperatureDisplay(_ value: Double?, unit: String) -> String {
    guard let value else { return "—" }
    let rounded = value.rounded()
    let number = abs(value - rounded) < 0.05
        ? String(Int(rounded))
        : String(format: "%.1f", value)
    return "\(number)°\(unit == "C" ? "C" : "F")"
}

private func homeConvertTemperature(
    _ value: Double,
    from sourceUnit: String,
    to targetUnit: String
) -> Double {
    let source = sourceUnit.uppercased() == "C" ? "C" : "F"
    let target = targetUnit.uppercased() == "C" ? "C" : "F"
    guard source != target else { return value }
    return target == "C"
        ? (value - 32) * 5 / 9
        : value * 9 / 5 + 32
}

private func homeFirstNumber(_ text: String) -> Double? {
    let token = text.split { character in
        !(character.isNumber || character == "." || character == "-")
    }.first
    return token.flatMap { Double($0) }
}

private func homePoweredOnCount(_ category: LittleSpudHomeCategory) -> Int {
    if let onCount = category.onCount {
        return max(0, onCount)
    }
    if category.state == "on" {
        return max(1, category.count)
    }
    if category.state == "mixed" {
        return max(1, Int(homeFirstNumber(category.summary) ?? 1))
    }
    return 0
}

private func homeOpenCount(_ category: LittleSpudHomeCategory) -> Int {
    if let openCount = category.openCount {
        return max(0, openCount)
    }
    if ["open", "opening"].contains(category.state) {
        return max(1, category.count)
    }
    let summary = category.summary.lowercased()
    if summary.contains("open") && !summary.contains("closed") {
        return max(1, Int(homeFirstNumber(summary) ?? 1))
    }
    return 0
}

private func homeOverviewStats(
    _ rooms: [LittleSpudHomeRoom],
    temperaturePreference: LittleSpudTemperatureUnitPreference,
    outdoorRoomIDs: Set<String>
) -> [HomeOverviewStat] {
    var lightsOn = 0
    var fansOn = 0
    var doorsOpen = 0
    var unlocked = 0
    var leakDetected = false
    var motionDetected = false
    var lightContributors: [HomeOverviewContributor] = []
    var fanContributors: [HomeOverviewContributor] = []
    var doorContributors: [HomeOverviewContributor] = []
    var lockContributors: [HomeOverviewContributor] = []
    var leakContributors: [HomeOverviewContributor] = []
    var motionContributors: [HomeOverviewContributor] = []
    var thermostatReferences: [HomeOverviewThermostatReference] = []
    var temperatures: [(
        roomID: String,
        roomName: String,
        value: Double,
        unit: String,
        sourceName: String,
        location: LittleSpudTemperatureRoomLocation
    )] = []
    var thermostatTemperatureUnit: String?
    var humidityValues: [(
        roomID: String,
        roomName: String,
        value: Double,
        sourceName: String
    )] = []

    for room in rooms {
        for category in room.categories {
            switch category.id {
            case "light":
                let onCount = homePoweredOnCount(category)
                lightsOn += onCount
                let value = onCount == 0
                    ? "All off"
                    : "\(onCount) of \(max(onCount, category.count)) on"
                lightContributors.append(
                    HomeOverviewContributor(
                        id: "lights-\(room.id)",
                        roomName: room.name,
                        sourceName: homeCategorySourceName(category, singular: "light"),
                        reportedValue: value,
                        usedValue: value,
                        controlRoomID: room.id,
                        controlCategoryID: category.id
                    )
                )
            case "fan":
                let onCount = homePoweredOnCount(category)
                fansOn += onCount
                if onCount > 0 {
                    let value = "\(onCount) of \(max(onCount, category.count)) on"
                    fanContributors.append(
                        HomeOverviewContributor(
                            id: "fans-\(room.id)",
                            roomName: room.name,
                            sourceName: homeCategorySourceName(category, singular: "fan"),
                            reportedValue: value,
                            usedValue: value
                        )
                    )
                }
            case "garage_door", "entry_sensor":
                let openCount = homeOpenCount(category)
                doorsOpen += openCount
                if openCount > 0 {
                    let value = "\(openCount) open"
                    doorContributors.append(
                        HomeOverviewContributor(
                            id: "doors-\(room.id)-\(category.id)",
                            roomName: room.name,
                            sourceName: homeCategorySourceName(
                                category,
                                singular: category.id == "garage_door"
                                    ? "garage door"
                                    : "door/window sensor"
                            ),
                            reportedValue: value,
                            usedValue: value
                        )
                    )
                }
            case "lock":
                let unlockedCount: Int
                if category.state == "unlocked" {
                    unlockedCount = max(1, category.count)
                } else if category.state == "mixed" {
                    unlockedCount = max(1, Int(homeFirstNumber(category.summary) ?? 1))
                } else {
                    unlockedCount = 0
                }
                unlocked += unlockedCount
                if unlockedCount > 0 {
                    let value = "\(unlockedCount) unlocked"
                    lockContributors.append(
                        HomeOverviewContributor(
                            id: "locks-\(room.id)",
                            roomName: room.name,
                            sourceName: homeCategorySourceName(category, singular: "lock"),
                            reportedValue: value,
                            usedValue: value
                        )
                    )
                }
            case "leak":
                let value = category.summary.lowercased()
                let active = value.contains("leak detected") || ["wet", "active"].contains(category.state)
                leakDetected = leakDetected || active
                if active {
                    leakContributors.append(
                        HomeOverviewContributor(
                            id: "leak-\(room.id)",
                            roomName: room.name,
                            sourceName: homeCategorySourceName(category, singular: "leak sensor"),
                            reportedValue: "Alert",
                            usedValue: "Alert"
                        )
                    )
                }
            case "motion":
                let active = category.summary.lowercased().contains("motion detected")
                motionDetected = motionDetected || active
                if active {
                    motionContributors.append(
                        HomeOverviewContributor(
                            id: "motion-\(room.id)",
                            roomName: room.name,
                            sourceName: homeCategorySourceName(category, singular: "motion sensor"),
                            reportedValue: "Active",
                            usedValue: "Active"
                        )
                    )
                }
            default:
                break
            }
        }

        if let temperature = room.categories.first(where: { $0.id == "temperature" }),
           let value = temperature.currentTemperature {
            temperatures.append(
                (
                    room.id,
                    room.name,
                    value,
                    temperature.temperatureUnit,
                    homeMeasurementSourceName(temperature, measurement: "temperature"),
                    outdoorRoomIDs.contains(room.id) ? .outdoor : .indoor
                )
            )
        } else if let climate = room.categories.first(where: { $0.id == "climate" }),
                  let value = climate.currentTemperature {
            temperatures.append(
                (
                    room.id,
                    room.name,
                    value,
                    climate.temperatureUnit,
                    "Thermostat",
                    outdoorRoomIDs.contains(room.id) ? .outdoor : .indoor
                )
            )
        }
        if thermostatTemperatureUnit == nil,
           let climate = room.categories.first(where: { $0.id == "climate" }),
           climate.currentTemperature != nil {
            thermostatTemperatureUnit = climate.temperatureUnit
        }
        if let climate = room.categories.first(where: {
            $0.id == "climate"
                && $0.controlType == "thermostat"
                && !$0.readOnly
        }) {
            thermostatReferences.append(
                HomeOverviewThermostatReference(
                    roomID: room.id,
                    roomName: room.name,
                    categoryID: climate.id
                )
            )
        }

        if let humidity = room.categories.first(where: { $0.id == "humidity" }),
           let value = homeFirstNumber(humidity.summary) {
            humidityValues.append(
                (
                    room.id,
                    room.name,
                    value,
                    homeMeasurementSourceName(humidity, measurement: "humidity")
                )
            )
        }
    }

    var stats: [HomeOverviewStat] = []
    if leakDetected {
        stats.append(HomeOverviewStat(id: "leak", value: "Alert", label: "leak detected", symbol: "drop.triangle.fill", color: AppTheme.danger, contributors: leakContributors))
    }
    if doorsOpen > 0 {
        stats.append(HomeOverviewStat(id: "doors", value: "\(doorsOpen)", label: doorsOpen == 1 ? "door open" : "doors open", symbol: "door.left.hand.open", color: AppTheme.danger, contributors: doorContributors))
    }
    if unlocked > 0 {
        stats.append(HomeOverviewStat(id: "locks", value: "\(unlocked)", label: unlocked == 1 ? "door unlocked" : "doors unlocked", symbol: "lock.open.fill", color: AppTheme.danger, contributors: lockContributors))
    }
    if lightsOn > 0 {
        stats.append(HomeOverviewStat(id: "lights", value: "\(lightsOn)", label: lightsOn == 1 ? "light on" : "lights on", symbol: "lightbulb.fill", color: AppTheme.accent2, contributors: lightContributors))
    }
    if fansOn > 0 {
        stats.append(HomeOverviewStat(id: "fans", value: "\(fansOn)", label: fansOn == 1 ? "fan on" : "fans on", symbol: "fan.fill", color: AppTheme.accent2, contributors: fanContributors))
    }
    if motionDetected {
        stats.append(HomeOverviewStat(id: "motion", value: "Active", label: "motion detected", symbol: "figure.walk.motion", color: AppTheme.accent2, contributors: motionContributors))
    }
    if let firstTemperature = temperatures.first {
        let automaticUnit = thermostatTemperatureUnit == "C"
            ? "C"
            : thermostatTemperatureUnit == "F"
                ? "F"
                : (firstTemperature.unit == "C" ? "C" : "F")
        let targetUnit = temperaturePreference.resolvedUnit(reportedUnit: automaticUnit)
        for location in LittleSpudTemperatureRoomLocation.allCases {
            let includedTemperatures = temperatures.filter {
                $0.location == location
            }
            guard !includedTemperatures.isEmpty else { continue }

            let converted = includedTemperatures.map { reading in
                homeConvertTemperature(
                    reading.value,
                    from: reading.unit,
                    to: targetUnit
                )
            }
            let average = converted.reduce(0, +) / Double(converted.count)
            let contributors = temperatures.map { reading in
                let usedValue = homeConvertTemperature(
                    reading.value,
                    from: reading.unit,
                    to: targetUnit
                )
                return HomeOverviewContributor(
                    id: "temperature-\(reading.roomID)",
                    roomName: reading.roomName,
                    sourceName: reading.sourceName,
                    reportedValue: homeTemperatureDisplay(
                        reading.value,
                        unit: reading.unit
                    ),
                    usedValue: homeTemperatureDisplay(
                        usedValue,
                        unit: targetUnit
                    ),
                    temperatureLocation: reading.location,
                    included: reading.location == location
                )
            }
            stats.append(
                HomeOverviewStat(
                    id: "temperature-\(location.rawValue)",
                    value: homeTemperatureDisplay(average, unit: targetUnit),
                    label: location == .indoor ? "inside average" : "outside average",
                    symbol: location == .indoor ? "house.fill" : "sun.max.fill",
                    color: location == .indoor ? AppTheme.green : AppTheme.accent2,
                    contributors: contributors,
                    thermostats: location == .indoor ? thermostatReferences : []
                )
            )
        }
    }
    if !humidityValues.isEmpty {
        let average = humidityValues.map { $0.value }.reduce(0, +) / Double(humidityValues.count)
        let contributors = humidityValues.map { reading in
            let value = "\(Int(reading.value.rounded()))%"
            return HomeOverviewContributor(
                id: "humidity-\(reading.roomID)",
                roomName: reading.roomName,
                sourceName: reading.sourceName,
                reportedValue: value,
                usedValue: value
            )
        }
        stats.append(
            HomeOverviewStat(
                id: "humidity",
                value: "\(Int(average.rounded()))%",
                label: "average humidity",
                symbol: "humidity.fill",
                color: AppTheme.green,
                contributors: contributors
            )
        )
    }
    return stats
}

private func homeMeasurementSourceName(
    _ category: LittleSpudHomeCategory,
    measurement: String
) -> String {
    if category.id == "climate" {
        return "Thermostat"
    }
    let count = max(1, category.count)
    let sensorLabel = "\(count) \(measurement) sensor\(count == 1 ? "" : "s")"
    return count > 1 ? "\(sensorLabel) · room average" : sensorLabel
}

private func homeCategorySourceName(
    _ category: LittleSpudHomeCategory,
    singular: String
) -> String {
    let count = max(1, category.count)
    return "\(count) \(singular)\(count == 1 ? "" : "s")"
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

private struct EmptyNotificationsView: View {
    var body: some View {
        VStack(spacing: 15) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent2.opacity(0.14))
                    .frame(width: 88, height: 88)
                Circle()
                    .stroke(AppTheme.accent2.opacity(0.18), lineWidth: 1)
                    .frame(width: 72, height: 72)
                Image("LittleSpudMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 66, height: 66)
            }
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Tater’s keeping watch.")
                    .font(.headline)
                Text("Alerts will land here in their own tidy stack, separate from chat.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.muted)
                    .padding(.horizontal, 12)
            }

            Label("No new alerts", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.green)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(AppTheme.green.opacity(0.1), in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 34)
        .background(
            LinearGradient(
                colors: [AppTheme.accent.opacity(0.09), AppTheme.panel, AppTheme.panelRaised],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(AppTheme.accent2.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct MessageBubble: View {
    @EnvironmentObject private var model: LittleSpudViewModel
    let message: LittleSpudMessage
    let completed: Bool

    private var isUser: Bool { message.role == .user }
    private var isSystem: Bool { message.role == .system }
    private var isPending: Bool { message.kind == "pending" }
    private var isStreaming: Bool { message.kind == "streaming" }
    private var hasText: Bool { !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                Text(senderLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                if isPending {
                    ThinkingBubbleContent(assistantName: model.assistantDisplayName)
                } else if hasText {
                    StreamingMessageText(
                        content: message.content,
                        isStreaming: isStreaming
                    )
                        .font(.body)
                        .textSelection(.enabled)
                        .foregroundStyle(isUser ? Color.white : AppTheme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(background, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    completed
                                        ? AppTheme.accent2.opacity(0.95)
                                        : isStreaming
                                            ? AppTheme.accent2.opacity(0.42)
                                            : Color.clear,
                                    lineWidth: completed ? 2 : 1
                                )
                        )
                        .shadow(
                            color: isStreaming ? AppTheme.accent2.opacity(0.12) : Color.clear,
                            radius: 8
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

    private var senderLabel: String {
        guard !isUser else { return message.label }
        let label = message.role == .assistant ? model.assistantDisplayName : message.label
        return "\(label) · \(message.createdAt.formatted(date: .omitted, time: .shortened))"
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
            isSpudLinkAPIPath(path),
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

    private func isSpudLinkAPIPath(_ path: String) -> Bool {
        path.hasPrefix("/api/spudlink/") || path.contains("/api/spudlink/")
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

private struct StreamingMessageText: View {
    let content: String
    let isStreaming: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cursorVisible = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            Text(content)
            if isStreaming {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(AppTheme.accent2)
                    .frame(width: 5, height: 16)
                    .opacity(reduceMotion || cursorVisible ? 0.95 : 0.2)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            animateCursorIfNeeded()
        }
        .onChange(of: isStreaming) { _ in
            animateCursorIfNeeded()
        }
    }

    private func animateCursorIfNeeded() {
        guard isStreaming else {
            cursorVisible = false
            return
        }
        guard !reduceMotion else {
            cursorVisible = true
            return
        }
        cursorVisible = false
        withAnimation(.easeInOut(duration: 0.52).repeatForever(autoreverses: true)) {
            cursorVisible = true
        }
    }
}

private struct MediaAttachmentGrid: View {
    let attachments: [LittleSpudAttachment]
    var compact = false

    private var visibleAttachments: [LittleSpudAttachment] {
        compact ? Array(attachments.prefix(1)) : attachments
    }

    var body: some View {
        if !attachments.isEmpty {
            VStack(spacing: 8) {
                ForEach(visibleAttachments) { attachment in
                    MediaAttachmentCard(attachment: attachment, compact: compact)
                }
                if compact && attachments.count > visibleAttachments.count {
                    Text("+\(attachments.count - visibleAttachments.count) more attachment\(attachments.count - visibleAttachments.count == 1 ? "" : "s")")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
    var compact = false

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
                if compact {
                    NotificationVideoPreviewView(
                        url: remoteURL,
                        suppliedSnapshot: imageFromDataURL
                    )
                } else {
                    InlineVideoPlayerView(url: remoteURL, height: 190)
                }
            } else if mediaKind == .audio, let remoteURL {
                InlineAudioPlayerView(
                    url: remoteURL,
                    title: attachment.displayName,
                    subtitle: [attachment.type, formattedSize].filter { !$0.isEmpty }.joined(separator: " / ")
                )
            } else {
                fileBody
            }
            if mediaKind != .audio && !compact {
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
            if compact {
                Image(uiImage: imageFromDataURL)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 132)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(uiImage: imageFromDataURL)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        } else if let remoteURL {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let image):
                    if compact {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 132)
                            .clipped()
                    } else {
                        image
                            .resizable()
                            .scaledToFit()
                    }
                case .failure:
                    fileBody
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: compact ? 132 : 120)
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

private struct NotificationVideoPreviewView: View {
    let url: URL
    let suppliedSnapshot: UIImage?

    @State private var extractedSnapshot: UIImage?
    @State private var showsFullScreenVideo = false

    private var snapshot: UIImage? {
        suppliedSnapshot ?? extractedSnapshot
    }

    var body: some View {
        Button {
            showsFullScreenVideo = true
        } label: {
            ZStack {
                Color.black

                if let snapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                        .tint(.white)
                }

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(AppTheme.accent2)
                    .shadow(color: .black.opacity(0.65), radius: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 132)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play video clip")
        .task(id: url) {
            await loadSnapshotIfNeeded()
        }
        .fullScreenCover(isPresented: $showsFullScreenVideo) {
            FullScreenNotificationVideoView(url: url)
        }
    }

    private func loadSnapshotIfNeeded() async {
        guard suppliedSnapshot == nil else { return }
        let image = await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1280, height: 1280)
            guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else {
                return nil as UIImage?
            }
            return UIImage(cgImage: cgImage)
        }.value
        guard !Task.isCancelled else { return }
        extractedSnapshot = image
    }
}

private struct FullScreenNotificationVideoView: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.65), in: Circle())
            }
            .padding(.top, 12)
            .padding(.trailing, 12)
            .accessibilityLabel("Close video")
        }
        .onAppear {
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

private struct InlineVideoPlayerView: View {
    let url: URL
    var height: CGFloat = 190
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
                .frame(maxWidth: .infinity, minHeight: height)
            }
        }
        .frame(height: height)
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
    @EnvironmentObject private var model: LittleSpudViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.assistantDisplayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                ThinkingBubbleContent(assistantName: model.assistantDisplayName)
            }
            .frame(maxWidth: 360, alignment: .leading)
            Spacer(minLength: 48)
        }
    }
}

private struct ThinkingBubbleContent: View {
    let assistantName: String
    @State private var animate = false

    var body: some View {
        HStack(spacing: 8) {
            Text("\(assistantName) is thinking")
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
    @State private var showAttachmentOptions = false
    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 8) {
            if !model.speechStatus.isEmpty {
                StatusLine(text: model.speechStatus, kind: model.speechStatus == "No speech recognized." ? "" : "ok")
                    .padding(.horizontal, 4)
            }
            if !model.pendingAttachments.isEmpty {
                PendingAttachmentStrip(attachments: model.pendingAttachments) { id in
                    model.removePendingAttachment(id: id)
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    focused.wrappedValue = false
                    showAttachmentOptions = true
                } label: {
                    Image(systemName: model.pendingAttachments.isEmpty ? "plus" : "photo.on.rectangle.angled")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(SecondaryIconButtonStyle(active: !model.pendingAttachments.isEmpty))
                .disabled(model.session == nil)
                .accessibilityLabel("Attach image")

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
        .confirmationDialog("Attach image", isPresented: $showAttachmentOptions, titleVisibility: .visible) {
            Button("Choose Photo") {
                showPhotoLibrary = true
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") {
                    showCamera = true
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhotoLibrary, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { item in
            loadSelectedPhoto(item)
        }
        .sheet(isPresented: $showCamera) {
            CameraCaptureSheet { image in
                if let image {
                    model.addImageAttachment(image, suggestedName: "little-spud-camera.jpg")
                }
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(AppTheme.background)
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    await MainActor.run {
                        model.speechStatus = "Image could not be attached."
                        selectedPhotoItem = nil
                    }
                    return
                }
                await MainActor.run {
                    model.addImageAttachment(image, suggestedName: "little-spud-photo.jpg")
                    selectedPhotoItem = nil
                }
            } catch {
                await MainActor.run {
                    model.speechStatus = "Image could not be attached."
                    selectedPhotoItem = nil
                }
            }
        }
    }
}

private struct PendingAttachmentStrip: View {
    let attachments: [LittleSpudAttachment]
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    PendingAttachmentChip(attachment: attachment) {
                        onRemove(attachment.id)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

private struct PendingAttachmentChip: View {
    let attachment: LittleSpudAttachment
    let onRemove: () -> Void

    private var image: UIImage? {
        guard attachment.dataUrl.hasPrefix("data:"), let comma = attachment.dataUrl.firstIndex(of: ",") else { return nil }
        let payload = String(attachment.dataUrl[attachment.dataUrl.index(after: comma)...])
        guard let data = Data(base64Encoded: payload) else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.accent2)
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(formattedSize)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
            }
            .frame(maxWidth: 150, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundStyle(AppTheme.text)
            .background(Color.white.opacity(0.08), in: Circle())
            .accessibilityLabel("Remove attachment")
        }
        .padding(6)
        .background(AppTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.line, lineWidth: 1)
        )
    }

    private var formattedSize: String {
        if attachment.size < 1024 { return "\(attachment.size) B" }
        let kb = Double(attachment.size) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}

private struct CameraCaptureSheet: UIViewControllerRepresentable {
    let onComplete: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onComplete: (UIImage?) -> Void

        init(onComplete: @escaping (UIImage?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onComplete(info[.originalImage] as? UIImage)
        }
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
