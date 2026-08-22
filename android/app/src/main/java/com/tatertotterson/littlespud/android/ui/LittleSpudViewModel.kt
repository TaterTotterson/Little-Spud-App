package com.tatertotterson.littlespud.android.ui

import android.Manifest
import android.app.Application
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.tatertotterson.littlespud.android.AppContainer
import com.tatertotterson.littlespud.android.BuildConfig
import com.tatertotterson.littlespud.android.data.ChatResponse
import com.tatertotterson.littlespud.android.data.SpudLinkException
import com.tatertotterson.littlespud.android.model.ConnectionRoute
import com.tatertotterson.littlespud.android.model.HomeCategory
import com.tatertotterson.littlespud.android.model.HomeSnapshot
import com.tatertotterson.littlespud.android.model.HubActiveRun
import com.tatertotterson.littlespud.android.model.HubHistoryMessage
import com.tatertotterson.littlespud.android.model.HubNotification
import com.tatertotterson.littlespud.android.model.LittleSpudAttachment
import com.tatertotterson.littlespud.android.model.LittleSpudLane
import com.tatertotterson.littlespud.android.model.LittleSpudMessage
import com.tatertotterson.littlespud.android.model.LittleSpudRole
import com.tatertotterson.littlespud.android.model.LittleSpudSession
import com.tatertotterson.littlespud.android.model.MusicRecommendation
import com.tatertotterson.littlespud.android.model.MusicSnapshot
import com.tatertotterson.littlespud.android.model.MusicTrack
import com.tatertotterson.littlespud.android.model.PushRegistration
import com.tatertotterson.littlespud.android.model.TemperatureUnitPreference
import com.tatertotterson.littlespud.android.playback.MusicPlaybackService
import com.tatertotterson.littlespud.android.playback.toMusicTrack
import com.tatertotterson.littlespud.android.playback.toPlaybackMediaItem
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString.Companion.toByteString
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.Locale
import java.util.UUID
import kotlin.math.max

data class LittleSpudUiState(
    val userName: String = "",
    val deviceName: String = "Android device",
    val hubUrl: String = "",
    val syncCode: String = "",
    val session: LittleSpudSession? = null,
    val messages: List<LittleSpudMessage> = emptyList(),
    val notifications: List<LittleSpudMessage> = emptyList(),
    val draft: String = "",
    val pendingAttachments: List<LittleSpudAttachment> = emptyList(),
    val activeLane: LittleSpudLane = LittleSpudLane.CHAT,
    val statusText: String = "",
    val statusIsError: Boolean = false,
    val isPairing: Boolean = false,
    val isSending: Boolean = false,
    val hubConnected: Boolean = false,
    val notificationsEnabled: Boolean = false,
    val notificationUnreadCount: Int = 0,
    val ttsEnabled: Boolean = false,
    val temperatureUnitPreference: TemperatureUnitPreference = TemperatureUnitPreference.AUTOMATIC,
    val isVoiceRecording: Boolean = false,
    val isVoiceSubmitting: Boolean = false,
    val speechStatus: String = "",
    val showSettings: Boolean = false,
    val home: HomeSnapshot = HomeSnapshot(),
    val homeLoading: Boolean = false,
    val homeError: String = "",
    val homeControlsInFlight: Set<String> = emptySet(),
    val cameraSnapshots: Map<String, ByteArray> = emptyMap(),
    val cameraLoading: Set<String> = emptySet(),
    val cameraErrors: Map<String, String> = emptyMap(),
    val music: MusicSnapshot = MusicSnapshot(),
    val musicLoading: Boolean = false,
    val musicTransportLoading: Boolean = false,
    val musicError: String = "",
    val musicQuery: String = "",
    val selectedMusicTargetIds: Set<String> = emptySet(),
    val localMusicTrack: MusicTrack? = null,
    val localMusicQueue: List<MusicTrack> = emptyList(),
    val localMusicQueueIndex: Int = -1,
    val localMusicPlaying: Boolean = false,
    val localMusicPositionSeconds: Double = 0.0,
) {
    val isDemo: Boolean get() = session?.isDemo == true
    val canSend: Boolean get() = session != null && (draft.isNotBlank() || pendingAttachments.isNotEmpty()) && !isSending
    val canUseVoiceInput: Boolean get() = session != null && !isDemo && !isSending
    val assistantName: String get() = session?.assistantName?.ifBlank { "Tater" } ?: "Tater"
    val connectionText: String get() = when {
        isDemo -> "Demo Mode"
        !hubConnected -> "Not Connected"
        session?.displayRoute == ConnectionRoute.HOME -> "Connected Home"
        session?.displayRoute == ConnectionRoute.AWAY -> "Connected Away"
        else -> "Connected"
    }
}

class LittleSpudViewModel(
    application: Application,
    private val container: AppContainer,
) : AndroidViewModel(application) {
    private val _state = MutableStateFlow(
        LittleSpudUiState(
            userName = container.settings.userName,
            deviceName = container.settings.defaultDeviceName(),
            session = container.secureStore.loadSession(),
            messages = ChatHistoryReconciler.dedupeLocal(container.messageStore.loadMessages()),
            notifications = container.messageStore.loadNotifications(),
            notificationsEnabled = container.settings.notificationsEnabled,
            notificationUnreadCount = container.settings.notificationUnreadCount,
            ttsEnabled = container.settings.ttsEnabled,
            temperatureUnitPreference = container.settings.temperatureUnitPreference,
        ),
    )
    val state: StateFlow<LittleSpudUiState> = _state.asStateFlow()

    private var notificationPollJob: Job? = null
    private var routeProbeJob: Job? = null
    private var homeJob: Job? = null
    private var musicJob: Job? = null
    private var musicStateSyncJob: Job? = null
    private var pushJob: Job? = null
    private var voiceCaptureJob: Job? = null
    private var voiceSocket: WebSocket? = null
    private var pendingReopenMicJob: Job? = null
    private var audioRecord: AudioRecord? = null
    private val pendingNotificationAcks = mutableSetOf<String>()
    private var localMusicController: MediaController? = null
    private var localMusicControllerFuture: ListenableFuture<MediaController>? = null
    private var pendingLocalPlayback: ((MediaController) -> Unit)? = null
    private var localMusicProgressJob: Job? = null
    private val localMusicPlayerListener = object : Player.Listener {
        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            // Some devices briefly restore the player's default gain while
            // advancing. Reapply the shared slider value before the next item
            // begins so track changes stay at a constant volume.
            val volume = _state.value.music.player.volumePercent.coerceIn(0, 100)
            localMusicController?.volume = volume / 100f
        }

        override fun onEvents(player: Player, events: Player.Events) {
            syncLocalMusicPlayerState(player)
        }

        override fun onPlayerError(error: PlaybackException) {
            _state.update { it.copy(musicError = friendlyError(error)) }
        }
    }

    init {
        connectLocalMusicController(application)
        viewModelScope.launch {
            container.notificationUpdates.revision.collect {
                refreshNotificationsFromStore()
            }
        }
        _state.value.session?.let { session ->
            _state.update { it.copy(hubUrl = session.hubUrl, userName = session.userName, deviceName = session.deviceName) }
            resume()
        }
    }

    private fun connectLocalMusicController(application: Application) {
        val token = SessionToken(
            application,
            ComponentName(application, MusicPlaybackService::class.java),
        )
        val future = MediaController.Builder(application, token)
            .setApplicationLooper(Looper.getMainLooper())
            .buildAsync()
        localMusicControllerFuture = future
        future.addListener(
            {
                runCatching { future.get() }
                    .onSuccess { controller ->
                        if (localMusicControllerFuture !== future) {
                            controller.release()
                            return@onSuccess
                        }
                        localMusicController = controller
                        controller.addListener(localMusicPlayerListener)
                        val pending = pendingLocalPlayback
                        pendingLocalPlayback = null
                        if (pending != null) {
                            pending(controller)
                        } else {
                            syncLocalMusicPlayerState(controller)
                        }
                    }
                    .onFailure { error ->
                        if (localMusicControllerFuture === future) {
                            _state.update {
                                it.copy(
                                    musicError = "Phone playback is unavailable: ${friendlyError(error)}",
                                )
                            }
                        }
                    }
            },
            ContextCompat.getMainExecutor(application),
        )
    }

    private fun syncLocalMusicPlayerState(player: Player) {
        if (_state.value.session?.isDemo == true) return
        val queue = buildList {
            repeat(player.mediaItemCount) { index ->
                player.getMediaItemAt(index).toMusicTrack()?.let(::add)
            }
        }
        val queueIndex = player.currentMediaItemIndex.takeIf { it in queue.indices } ?: -1
        val position = player.currentPosition.coerceAtLeast(0L) / 1_000.0
        _state.update { current ->
            current.copy(
                localMusicTrack = queue.getOrNull(queueIndex),
                localMusicQueue = queue,
                localMusicQueueIndex = queueIndex,
                localMusicPlaying = player.isPlaying,
                localMusicPositionSeconds = position,
                music = current.music.copy(
                    player = current.music.player.copy(
                        volumePercent = (player.volume * 100).toInt().coerceIn(0, 100),
                    ),
                ),
            )
        }
        updateLocalMusicProgressTracking()
    }

    private fun updateLocalMusicProgressTracking() {
        localMusicProgressJob?.cancel()
        localMusicProgressJob = null
        val controller = localMusicController ?: return
        if (!controller.isPlaying) return
        localMusicProgressJob = viewModelScope.launch {
            while (isActive && controller.isPlaying) {
                _state.update {
                    it.copy(
                        localMusicPositionSeconds = controller.currentPosition
                            .coerceAtLeast(0L) / 1_000.0,
                    )
                }
                delay(500)
            }
        }
    }

    fun updateUserName(value: String) = _state.update { it.copy(userName = value) }
    fun updateDeviceName(value: String) = _state.update { it.copy(deviceName = value) }
    fun updateHubUrl(value: String) = _state.update { it.copy(hubUrl = value) }
    fun updateSyncCode(value: String) = _state.update { it.copy(syncCode = value) }
    fun updateDraft(value: String) = _state.update { it.copy(draft = value) }
    fun updateMusicQuery(value: String) = _state.update { it.copy(musicQuery = value) }
    fun showSettings(show: Boolean) = _state.update { it.copy(showSettings = show) }
    fun setTemperatureUnitPreference(preference: TemperatureUnitPreference) {
        container.settings.temperatureUnitPreference = preference
        _state.update { it.copy(temperatureUnitPreference = preference) }
    }
    fun reportStatus(message: String, isError: Boolean = false) =
        _state.update { it.copy(statusText = message, statusIsError = isError) }

    fun applyPairingPayload(value: String) {
        _state.update { it.copy(syncCode = value, statusText = "QR code captured.", statusIsError = false) }
    }

    fun toggleVoiceInput() {
        cancelPendingReopenMic()
        when {
            _state.value.isVoiceRecording -> stopVoiceInput()
            _state.value.isVoiceSubmitting -> cancelVoiceInput()
            else -> openVoiceInput()
        }
    }

    private fun openVoiceInput() {
        val session = _state.value.session ?: return
        if (!_state.value.canUseVoiceInput) return
        val application = getApplication<Application>()
        if (ContextCompat.checkSelfPermission(application, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            reportStatus("Allow microphone access to use voice input.", isError = true)
            return
        }

        cleanupVoiceInput(closeSocket = true)
        val minBufferSize = AudioRecord.getMinBufferSize(
            VOICE_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBufferSize <= 0) {
            reportStatus("This device could not open a compatible microphone stream.", isError = true)
            return
        }

        try {
            @Suppress("MissingPermission")
            val recorder = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                VOICE_SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                max(minBufferSize, VOICE_BUFFER_BYTES * 2),
            )
            if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                recorder.release()
                throw SpudLinkException("This device could not initialize the microphone.")
            }
            audioRecord = recorder
            _state.update {
                it.copy(
                    isVoiceRecording = true,
                    isVoiceSubmitting = false,
                    speechStatus = "Opening mic…",
                    statusText = "",
                    statusIsError = false,
                )
            }
            val listener = object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    viewModelScope.launch {
                        if (voiceSocket === webSocket) startVoiceCapture(webSocket)
                    }
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    viewModelScope.launch { if (voiceSocket === webSocket) handleSpeechPayload(text) }
                }

                override fun onMessage(webSocket: WebSocket, bytes: okio.ByteString) {
                    onMessage(webSocket, bytes.utf8())
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    viewModelScope.launch {
                        if (voiceSocket === webSocket) handleVoiceFailure(t.localizedMessage ?: "The voice stream closed.")
                    }
                }
            }
            voiceSocket = container.api.openSttStream(
                session,
                VOICE_SAMPLE_RATE,
                Locale.getDefault().toLanguageTag(),
                listener,
            )
        } catch (error: Throwable) {
            cleanupVoiceInput(closeSocket = true)
            reportStatus("Voice input failed: ${friendlyError(error)}", isError = true)
        }
    }

    private fun startVoiceCapture(socket: WebSocket) {
        val recorder = audioRecord ?: return
        try {
            recorder.startRecording()
            if (recorder.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                throw SpudLinkException("The microphone did not start recording.")
            }
            _state.update { it.copy(speechStatus = "Listening…") }
            voiceCaptureJob = viewModelScope.launch(Dispatchers.IO) {
                val buffer = ByteArray(VOICE_BUFFER_BYTES)
                while (isActive && voiceSocket === socket && _state.value.isVoiceRecording) {
                    val count = recorder.read(buffer, 0, buffer.size)
                    if (count > 0) socket.send(buffer.toByteString(0, count))
                    else if (count != AudioRecord.ERROR_INVALID_OPERATION) break
                }
            }
        } catch (error: Throwable) {
            handleVoiceFailure(error.localizedMessage ?: "The microphone stopped.")
        }
    }

    private fun stopVoiceInput() {
        if (!_state.value.isVoiceRecording) return
        stopVoiceCapture()
        _state.update { it.copy(isVoiceRecording = false, isVoiceSubmitting = true, speechStatus = "Transcribing…") }
        if (voiceSocket?.send(JSONObject().put("type", "stop").toString()) != true) {
            handleVoiceFailure("The voice stream was no longer connected.")
        }
    }

    private fun cancelVoiceInput() {
        val socket = voiceSocket
        socket?.send(JSONObject().put("type", "cancel").toString())
        cleanupVoiceInput(closeSocket = false)
        socket?.close(1000, "Voice input cancelled")
    }

    private fun handleSpeechPayload(value: String) {
        val payload = runCatching { JSONObject(value) }.getOrNull() ?: return
        if (payload.has("ok") && !payload.optBoolean("ok", true)) {
            handleVoiceFailure(payload.optString("error").ifBlank { payload.optString("message").ifBlank { "Voice input failed." } })
            return
        }
        when (payload.optString("type")) {
            "listening" -> _state.update { it.copy(speechStatus = "Listening…") }
            "speech_start" -> {
                _state.update { it.copy(speechStatus = "Got it…") }
                haptic()
            }
            "speech_end" -> {
                stopVoiceCapture()
                _state.update { it.copy(isVoiceRecording = false, isVoiceSubmitting = true, speechStatus = "Transcribing…") }
            }
            "final" -> finishVoiceTranscript(payload.optString("text"))
            "cancelled" -> cleanupVoiceInput(closeSocket = true)
            "error" -> handleVoiceFailure(payload.optString("error").ifBlank { payload.optString("message").ifBlank { "Voice input failed." } })
        }
    }

    private fun finishVoiceTranscript(value: String) {
        val clean = value.trim()
        cleanupVoiceInput(closeSocket = true)
        if (clean.isBlank()) {
            _state.update { it.copy(speechStatus = "No speech recognized.") }
            return
        }
        _state.update { it.copy(draft = clean, speechStatus = "") }
        haptic()
        sendMessage(fromVoice = true)
    }

    private fun handleVoiceFailure(message: String) {
        cleanupVoiceInput(closeSocket = true)
        reportStatus("Voice input failed: $message", isError = true)
    }

    private fun stopVoiceCapture() {
        voiceCaptureJob?.cancel()
        voiceCaptureJob = null
        val recorder = audioRecord
        audioRecord = null
        if (recorder != null) {
            if (recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) runCatching { recorder.stop() }
            recorder.release()
        }
    }

    private fun cleanupVoiceInput(closeSocket: Boolean) {
        stopVoiceCapture()
        if (closeSocket) voiceSocket?.close(1000, "Voice input complete")
        voiceSocket = null
        _state.update { it.copy(isVoiceRecording = false, isVoiceSubmitting = false, speechStatus = "") }
    }

    fun pair() {
        val snapshot = _state.value
        if (snapshot.isPairing) return
        _state.update { it.copy(isPairing = true, statusText = "Pairing with Tater…", statusIsError = false) }
        viewModelScope.launch {
            try {
                val session = container.api.pair(snapshot.userName, snapshot.deviceName, snapshot.hubUrl, snapshot.syncCode)
                container.secureStore.saveSession(session)
                container.settings.userName = session.userName
                _state.update {
                    it.copy(
                        session = session,
                        userName = session.userName,
                        deviceName = session.deviceName,
                        hubUrl = session.hubUrl,
                        syncCode = "",
                        isPairing = false,
                        hubConnected = true,
                        statusText = "Paired with ${session.hubName}.",
                        statusIsError = false,
                    )
                }
                haptic()
                resume()
            } catch (error: Throwable) {
                _state.update { it.copy(isPairing = false, statusText = friendlyError(error), statusIsError = true) }
            }
        }
    }

    fun startDemoMode() {
        val now = System.currentTimeMillis()
        val session = LittleSpudSession(
            hubUrl = "demo://little-spud",
            homeHubUrl = "demo://little-spud",
            activeRoute = ConnectionRoute.HOME,
            token = "little-spud-demo-token",
            userName = _state.value.userName.trim().ifBlank { "Demo User" },
            deviceName = _state.value.deviceName.trim().ifBlank { "Android device" },
            nodeName = "Little Spud Demo",
            hubName = "Tater Demo",
            hubMode = "demo",
            assistantName = "Tater",
            toolsEnabled = true,
            pairedAt = now,
            lastSeenAt = now,
        )
        container.secureStore.saveSession(session)
        _state.update {
            it.copy(
                session = session,
                hubUrl = session.hubUrl,
                hubConnected = true,
                statusText = "Demo mode is ready.",
                statusIsError = false,
                messages = if (it.messages.isEmpty()) listOf(
                    LittleSpudMessage(role = LittleSpudRole.ASSISTANT, content = "Hi! I’m Tater. Little Spud for Android is ready to explore."),
                ) else it.messages,
            )
        }
        saveMessages()
    }

    fun resume() {
        val session = _state.value.session ?: return
        if (session.isDemo) {
            _state.update { it.copy(hubConnected = true, home = demoHome(), music = demoMusic()) }
            return
        }
        refreshFromHub(showStatus = false)
        startNotificationPoll()
        startRouteProbe()
        if (_state.value.activeLane == LittleSpudLane.MUSIC) {
            refreshMusic()
            startMusicStateSync()
        }
        syncPushRegistration()
    }

    fun pauseForegroundWork() {
        cancelPendingReopenMic()
        notificationPollJob?.cancel()
        notificationPollJob = null
        routeProbeJob?.cancel()
        routeProbeJob = null
        stopMusicStateSync()
        if (_state.value.isVoiceRecording || _state.value.isVoiceSubmitting) cancelVoiceInput()
    }

    fun selectLane(lane: LittleSpudLane) {
        _state.update { it.copy(activeLane = lane, showSettings = false) }
        if (lane != LittleSpudLane.MUSIC) stopMusicStateSync()
        when (lane) {
            LittleSpudLane.NOTIFICATIONS -> markNotificationsRead()
            LittleSpudLane.HOME -> refreshHome()
            LittleSpudLane.MUSIC -> {
                refreshMusic()
                startMusicStateSync()
            }
            LittleSpudLane.CHAT -> Unit
        }
    }

    fun sendMessage(fromVoice: Boolean = false) {
        cancelPendingReopenMic()
        val snapshot = _state.value
        val session = snapshot.session ?: return
        if (!snapshot.canSend) return
        val text = snapshot.draft.trim()
        val attachments = snapshot.pendingAttachments
        val userMessage = LittleSpudMessage(
            role = LittleSpudRole.USER,
            content = text.ifBlank { if (attachments.size == 1) "Attached image" else "Attached media" },
            attachments = attachments,
        )
        val assistantId = UUID.randomUUID().toString()
        val pending = LittleSpudMessage(
            id = assistantId,
            role = LittleSpudRole.ASSISTANT,
            content = "",
            kind = "streaming",
        )
        // The current prompt is sent separately by SpudLinkApi; history must only
        // contain messages that existed before this turn.
        val historyForRequest = snapshot.messages
        _state.update {
            it.copy(
                messages = sortedMessages(it.messages + userMessage + pending),
                draft = "",
                pendingAttachments = emptyList(),
                isSending = true,
                statusText = "",
                statusIsError = false,
            )
        }
        saveMessages()
        if (session.isDemo) {
            viewModelScope.launch {
                delay(450)
                val reply = demoReply(text, attachments)
                replaceMessage(assistantId) { it.copy(content = reply, kind = null) }
                _state.update { it.copy(isSending = false) }
                saveMessages(); haptic()
            }
            return
        }
        viewModelScope.launch {
            try {
                val response = container.api.sendChat(
                    session = session,
                    messages = historyForRequest,
                    text = text,
                    attachments = attachments,
                    onToolNotice = { notice ->
                        withContext(Dispatchers.Main) {
                            val tool = LittleSpudMessage(
                                id = notice.id,
                                role = LittleSpudRole.ASSISTANT,
                                content = notice.text,
                                createdAt = notice.createdAt,
                                kind = "tool_notice",
                            )
                            _state.update { current ->
                                if (current.messages.any { it.id == tool.id }) current
                                else current.copy(messages = sortedMessages(current.messages + tool))
                            }
                        }
                    },
                    onResponseChunk = { chunk ->
                        withContext(Dispatchers.Main) {
                            replaceMessage(assistantId) { message -> message.copy(content = message.content + chunk, kind = "streaming") }
                        }
                    },
                )
                completeChat(assistantId, response)
                val speechJob = if (_state.value.ttsEnabled && response.content.isNotBlank()) {
                    playSpeech(session, response.content)
                } else null
                if (fromVoice && response.reopenMic) {
                    speechJob?.join()
                    reopenMicAfterReply()
                }
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                val message = friendlyError(error)
                replaceMessage(assistantId) { existing -> existing.copy(content = existing.content.ifBlank { message }, kind = "error") }
                _state.update { it.copy(isSending = false, statusText = message, statusIsError = true, hubConnected = false) }
                saveMessages()
            }
        }
    }

    private fun completeChat(assistantId: String, response: ChatResponse) {
        replaceMessage(assistantId) { existing ->
            existing.copy(
                content = response.content.ifBlank { existing.content }.ifBlank { "Tater finished without a text response." },
                kind = null,
                attachments = response.attachments,
            )
        }
        _state.update { it.copy(isSending = false, hubConnected = true) }
        saveMessages(); haptic()
    }

    fun removeAttachment(id: String) = _state.update {
        it.copy(pendingAttachments = it.pendingAttachments.filterNot { attachment -> attachment.id == id })
    }

    fun addAttachment(uri: Uri) {
        if (_state.value.pendingAttachments.size >= 3) {
            _state.update { it.copy(statusText = "Remove an attachment before adding another.", statusIsError = true) }
            return
        }
        viewModelScope.launch {
            runCatching { makeAttachment(uri) }
                .onSuccess { attachment ->
                    _state.update { it.copy(pendingAttachments = it.pendingAttachments + attachment, statusText = "Image attached.", statusIsError = false) }
                }
                .onFailure { error -> _state.update { it.copy(statusText = friendlyError(error), statusIsError = true) } }
        }
    }

    private suspend fun makeAttachment(uri: Uri): LittleSpudAttachment = withContext(Dispatchers.IO) {
        val resolver = getApplication<Application>().contentResolver
        val source = resolver.openInputStream(uri)?.use { input -> input.readBytes(MAX_ATTACHMENT_BYTES + 1) }
            ?: throw SpudLinkException("The selected image could not be read.")
        if (source.size > MAX_ATTACHMENT_BYTES) throw SpudLinkException("That image is too large. Choose an image under 8 MB.")
        val bitmap = BitmapFactory.decodeByteArray(source, 0, source.size)
            ?: throw SpudLinkException("The selected file is not a supported image.")
        val resized = resizeBitmap(bitmap, 1600)
        val output = ByteArrayOutputStream()
        resized.compress(Bitmap.CompressFormat.JPEG, 84, output)
        if (resized !== bitmap) resized.recycle()
        bitmap.recycle()
        val bytes = output.toByteArray()
        val name = uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() } ?: "little-spud-image.jpg"
        LittleSpudAttachment(
            name = name.substringBeforeLast('.', name) + ".jpg",
            type = "image/jpeg",
            size = bytes.size,
            dataUrl = "data:image/jpeg;base64," + android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP),
        )
    }

    private fun resizeBitmap(bitmap: Bitmap, maxDimension: Int): Bitmap {
        val largest = max(bitmap.width, bitmap.height)
        if (largest <= maxDimension) return bitmap
        val scale = maxDimension.toFloat() / largest
        return Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true)
    }

    fun refreshHome(force: Boolean = false) {
        val session = _state.value.session ?: return
        if (session.isDemo) {
            _state.update { it.copy(home = demoHome(), homeLoading = false, homeError = "") }
            return
        }
        if (homeJob?.isActive == true) return
        _state.update { it.copy(homeLoading = true, homeError = if (force) "" else it.homeError) }
        homeJob = viewModelScope.launch {
            try {
                val home = container.api.fetchHome(session, force)
                _state.update { it.copy(home = home, homeLoading = false, homeError = "") }
            } catch (error: Throwable) {
                _state.update { it.copy(homeLoading = false, homeError = friendlyError(error)) }
            }
        }
    }

    fun performHomeAction(
        roomId: String,
        category: HomeCategory,
        action: String,
        value: Double? = null,
        mode: String? = null,
        temperatureUnit: String? = null,
    ) {
        val session = _state.value.session ?: return
        if (!category.supports(action)) {
            _state.update { it.copy(homeError = "${category.name} does not support that control.") }
            return
        }
        val key = "$roomId|${category.id}"
        if (key in _state.value.homeControlsInFlight) return
        if (session.isDemo) {
            val updatedRooms = _state.value.home.rooms.map { room ->
                if (room.id != roomId) room else room.copy(categories = room.categories.map { item ->
                    if (item.id != category.id) item else item.copy(state = when (action) {
                        "turn_on" -> "on"; "turn_off" -> "off"; else -> item.state
                    }, brightness = if (action == "set_brightness") value else item.brightness,
                        targetTemperature = if (action == "set_temperature") value else item.targetTemperature,
                        temperatureUnit = if (action == "set_temperature" && !temperatureUnit.isNullOrBlank()) temperatureUnit else item.temperatureUnit,
                        hvacMode = if (action == "set_hvac_mode") mode.orEmpty() else item.hvacMode)
                })
            }
            _state.update { it.copy(home = it.home.copy(rooms = updatedRooms)) }
            haptic(); return
        }
        _state.update { it.copy(homeControlsInFlight = it.homeControlsInFlight + key, homeError = "") }
        viewModelScope.launch {
            try {
                val home = container.api.controlHome(session, roomId, category.id, action, value, mode, temperatureUnit)
                _state.update { it.copy(home = home, homeControlsInFlight = it.homeControlsInFlight - key) }
                haptic()
            } catch (error: Throwable) {
                _state.update { it.copy(homeControlsInFlight = it.homeControlsInFlight - key, homeError = friendlyError(error)) }
            }
        }
    }

    fun toggleHomePower(roomId: String, category: HomeCategory) {
        performHomeAction(roomId, category, if (category.state in setOf("on", "mixed")) "turn_off" else "turn_on")
    }

    fun refreshCamera(roomId: String, cameraId: String) {
        val session = _state.value.session ?: return
        val key = "$roomId|$cameraId"
        if (key in _state.value.cameraLoading) return
        _state.update { it.copy(cameraLoading = it.cameraLoading + key, cameraErrors = it.cameraErrors - key) }
        viewModelScope.launch {
            try {
                val bytes = container.api.fetchCameraSnapshot(session, roomId, cameraId)
                _state.update { it.copy(cameraSnapshots = it.cameraSnapshots + (key to bytes), cameraLoading = it.cameraLoading - key) }
            } catch (error: Throwable) {
                _state.update { it.copy(cameraLoading = it.cameraLoading - key, cameraErrors = it.cameraErrors + (key to friendlyError(error))) }
            }
        }
    }

    fun refreshMusic(force: Boolean = false, query: String? = null, limit: Int? = null) {
        val session = _state.value.session ?: return
        if (session.isDemo) {
            _state.update { it.copy(music = demoMusic(it.musicQuery), musicLoading = false, musicError = "") }
            return
        }
        musicJob?.cancel()
        val search = query ?: _state.value.musicQuery
        _state.update { it.copy(musicLoading = true, musicError = "") }
        musicJob = viewModelScope.launch {
            try {
                val music = container.api.fetchMusic(session, search, force, limit)
                _state.update { current ->
                    val reconciled = reconcileMusicSnapshot(current, music)
                    current.copy(
                        music = reconciled,
                        musicLoading = false,
                        selectedMusicTargetIds = chooseMusicTargets(
                            current.selectedMusicTargetIds,
                            reconciled,
                        ),
                    )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                _state.update { it.copy(musicLoading = false, musicError = friendlyError(error)) }
            }
        }
    }

    fun searchMusic() = refreshMusic(query = _state.value.musicQuery.trim())

    fun browseMusic(value: String) {
        _state.update { it.copy(musicQuery = value) }
        refreshMusic(query = value, limit = 200)
    }

    fun clearMusicBrowse() {
        _state.update { it.copy(musicQuery = "") }
        refreshMusic(query = "")
    }

    fun toggleMusicTarget(id: String) {
        val snapshot = _state.value
        val target = snapshot.music.targets.firstOrNull { it.id == id } ?: return
        if (target.isLocal) {
            _state.update { it.copy(selectedMusicTargetIds = setOf(id)) }
            return
        }

        pendingLocalPlayback = null
        if (snapshot.localMusicTrack != null) {
            if (snapshot.session?.isDemo != true) {
                localMusicController?.run {
                    stop()
                    clearMediaItems()
                }
            }
            _state.update {
                it.copy(
                    localMusicTrack = null,
                    localMusicQueue = emptyList(),
                    localMusicQueueIndex = -1,
                    localMusicPlaying = false,
                    localMusicPositionSeconds = 0.0,
                )
            }
        }

        val current = _state.value
        val remoteSelection = current.selectedMusicTargetIds.filterTo(mutableSetOf()) { targetId ->
            current.music.targets.firstOrNull { it.id == targetId }?.isLocal != true
        }
        val updated = when {
            id !in remoteSelection -> remoteSelection + id
            remoteSelection.size > 1 -> remoteSelection - id
            else -> remoteSelection
        }
        _state.update { it.copy(selectedMusicTargetIds = updated) }
        if (current.session?.isDemo != true) runMusicAction("set_targets")
    }

    fun playMusicQueueTrack(index: Int) {
        val current = _state.value
        val session = current.session ?: return
        val queue = if (current.localMusicTrack != null) current.localMusicQueue else current.music.player.queue
        if (index !in queue.indices) return
        val targets = chooseMusicTargets(current.selectedMusicTargetIds, current.music)
        _state.update { it.copy(selectedMusicTargetIds = targets) }
        val local = current.music.targets.any { it.id in targets && it.isLocal }
        if (local) {
            playLocalMusicQueue(queue, session, index)
            return
        }

        val track = queue[index]
        if (session.isDemo) {
            _state.update { state ->
                state.copy(
                    music = state.music.copy(
                        player = state.music.player.copy(
                            status = "playing",
                            current = track,
                            targets = targets.toList(),
                            queueCount = queue.size,
                            queueIndex = index,
                            queue = queue,
                            durationSeconds = track.durationSeconds,
                            positionSeconds = 0.0,
                        ),
                    ),
                    musicError = "",
                )
            }
            haptic()
            return
        }

        // Music Core starts play_queue at its first entry. Rotate the existing
        // queue so the selected song starts immediately and the rest continue
        // in the same circular order.
        val selectedQueue = queue.drop(index) + queue.take(index)
        runMusicAction("play_queue", trackIds = selectedQueue.map { it.id })
    }

    fun playMusic(track: MusicTrack) {
        val session = _state.value.session ?: return
        val targets = chooseMusicTargets(_state.value.selectedMusicTargetIds, _state.value.music)
        _state.update { it.copy(selectedMusicTargetIds = targets) }
        val local = _state.value.music.targets.any { it.id in targets && it.isLocal }
        if (local) {
            playLocalMusicQueue(listOf(track), session)
            return
        }
        runMusicAction("play", trackId = track.id)
    }

    fun playAlbum(tracks: List<MusicTrack>) {
        val queue = tracks.distinctBy { it.id }.filter { it.id.isNotBlank() }
        if (queue.isEmpty()) return
        val session = _state.value.session ?: return
        val targets = chooseMusicTargets(_state.value.selectedMusicTargetIds, _state.value.music)
        _state.update { it.copy(selectedMusicTargetIds = targets) }
        val local = _state.value.music.targets.any { it.id in targets && it.isLocal }
        if (local) {
            playLocalMusicQueue(queue, session)
            return
        }
        if (session.isDemo) {
            _state.update { current ->
                current.copy(
                    music = current.music.copy(
                        player = current.music.player.copy(
                            status = "playing",
                            current = queue.first(),
                            targets = targets.toList(),
                            queueCount = queue.size,
                            queueIndex = 0,
                            queue = queue,
                            durationSeconds = queue.first().durationSeconds,
                            positionSeconds = 0.0,
                        ),
                    ),
                    musicError = "",
                )
            }
            haptic()
            return
        }
        runMusicAction("play_queue", trackIds = queue.map { it.id })
    }

    private fun playLocalMusicQueue(
        tracks: List<MusicTrack>,
        session: LittleSpudSession,
        startIndex: Int = 0,
    ) {
        val queue = tracks.distinctBy { it.id }.filter { it.id.isNotBlank() }
        if (queue.isEmpty()) return
        val selectedIndex = startIndex.coerceIn(0, queue.lastIndex)
        val first = queue[selectedIndex]
        if (session.isDemo) {
            _state.update {
                it.copy(
                    localMusicTrack = first,
                    localMusicQueue = queue,
                    localMusicQueueIndex = selectedIndex,
                    localMusicPlaying = true,
                    localMusicPositionSeconds = 0.0,
                    musicError = "",
                )
            }
            haptic()
            return
        }
        runCatching {
            val items = queue.map { track ->
                track.toPlaybackMediaItem(
                    streamUrl = container.api.musicStreamUrl(session, track),
                    hubUrl = session.hubUrl,
                )
            }
            _state.update {
                it.copy(
                    localMusicTrack = first,
                    localMusicQueue = queue,
                    localMusicQueueIndex = selectedIndex,
                    localMusicPlaying = true,
                    localMusicPositionSeconds = 0.0,
                    musicError = "",
                )
            }
            val startPlayback: (MediaController) -> Unit = { controller ->
                runCatching {
                    controller.setMediaItems(items, selectedIndex, 0L)
                    controller.volume = _state.value.music.player.volumePercent / 100f
                    controller.prepare()
                    controller.play()
                }.onFailure { error ->
                    _state.update {
                        it.copy(
                            localMusicPlaying = false,
                            musicError = friendlyError(error),
                        )
                    }
                }
            }
            val controller = localMusicController
            if (controller == null) {
                pendingLocalPlayback = startPlayback
            } else {
                startPlayback(controller)
            }
            haptic()
        }.onFailure { error ->
            _state.update { it.copy(musicError = friendlyError(error)) }
        }
    }

    fun playRecommendation(recommendation: MusicRecommendation) {
        val local = _state.value.music.targets.any { it.id in _state.value.selectedMusicTargetIds && it.isLocal }
        val session = _state.value.session
        if (local && session != null) playLocalMusicQueue(recommendation.tracks, session)
        else runMusicAction("play_recommendation", recommendationId = recommendation.id)
    }

    fun toggleMusicPlayback() {
        if (_state.value.localMusicTrack != null) {
            if (_state.value.session?.isDemo == true) {
                _state.update { it.copy(localMusicPlaying = !it.localMusicPlaying) }
            } else {
                localMusicController?.let { controller ->
                    if (controller.isPlaying) controller.pause() else controller.play()
                }
            }
            return
        }
        runMusicAction(if (_state.value.music.player.status == "playing") "pause" else "resume")
    }

    fun seekMusic(positionSeconds: Double) {
        val current = _state.value
        val track = current.localMusicTrack ?: current.music.player.current ?: return
        val duration = if (current.localMusicTrack != null) {
            track.durationSeconds
        } else {
            max(track.durationSeconds, current.music.player.durationSeconds)
        }.coerceAtLeast(0.0)
        if (duration <= 0.0) return
        val position = positionSeconds.coerceIn(0.0, duration)

        if (current.localMusicTrack != null) {
            _state.update { it.copy(localMusicPositionSeconds = position) }
            if (current.session?.isDemo != true) {
                // Media3 preserves playWhenReady when seeking, so a paused
                // player stays paused and a playing player continues at release.
                localMusicController?.seekTo((position * 1_000.0).toLong())
            }
            return
        }

        if (current.session?.isDemo == true) {
            _state.update { state ->
                state.copy(
                    music = state.music.copy(
                        player = state.music.player.copy(positionSeconds = position),
                    ),
                )
            }
            return
        }
        if (current.musicLoading) return
        _state.update { state ->
            state.copy(
                music = state.music.copy(
                    player = state.music.player.copy(positionSeconds = position),
                ),
            )
        }
        runMusicAction("seek", positionSeconds = position)
    }

    fun setMusicVolume(value: Int) {
        val volume = value.coerceIn(0, 100)
        if (_state.value.localMusicTrack != null) {
            if (_state.value.session?.isDemo != true) {
                localMusicController?.volume = volume / 100f
            }
            _state.update { current ->
                current.copy(
                    music = current.music.copy(
                        player = current.music.player.copy(volumePercent = volume),
                    ),
                )
            }
            return
        }
        if (_state.value.session?.isDemo == true) {
            _state.update { current ->
                current.copy(
                    music = current.music.copy(
                        player = current.music.player.copy(volumePercent = volume),
                    ),
                )
            }
            return
        }
        // Update the shared snapshot before the request completes. This keeps
        // a fast next/play tap from resending the previous volume to Tater.
        _state.update { current ->
            current.copy(
                music = current.music.copy(
                    player = current.music.player.copy(volumePercent = volume),
                ),
            )
        }
        runMusicAction("set_volume", volumePercent = volume)
    }

    fun stopMusic() {
        if (_state.value.localMusicTrack != null) {
            pendingLocalPlayback = null
            if (_state.value.session?.isDemo != true) {
                localMusicController?.run {
                    stop()
                    clearMediaItems()
                }
            }
            _state.update {
                it.copy(
                    localMusicTrack = null,
                    localMusicQueue = emptyList(),
                    localMusicQueueIndex = -1,
                    localMusicPlaying = false,
                    localMusicPositionSeconds = 0.0,
                )
            }
        } else runMusicAction("stop")
    }

    fun skipMusic(direction: Int) {
        if (_state.value.localMusicTrack != null) {
            val queue = _state.value.localMusicQueue
            if (queue.isEmpty()) return
            val current = _state.value.localMusicQueueIndex.coerceIn(0, queue.lastIndex)
            val next = (current + if (direction >= 0) 1 else queue.size - 1) % queue.size
            if (_state.value.session?.isDemo == true) {
                _state.update {
                    it.copy(
                        localMusicTrack = queue[next],
                        localMusicQueueIndex = next,
                        localMusicPlaying = true,
                        localMusicPositionSeconds = 0.0,
                    )
                }
            } else {
                localMusicController?.run {
                    volume = _state.value.music.player.volumePercent.coerceIn(0, 100) / 100f
                    seekTo(next, 0L)
                    play()
                }
            }
        } else runMusicAction(if (direction >= 0) "next" else "previous")
    }

    private fun runMusicAction(
        action: String,
        trackId: String = "",
        trackIds: List<String> = emptyList(),
        recommendationId: String = "",
        volumePercent: Int? = null,
        positionSeconds: Double? = null,
    ) {
        val session = _state.value.session ?: return
        if (session.isDemo) return
        if (_state.value.musicLoading) return
        val isTransportAction = action in setOf(
            "play", "play_queue", "play_recommendation",
            "pause", "resume", "replay", "stop", "next", "previous",
        )
        _state.update {
            it.copy(
                musicLoading = true,
                musicTransportLoading = isTransportAction,
                musicError = "",
            )
        }
        if (isTransportAction) haptic()
        viewModelScope.launch {
            try {
                val music = container.api.controlMusic(
                    session = session,
                    action = action,
                    trackId = trackId,
                    trackIds = trackIds,
                    recommendationId = recommendationId,
                    targets = _state.value.selectedMusicTargetIds.toList(),
                    provider = _state.value.music.provider?.id.orEmpty(),
                    volumePercent = volumePercent ?: _state.value.music.player.volumePercent,
                    positionSeconds = positionSeconds,
                )
                _state.update { current ->
                    val reconciled = reconcileMusicSnapshot(current, music)
                    current.copy(
                        music = reconciled,
                        musicLoading = false,
                        musicTransportLoading = false,
                        selectedMusicTargetIds = chooseMusicTargets(
                            current.selectedMusicTargetIds,
                            reconciled,
                        ),
                    )
                }
                if (!isTransportAction) haptic()
            } catch (error: Throwable) {
                _state.update {
                    it.copy(
                        musicLoading = false,
                        musicTransportLoading = false,
                        musicError = friendlyError(error),
                    )
                }
            }
        }
    }

    private fun chooseMusicTargets(existing: Set<String>, music: MusicSnapshot): Set<String> {
        val available = music.targets.map { it.id }.toSet()
        val valid = existing.intersect(available)
        val local = valid.filterTo(mutableSetOf()) { id ->
            music.targets.firstOrNull { it.id == id }?.isLocal == true
        }
        if (local.isNotEmpty()) return local
        val server = music.player.targets.filter { it in available }.toSet()
        if (server.isNotEmpty()) return server
        if (valid.isNotEmpty()) return valid
        return music.targets.firstOrNull { !it.isLocal }?.id?.let(::setOf)
            ?: music.targets.firstOrNull { it.isLocal }?.id?.let(::setOf).orEmpty()
    }

    private fun reconcileMusicSnapshot(
        current: LittleSpudUiState,
        incoming: MusicSnapshot,
    ): MusicSnapshot {
        val localSelected = current.localMusicTrack != null ||
            current.selectedMusicTargetIds.any { targetId ->
                incoming.targets.firstOrNull { it.id == targetId }?.isLocal == true
            }
        if (!localSelected) return incoming

        // Music Core owns speaker volume, while phone playback owns its local
        // output volume. Preserve the latter when polling the shared snapshot;
        // otherwise an idle/default server value could raise the phone between
        // songs.
        return incoming.copy(
            player = incoming.player.copy(
                volumePercent = current.music.player.volumePercent,
            ),
        )
    }

    private fun startMusicStateSync() {
        val session = _state.value.session ?: return
        if (session.isDemo || _state.value.activeLane != LittleSpudLane.MUSIC || musicStateSyncJob != null) return
        musicStateSyncJob = viewModelScope.launch {
            while (isActive) {
                delay(4_000)
                val current = _state.value
                if (current.activeLane != LittleSpudLane.MUSIC) return@launch
                val latestSession = current.session ?: return@launch
                if (latestSession.isDemo || current.musicLoading) continue
                runCatching {
                    container.api.fetchMusic(
                        session = latestSession,
                        query = current.musicQuery,
                        refresh = false,
                    )
                }.onSuccess { music ->
                    if (_state.value.activeLane == LittleSpudLane.MUSIC &&
                        !_state.value.musicLoading &&
                        _state.value.session?.token == latestSession.token
                    ) {
                        _state.update { latest ->
                            val reconciled = reconcileMusicSnapshot(latest, music)
                            latest.copy(
                                music = reconciled,
                                selectedMusicTargetIds = chooseMusicTargets(
                                    latest.selectedMusicTargetIds,
                                    reconciled,
                                ),
                            )
                        }
                    }
                }
                // Background music-state sync is best-effort. Manual refresh
                // continues to surface connection errors to the user.
            }
        }
    }

    private fun stopMusicStateSync() {
        musicStateSyncJob?.cancel()
        musicStateSyncJob = null
    }

    fun setNotificationsEnabled(enabled: Boolean) {
        container.settings.notificationsEnabled = enabled
        _state.update { it.copy(notificationsEnabled = enabled) }
        if (enabled) syncPushRegistration(force = true) else disablePushRegistration()
    }

    fun toggleTts() {
        val enabled = !_state.value.ttsEnabled
        container.settings.ttsEnabled = enabled
        _state.update { it.copy(ttsEnabled = enabled) }
    }

    private fun syncPushRegistration(force: Boolean = false) {
        val session = _state.value.session ?: return
        if (session.isDemo || !_state.value.notificationsEnabled || !BuildConfig.FIREBASE_CONFIGURED) return
        if (pushJob?.isActive == true && !force) return
        pushJob?.cancel()
        pushJob = viewModelScope.launch {
            try {
                val token = container.secureStore.fcmToken().ifBlank {
                    if (FirebaseApp.getApps(getApplication()).isEmpty()) return@launch
                    @Suppress("DEPRECATION")
                    FirebaseMessaging.getInstance().token.await().also(container.secureStore::saveFcmToken)
                }
                val fingerprint = token.takeLast(24)
                var registration = container.secureStore.loadPushRegistration()
                if (force || registration?.tokenFingerprint != fingerprint || !registration.isComplete) {
                    registration = container.api.registerPushGateway(token, session)
                    container.secureStore.savePushRegistration(registration)
                }
                val updated = container.api.updatePushRegistration(session, registration, true)
                saveSession(updated)
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                // Pairing/chat remain fully functional when Firebase has not been provisioned server-side.
            }
        }
    }

    private fun disablePushRegistration() {
        val session = _state.value.session ?: return
        container.secureStore.clearPushRegistration()
        if (session.isDemo) return
        viewModelScope.launch { runCatching { container.api.updatePushRegistration(session, null, false) } }
    }

    fun markNotificationsRead() {
        container.settings.notificationUnreadCount = 0
        _state.update { it.copy(notificationUnreadCount = 0) }
    }

    private fun refreshNotificationsFromStore() {
        val notifications = container.messageStore.loadNotifications()
        val viewingNotifications = _state.value.activeLane == LittleSpudLane.NOTIFICATIONS
        val unread = if (viewingNotifications) 0 else container.settings.notificationUnreadCount
        if (viewingNotifications) container.settings.notificationUnreadCount = 0
        _state.update {
            it.copy(
                notifications = notifications,
                notificationUnreadCount = unread,
            )
        }
    }

    fun disconnect() {
        val session = _state.value.session
        pauseForegroundWork()
        cleanupVoiceInput(closeSocket = true)
        pendingLocalPlayback = null
        localMusicController?.run {
            stop()
            clearMediaItems()
        }
        container.secureStore.clearSession()
        container.secureStore.clearPushRegistration()
        container.messageStore.clear()
        _state.value = LittleSpudUiState(
            userName = container.settings.userName,
            deviceName = container.settings.defaultDeviceName(),
            notificationsEnabled = container.settings.notificationsEnabled,
            ttsEnabled = container.settings.ttsEnabled,
            temperatureUnitPreference = container.settings.temperatureUnitPreference,
            statusText = "Little Spud forgot this pairing.",
        )
        if (session != null && !session.isDemo) viewModelScope.launch { runCatching { container.api.forgetPairing(session) } }
    }

    private fun refreshFromHub(showStatus: Boolean) {
        val session = _state.value.session ?: return
        if (session.isDemo) return
        viewModelScope.launch {
            try {
                val updated = container.api.sendHeartbeat(session, _state.value.messages.size, preferHome = true)
                saveSession(updated)
                val sync = container.api.fetchHistoryState(updated)
                val named = if (sync.assistantName.isNotBlank()) updated.copy(assistantName = sync.assistantName) else updated
                saveSession(named)
                mergeHistory(sync.messages, sync.activeRuns)
                _state.update { it.copy(hubConnected = true, statusText = if (showStatus) "Synced with ${named.hubName}." else it.statusText) }
                syncPushRegistration()
            } catch (error: Throwable) {
                if (error is CancellationException) return@launch
                _state.update { it.copy(hubConnected = false, statusText = if (showStatus) friendlyError(error) else it.statusText, statusIsError = showStatus) }
            }
        }
    }

    private fun mergeHistory(incoming: List<HubHistoryMessage>, activeRuns: List<HubActiveRun>) {
        _state.update { current ->
            current.copy(
                messages = ChatHistoryReconciler.merge(
                    local = current.messages,
                    incoming = incoming,
                    activeRuns = activeRuns,
                    isSending = current.isSending,
                ),
            )
        }
        saveMessages()
    }

    private fun startNotificationPoll() {
        if (notificationPollJob?.isActive == true || _state.value.session?.isDemo != false) return
        notificationPollJob = viewModelScope.launch {
            while (isActive) {
                val session = _state.value.session ?: return@launch
                try {
                    val consume = !_state.value.notificationsEnabled
                    container.api.pollNotification(session, consume = consume)?.let { notification ->
                        appendNotification(notification)
                        if (!consume) scheduleNotificationAck(notification, session)
                    }
                } catch (_: CancellationException) {
                    return@launch
                } catch (_: Throwable) {
                    delay(5_000)
                }
            }
        }
    }

    private fun appendNotification(notification: HubNotification) {
        val local = LittleSpudMessage(
            id = notification.id,
            role = LittleSpudRole.ASSISTANT,
            content = notification.content,
            createdAt = notification.createdAt,
            kind = "notification",
            attachments = notification.attachments,
            notificationTitle = notification.title,
            notificationBody = notification.message,
            notificationPriority = notification.priority,
        )
        val added = container.messageStore.appendNotification(local)
        if (!added) return
        val unread = if (_state.value.activeLane == LittleSpudLane.NOTIFICATIONS) 0 else _state.value.notificationUnreadCount + 1
        container.settings.notificationUnreadCount = unread
        _state.update { it.copy(notifications = (it.notifications + local).distinctBy { message -> message.id }.sortedBy { message -> message.createdAt }, notificationUnreadCount = unread) }
    }

    private fun scheduleNotificationAck(notification: HubNotification, session: LittleSpudSession) {
        if (!pendingNotificationAcks.add(notification.id)) return
        viewModelScope.launch {
            delay(45_000)
            runCatching { container.api.acknowledgeNotification(session, notification.id) }
            pendingNotificationAcks.remove(notification.id)
        }
    }

    private fun startRouteProbe() {
        if (routeProbeJob?.isActive == true || _state.value.session?.isDemo != false) return
        routeProbeJob = viewModelScope.launch {
            while (isActive) {
                delay(30_000)
                refreshFromHub(showStatus = false)
            }
        }
    }

    private fun saveSession(session: LittleSpudSession) {
        container.secureStore.saveSession(session)
        _state.update { it.copy(session = session, hubUrl = session.hubUrl, hubConnected = true) }
    }

    private fun replaceMessage(id: String, transform: (LittleSpudMessage) -> LittleSpudMessage) {
        _state.update { current -> current.copy(messages = current.messages.map { if (it.id == id) transform(it) else it }) }
    }

    private fun saveMessages() = container.messageStore.saveMessages(_state.value.messages)
    private fun sortedMessages(messages: List<LittleSpudMessage>) = ChatHistoryReconciler.dedupeLocal(messages)

    private fun reopenMicAfterReply() {
        val current = _state.value
        if (current.session == null || current.isVoiceRecording || current.isVoiceSubmitting) return
        _state.update { it.copy(speechStatus = "I’m listening…") }
        pendingReopenMicJob?.cancel()
        pendingReopenMicJob = viewModelScope.launch {
            delay(250)
            pendingReopenMicJob = null
            val latest = _state.value
            if (latest.session == null || latest.isSending || latest.isVoiceRecording || latest.isVoiceSubmitting) return@launch
            openVoiceInput()
        }
    }

    private fun cancelPendingReopenMic() {
        pendingReopenMicJob?.cancel()
        pendingReopenMicJob = null
        _state.update { current ->
            if (current.speechStatus == "I’m listening…") current.copy(speechStatus = "") else current
        }
    }

    private fun playSpeech(session: LittleSpudSession, text: String): Job? {
        if (session.isDemo) return null
        return viewModelScope.launch {
            val cache = getApplication<Application>().cacheDir.resolve("little-spud-tts-${UUID.randomUUID()}.audio")
            var speechPlayer: ExoPlayer? = null
            try {
                val bytes = container.api.fetchSpeech(session, text)
                withContext(Dispatchers.IO) { cache.writeBytes(bytes) }
                val playbackFinished = CompletableDeferred<Unit>()
                speechPlayer = ExoPlayer.Builder(getApplication()).build().apply {
                    addListener(object : Player.Listener {
                        override fun onPlaybackStateChanged(playbackState: Int) {
                            if (playbackState == Player.STATE_ENDED) playbackFinished.complete(Unit)
                        }

                        override fun onPlayerError(error: PlaybackException) {
                            playbackFinished.complete(Unit)
                        }
                    })
                    setMediaItem(MediaItem.fromUri(cache.toURI().toString()))
                    prepare()
                    play()
                }
                withTimeoutOrNull(120_000) { playbackFinished.await() }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                // Speech playback is optional; a failed voice reply should still reopen the mic.
            } finally {
                speechPlayer?.release()
                cache.delete()
            }
        }
    }

    private fun haptic() {
        val context = getApplication<Application>()
        val vibrator = if (Build.VERSION.SDK_INT >= 31) context.getSystemService(VibratorManager::class.java).defaultVibrator
        else @Suppress("DEPRECATION") context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        if (vibrator.hasVibrator()) vibrator.vibrate(VibrationEffect.createOneShot(35, VibrationEffect.DEFAULT_AMPLITUDE))
    }

    private fun demoReply(text: String, attachments: List<LittleSpudAttachment>): String = when {
        attachments.isNotEmpty() -> "I can see the attached media. In a real pairing, I’d send it securely to your Tater for analysis."
        text.contains("light", true) -> "Demo complete — I’d route that request through your paired Tater’s home controls."
        text.contains("music", true) -> "The Android Music Core is ready. Open the Music tab to browse the demo library."
        text.isBlank() -> "What would you like to try?"
        else -> "This is the Android demo response to: “$text” Pair with Tater to use live tools and conversation history."
    }

    private fun demoHome(): HomeSnapshot = HomeSnapshot(
        rooms = listOf(
            com.tatertotterson.littlespud.android.model.HomeRoom(
                "living-room", "Living Room", 4, listOf("2 lights on", "72°F"),
                listOf(
                    HomeCategory("light", "Lights", 3, "mixed", "2 of 3 on", "power_brightness", listOf("turn_on", "turn_off", "set_brightness"), true, false, true, 68.0, onCount = 2),
                    HomeCategory("temperature", "Temperature", 1, "72", "72°F", "read_only", emptyList(), false, true, false, null, currentTemperature = 72.0),
                ),
            ),
            com.tatertotterson.littlespud.android.model.HomeRoom(
                "office", "Office", 2, listOf("All quiet"),
                listOf(HomeCategory("switch", "Desk", 1, "off", "Off", "power", listOf("turn_on", "turn_off"), true, false, false, null)),
            ),
        ),
        generatedAt = System.currentTimeMillis(),
    )

    private fun demoMusic(query: String = ""): MusicSnapshot {
        val tracks = listOf(
            MusicTrack("demo-1", "Morning on the Farm", "Tater & The Sprouts", "", "Homegrown", "Indie", 218.0, "3:38", "demo", ""),
            MusicTrack("demo-2", "Signals in the Soil", "Little Spud", "", "Root System", "Electronic", 244.0, "4:04", "demo", ""),
            MusicTrack("demo-3", "Lantern Kitchen", "The Satellites", "", "Rooms", "Ambient", 196.0, "3:16", "demo", ""),
        ).filter { query.isBlank() || it.title.contains(query, true) || it.artist.contains(query, true) }
        val local = com.tatertotterson.littlespud.android.model.MusicTarget("little_spud:local", "This Android device", "local")
        return MusicSnapshot(
            available = true,
            provider = com.tatertotterson.littlespud.android.model.MusicProvider("demo", "Demo Library", true, true, true),
            tracks = tracks,
            trackCount = tracks.size,
            artists = tracks.map { it.artist }.distinct(),
            albums = tracks.map { it.album }.distinct(),
            genres = tracks.map { it.genre }.distinct(),
            targets = listOf(local),
            recommendations = listOf(MusicRecommendation("demo-mix", "Tater’s Picks", "A small Android preview", tracks, "")),
        )
    }

    private fun friendlyError(error: Throwable): String = when (error) {
        is SpudLinkException -> error.message ?: "Little Spud could not complete that request."
        else -> error.localizedMessage?.takeIf { it.isNotBlank() } ?: "Little Spud could not complete that request."
    }

    override fun onCleared() {
        pauseForegroundWork()
        cleanupVoiceInput(closeSocket = true)
        localMusicProgressJob?.cancel()
        localMusicProgressJob = null
        pendingLocalPlayback = null
        localMusicController?.removeListener(localMusicPlayerListener)
        localMusicController = null
        localMusicControllerFuture?.let { MediaController.releaseFuture(it) }
        localMusicControllerFuture = null
        super.onCleared()
    }

    class Factory(
        private val application: Application,
        private val container: AppContainer,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T = LittleSpudViewModel(application, container) as T
    }

    private companion object {
        const val MAX_ATTACHMENT_BYTES = 8 * 1024 * 1024
        const val VOICE_SAMPLE_RATE = 16_000
        const val VOICE_BUFFER_BYTES = 4_096
    }
}

private fun java.io.InputStream.readBytes(maxBytes: Int): ByteArray {
    val output = ByteArrayOutputStream()
    val buffer = ByteArray(16 * 1024)
    while (true) {
        val count = read(buffer)
        if (count <= 0) break
        output.write(buffer, 0, count)
        if (output.size() > maxBytes) break
    }
    return output.toByteArray()
}
