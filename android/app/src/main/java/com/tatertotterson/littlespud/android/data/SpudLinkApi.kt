package com.tatertotterson.littlespud.android.data

import android.net.Uri
import android.os.Build
import android.util.Base64
import com.tatertotterson.littlespud.android.model.CameraPreview
import com.tatertotterson.littlespud.android.model.ConnectionRoute
import com.tatertotterson.littlespud.android.model.HomeCategory
import com.tatertotterson.littlespud.android.model.HomeRoom
import com.tatertotterson.littlespud.android.model.HomeSnapshot
import com.tatertotterson.littlespud.android.model.HubActiveRun
import com.tatertotterson.littlespud.android.model.HubHistoryMessage
import com.tatertotterson.littlespud.android.model.HubNotification
import com.tatertotterson.littlespud.android.model.HubSyncState
import com.tatertotterson.littlespud.android.model.LittleSpudAttachment
import com.tatertotterson.littlespud.android.model.LittleSpudMessage
import com.tatertotterson.littlespud.android.model.LittleSpudRole
import com.tatertotterson.littlespud.android.model.LittleSpudSession
import com.tatertotterson.littlespud.android.model.MusicPlayerState
import com.tatertotterson.littlespud.android.model.MusicProvider
import com.tatertotterson.littlespud.android.model.MusicRecommendation
import com.tatertotterson.littlespud.android.model.MusicSnapshot
import com.tatertotterson.littlespud.android.model.MusicTarget
import com.tatertotterson.littlespud.android.model.MusicTrack
import com.tatertotterson.littlespud.android.model.PairingInput
import com.tatertotterson.littlespud.android.model.PushRegistration
import com.tatertotterson.littlespud.android.model.booleanOrNull
import com.tatertotterson.littlespud.android.model.dateMillis
import com.tatertotterson.littlespud.android.model.doubleOrNull
import com.tatertotterson.littlespud.android.model.intValue
import com.tatertotterson.littlespud.android.model.objectArray
import com.tatertotterson.littlespud.android.model.objectOrNull
import com.tatertotterson.littlespud.android.model.objects
import com.tatertotterson.littlespud.android.model.string
import com.tatertotterson.littlespud.android.model.stringArray
import com.tatertotterson.littlespud.android.model.toJsonArray
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.job
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.TimeUnit

class SpudLinkException(message: String, val statusCode: Int? = null) : IOException(message)

data class ChatResponse(
    val content: String,
    val reopenMic: Boolean,
    val attachments: List<LittleSpudAttachment>,
)

data class ToolNotice(
    val id: String,
    val text: String,
    val runId: String,
    val tool: String,
    val phase: String,
    val createdAt: Long,
)

class SpudLinkApi(
    private val secureStore: SecureStore,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(70, TimeUnit.SECONDS)
        .writeTimeout(70, TimeUnit.SECONDS)
        .build(),
) {
    suspend fun pair(userName: String, deviceName: String, hubUrlInput: String, syncInput: String): LittleSpudSession {
        val cleanUser = userName.trim()
        val cleanDevice = deviceName.trim().ifBlank { "Android device" }
        if (cleanUser.isBlank()) throw SpudLinkException("Enter a user name first.")

        val sync = parsePairingInput(syncInput, hubUrlInput)
        val installId = secureStore.installId()
        val body = JSONObject().apply {
            put("pairing_code", sync.pairingCode)
            put("role", "little_spud")
            put("node_name", "$cleanUser on $cleanDevice")
            put("metadata", JSONObject().apply {
                put("client", CLIENT_ID)
                put("client_version", CLIENT_VERSION)
                put("app_install_id", installId)
                put("client_device_id", installId)
                put("user_name", cleanUser)
                put("device_name", cleanDevice)
                put("user_agent", "LittleSpud Android ${Build.VERSION.RELEASE}")
            })
        }

        var payload: JSONObject? = null
        var pairedUrl = sync.hubUrl
        var lastError: Throwable? = null
        sync.pairUrls.forEachIndexed { index, pairUrl ->
            if (payload != null) return@forEachIndexed
            try {
                payload = executeJson(
                    request = Request.Builder()
                        .url(validHttpUrl(pairUrl, "Pairing URL"))
                        .post(body.toString().toRequestBody(JSON_MEDIA_TYPE))
                        .header("Content-Type", "application/json")
                        .build(),
                    action = "Pairing",
                    timeoutSeconds = if (index == 0) 3 else 12,
                )
                pairedUrl = hubBaseFromApiUrl(pairUrl, "/api/spudlink/pair").ifBlank { sync.hubUrl }
            } catch (error: Throwable) {
                lastError = error
            }
        }
        val result = payload ?: throw (lastError ?: SpudLinkException("Could not reach Tater."))
        val token = result.string("node_token")
        if (token.isBlank()) throw SpudLinkException("Pairing succeeded but no node token was returned.")
        val node = result.objectOrNull("node")
        val hub = result.objectOrNull("hub") ?: result.objectOrNull("server")
        val now = System.currentTimeMillis()
        return LittleSpudSession(
            hubUrl = pairedUrl,
            homeHubUrl = sync.homeHubUrl,
            awayHubUrl = sync.awayHubUrl,
            activeRoute = when (pairedUrl) {
                sync.homeHubUrl -> ConnectionRoute.HOME
                sync.awayHubUrl -> ConnectionRoute.AWAY
                else -> ConnectionRoute.UNKNOWN
            },
            token = token,
            userName = cleanUser,
            deviceName = cleanDevice,
            nodeName = node?.string("name").orEmpty().ifBlank { "$cleanUser on $cleanDevice" },
            hubName = hub?.string("name").orEmpty().ifBlank { sync.hubUrl },
            hubMode = hub?.string("mode").orEmpty(),
            assistantName = hub?.string("assistant_name", "tater_name").orEmpty().ifBlank { "Tater" },
            toolsEnabled = hub?.booleanOrNull("tools_enabled"),
            pairedAt = now,
            lastSeenAt = now,
        )
    }

    suspend fun sendHeartbeat(session: LittleSpudSession, messageCount: Int, preferHome: Boolean = false): LittleSpudSession {
        val body = JSONObject().apply {
            put("node_name", session.displayNodeName)
            put("mode", "little_spud")
            put("version", CLIENT_VERSION)
            put("stats", JSONObject().apply {
                put("platform", "Android")
                put("system_version", Build.VERSION.RELEASE)
                put("device_model", "${Build.MANUFACTURER} ${Build.MODEL}".trim())
                put("online", true)
            })
            put("activity", JSONObject().apply {
                put("messages", messageCount)
                put("attachments_pending", 0)
            })
        }
        var lastError: Throwable? = null
        for ((url, route) in routeCandidates(session, preferHome)) {
            currentCoroutineContext().ensureActive()
            try {
                val candidate = session.copy(hubUrl = url, activeRoute = route)
                val request = authorizedRequest(candidate, "/api/spudlink/heartbeat")
                    .post(body.toString().toRequestBody(JSON_MEDIA_TYPE))
                    .build()
                val payload = executeJson(request, "Hub ping", if (route == ConnectionRoute.HOME) 3 else 12)
                return updatedSession(payload, candidate)
            } catch (error: Throwable) {
                lastError = error
            }
        }
        throw (lastError ?: SpudLinkException("Could not reach Tater."))
    }

    suspend fun fetchHistoryState(session: LittleSpudSession): HubSyncState {
        val payload = executeJson(
            authorizedRequest(session, "/api/spudlink/v1/history?limit=80").get().build(),
            "History sync",
            20,
        )
        val runs = payload.optJSONArray("active_runs")?.objects()
            ?: payload.objectOrNull("active_run")?.let(::listOf)
            ?: emptyList()
        val hub = payload.objectOrNull("server") ?: payload.objectOrNull("hub")
        return HubSyncState(
            messages = payload.objectArray("messages").mapNotNull { normalizeHistoryMessage(it, session) },
            activeRuns = runs.mapNotNull(::normalizeActiveRun),
            assistantName = payload.string("assistant_name").ifBlank {
                hub?.string("assistant_name", "tater_name").orEmpty()
            },
        )
    }

    suspend fun fetchHome(session: LittleSpudSession, refresh: Boolean = false): HomeSnapshot {
        val payload = executeJson(
            authorizedRequest(session, "/api/spudlink/v1/home?refresh=$refresh").get().build(),
            "Home sync",
            if (refresh) 35 else 15,
        )
        return normalizeHomeSnapshot(payload)
    }

    suspend fun controlHome(
        session: LittleSpudSession,
        roomId: String,
        categoryId: String,
        action: String,
        value: Double? = null,
        mode: String? = null,
        temperatureUnit: String? = null,
    ): HomeSnapshot {
        val body = JSONObject().apply {
            put("room_id", roomId); put("category_id", categoryId); put("action", action)
            value?.let { put("value", it) }
            mode?.takeIf { it.isNotBlank() }?.let { put("mode", it) }
            temperatureUnit?.takeIf { it.isNotBlank() }?.let { put("temperature_unit", it) }
        }
        val payload = executeJson(
            authorizedRequest(session, "/api/spudlink/v1/home/actions")
                .post(body.toString().toRequestBody(JSON_MEDIA_TYPE)).build(),
            "Home control",
            35,
        )
        return normalizeHomeSnapshot(payload)
    }

    suspend fun fetchCameraSnapshot(session: LittleSpudSession, roomId: String, cameraId: String): ByteArray {
        if (roomId.isBlank() || cameraId.isBlank()) throw SpudLinkException("Camera snapshot failed: camera unavailable.")
        val path = "/api/spudlink/v1/home/rooms/${encodePath(roomId)}/cameras/${encodePath(cameraId)}/snapshot"
        val bytes = executeBytes(
            authorizedRequest(session, path).header("Accept", "image/*").get().build(),
            "Camera snapshot",
            25,
        )
        if (bytes.isEmpty()) throw SpudLinkException("Camera snapshot failed: the camera returned no image.")
        if (bytes.size > 12 * 1024 * 1024) throw SpudLinkException("Camera snapshot failed: the image is too large.")
        return bytes
    }

    suspend fun fetchMusic(
        session: LittleSpudSession,
        query: String = "",
        refresh: Boolean = false,
        limit: Int? = null,
    ): MusicSnapshot {
        val trackLimit = (limit ?: if (query.isBlank()) 20 else 80).coerceIn(1, 200)
        val endpoint = Uri.parse(hubApiUrl(session.hubUrl, "/api/spudlink/v1/music")).buildUpon()
            .appendQueryParameter("query", query)
            .appendQueryParameter("limit", trackLimit.toString())
            .appendQueryParameter("refresh", refresh.toString())
            .build().toString()
        val request = authorizedRequestUrl(session, endpoint).get().build()
        return normalizeMusicSnapshot(executeJson(request, "Music", if (refresh) 185 else 25))
    }

    suspend fun controlMusic(
        session: LittleSpudSession,
        action: String,
        trackId: String = "",
        trackIds: List<String> = emptyList(),
        recommendationId: String = "",
        query: String = "",
        targets: List<String> = emptyList(),
        provider: String = "",
        volumePercent: Int = 75,
        positionSeconds: Double? = null,
    ): MusicSnapshot {
        val body = JSONObject().apply {
            put("action", action)
            put("volume_percent", volumePercent.coerceIn(0, 100))
            if (trackId.isNotBlank()) put("track_id", trackId)
            if (trackIds.isNotEmpty()) put("track_ids", trackIds.take(200).toJsonArray { it })
            if (recommendationId.isNotBlank()) put("recommendation_id", recommendationId)
            if (query.isNotBlank()) put("query", query)
            if (targets.isNotEmpty()) put("targets", targets.toJsonArray { it })
            if (provider.isNotBlank()) put("provider", provider)
            positionSeconds?.let { put("position_seconds", it.coerceAtLeast(0.0)) }
        }
        val payload = executeJson(
            authorizedRequest(session, "/api/spudlink/v1/music/actions")
                .post(body.toString().toRequestBody(JSON_MEDIA_TYPE)).build(),
            "Music control",
            if (action == "refresh") 185 else 50,
        )
        return normalizeMusicSnapshot(payload.objectOrNull("state") ?: payload)
    }

    fun musicStreamUrl(session: LittleSpudSession, track: MusicTrack): String {
        if (track.id.isBlank()) throw SpudLinkException("Music stream URL is not valid.")
        return Uri.parse(hubApiUrl(session.hubUrl, "/api/spudlink/v1/music/stream/${encodePath(track.id)}"))
            .buildUpon()
            .appendQueryParameter("provider", track.provider)
            .appendQueryParameter("token", session.token)
            .build().toString()
    }

    suspend fun pollNotification(
        session: LittleSpudSession,
        waitSeconds: Int = 20,
        consume: Boolean = true,
        eventId: String = "",
    ): HubNotification? {
        val wait = waitSeconds.coerceIn(1, 60)
        val endpoint = Uri.parse(hubApiUrl(session.hubUrl, "/api/spudlink/v1/notifications/next"))
            .buildUpon()
            .appendQueryParameter("wait_seconds", wait.toString())
            .appendQueryParameter("consume", consume.toString())
            .apply { if (eventId.isNotBlank()) appendQueryParameter("event_id", eventId) }
            .build().toString()
        val payload = executeJson(
            authorizedRequestUrl(session, endpoint).get().build(),
            "Notification poll",
            wait + 10L,
        )
        return payload.objectOrNull("notification")?.let(::normalizeNotification)
    }

    suspend fun acknowledgeNotification(session: LittleSpudSession, eventId: String) {
        if (eventId.isBlank()) return
        executeJson(
            authorizedRequest(session, "/api/spudlink/v1/notifications/${encodePath(eventId)}/ack")
                .post(EMPTY_BODY).build(),
            "Notification ack",
            10,
        )
    }

    suspend fun forgetPairing(session: LittleSpudSession) {
        if (session.isDemo) return
        var lastError: Throwable? = null
        for ((url, route) in routeCandidates(session, true)) {
            try {
                val candidate = session.copy(hubUrl = url, activeRoute = route)
                executeJson(
                    authorizedRequest(candidate, "/api/spudlink/v1/forget").post(EMPTY_BODY).build(),
                    "Forget pairing",
                    10,
                )
                return
            } catch (error: Throwable) {
                lastError = error
            }
        }
        lastError?.let { throw it }
    }

    suspend fun registerPushGateway(fcmToken: String, session: LittleSpudSession): PushRegistration {
        val token = fcmToken.trim()
        if (token.isBlank()) throw SpudLinkException("Firebase push token is missing.")
        val body = JSONObject().apply {
            put("provider", "fcm")
            put("app", "little_spud_android")
            put("platform", "android")
            put("environment", "production")
            put("bundle_id", APPLICATION_ID)
            put("fcm_token", token)
            put("device_name", session.deviceName)
            put("node_name", session.displayNodeName)
            put("client_version", CLIENT_VERSION)
            put("system_version", Build.VERSION.RELEASE)
            put("device_model", "${Build.MANUFACTURER} ${Build.MODEL}".trim())
        }
        val payload = executeJson(
            Request.Builder().url(PUSH_GATEWAY_REGISTER_URL)
                .post(body.toString().toRequestBody(JSON_MEDIA_TYPE)).build(),
            "Push gateway registration",
            15,
        )
        val deviceId = payload.string("push_device_id", "device_id")
        val secret = payload.string("push_secret", "secret")
        if (deviceId.isBlank() || secret.isBlank()) throw SpudLinkException("Push gateway did not return registration credentials.")
        return PushRegistration(
            provider = payload.string("provider").ifBlank { "fcm" },
            app = payload.string("app").ifBlank { "little_spud_android" },
            environment = payload.string("environment").ifBlank { "production" },
            pushDeviceId = deviceId,
            pushSecret = secret,
            gatewayUrl = payload.string("gateway_url", "relay_url", "send_url").ifBlank { PUSH_GATEWAY_SEND_URL },
            tokenFingerprint = token.takeLast(24),
            registeredAt = System.currentTimeMillis(),
        )
    }

    suspend fun updatePushRegistration(
        session: LittleSpudSession,
        registration: PushRegistration?,
        enabled: Boolean,
    ): LittleSpudSession {
        val body = JSONObject().apply {
            put("enabled", enabled)
            if (enabled && registration != null) {
                put("provider", registration.provider)
                put("app", registration.app)
                put("environment", registration.environment)
                put("push_device_id", registration.pushDeviceId)
                put("push_secret", registration.pushSecret)
                put("gateway_url", registration.gatewayUrl)
                put("registered_at", registration.registeredAt / 1000.0)
                put("metadata", JSONObject().apply {
                    put("client", CLIENT_ID)
                    put("client_version", CLIENT_VERSION)
                    put("app_install_id", secureStore.installId())
                })
            }
        }
        val payload = executeJson(
            authorizedRequest(session, "/api/spudlink/v1/push-registration")
                .post(body.toString().toRequestBody(JSON_MEDIA_TYPE)).build(),
            "Push registration",
            15,
        )
        return updatedSession(payload, session)
    }

    suspend fun fetchSpeech(session: LittleSpudSession, text: String): ByteArray {
        val body = JSONObject().put("text", text)
        return executeBytes(
            authorizedRequest(session, "/api/spudlink/v1/tts/speech")
                .post(body.toString().toRequestBody(JSON_MEDIA_TYPE)).build(),
            "TTS",
            70,
        )
    }

    fun sttStreamUrl(session: LittleSpudSession, sampleRate: Int, language: String = "en-US"): String {
        val base = Uri.parse(hubApiUrl(session.hubUrl, "/api/spudlink/v1/stt/stream"))
        val scheme = if (base.scheme.equals("https", true)) "wss" else "ws"
        return base.buildUpon().scheme(scheme)
            .appendQueryParameter("token", session.token)
            .appendQueryParameter("rate", sampleRate.coerceIn(8_000, 48_000).toString())
            .appendQueryParameter("bits", "16")
            .appendQueryParameter("channels", "1")
            .appendQueryParameter("language", language)
            .appendQueryParameter("user", session.userName)
            .appendQueryParameter("device", session.deviceName)
            .build().toString()
    }

    fun openSttStream(
        session: LittleSpudSession,
        sampleRate: Int,
        language: String,
        listener: WebSocketListener,
    ): WebSocket = client.newWebSocket(
        Request.Builder()
            .url(sttStreamUrl(session, sampleRate, language))
            .build(),
        listener,
    )

    suspend fun sendChat(
        session: LittleSpudSession,
        messages: List<LittleSpudMessage>,
        text: String,
        attachments: List<LittleSpudAttachment>,
        onToolNotice: suspend (ToolNotice) -> Unit,
        onResponseChunk: suspend (String) -> Unit,
    ): ChatResponse = withContext(Dispatchers.IO) {
        val history = messages
            .filter { it.role == LittleSpudRole.USER || it.role == LittleSpudRole.ASSISTANT }
            .filter { it.kind != "tool_notice" }
            .takeLast(14)
            .toJsonArray { JSONObject().put("role", it.role.wireName).put("content", it.content) }
        val cleanText = text.trim()
        val prompt = cleanText.ifBlank { "Please review the attached media." }
        val messageContent = JSONArray().put(JSONObject().put("type", "text").put("text", prompt + attachmentSummary(attachments)))
        val attachmentMetadata = attachments.toJsonArray { attachment ->
            JSONObject().apply {
                put("name", attachment.displayName); put("type", attachment.type); put("mimetype", attachment.type)
                put("size", attachment.size); put("data_url", attachment.dataUrl)
            }
        }
        val body = JSONObject().apply {
            put("user", session.userName); put("user_name", session.userName); put("device_name", session.deviceName)
            put("message", messageContent); put("history", history); put("attachments", attachmentMetadata)
            put("metadata", JSONObject().put("client", CLIENT_ID).put("client_version", CLIENT_VERSION)
                .put("transport", "tater_native_event_stream"))
        }
        val request = authorizedRequest(session, "/api/spudlink/v1/tater/chat")
            .post(body.toString().toRequestBody(JSON_MEDIA_TYPE))
            .header("Accept", "text/event-stream")
            .build()
        val streamingClient = client.newBuilder().callTimeout(10, TimeUnit.MINUTES).readTimeout(0, TimeUnit.MILLISECONDS).build()
        val call = streamingClient.newCall(request)
        currentCoroutineContext().job.invokeOnCompletion { call.cancel() }

        var content = ""
        var reopenMic = false
        val resultAttachments = mutableListOf<LittleSpudAttachment>()
        val seenNotices = mutableSetOf<String>()

        fun parseNotice(payload: JSONObject): ToolNotice {
            val wait = payload.objectOrNull("wait_payload")
            val runId = payload.string("run_id")
            val tool = payload.string("display_name", "tool").ifBlank { wait?.string("display_name", "tool").orEmpty() }
            val phase = payload.string("phase").ifBlank { wait?.string("phase").orEmpty() }.ifBlank { "tool_start" }
            val noticeText = payload.string("text", "wait_text")
            val key = "$runId|$tool|$phase|$noticeText"
            return ToolNotice(
                id = "tool-${key.hashCode()}", text = noticeText, runId = runId, tool = tool, phase = phase,
                createdAt = payload.dateMillis("createdAt", "created_at") ?: System.currentTimeMillis(),
            )
        }

        suspend fun handle(block: String): Boolean {
            var event = "message"
            val dataLines = mutableListOf<String>()
            block.lineSequence().forEach { raw ->
                if (raw.isEmpty() || raw.startsWith(":")) return@forEach
                val index = raw.indexOf(':')
                val field = if (index >= 0) raw.substring(0, index) else raw
                val value = if (index >= 0) raw.substring(index + 1).removePrefix(" ") else ""
                when (field) {
                    "event" -> event = value.trim().ifBlank { "message" }
                    "data" -> dataLines += value
                }
            }
            if (dataLines.isEmpty()) return false
            val data = dataLines.joinToString("\n")
            if (data.trim() == "[DONE]") return true
            val payload = runCatching { JSONObject(data) }.getOrNull() ?: return false
            when (event) {
                "tater.tool" -> {
                    val notice = parseNotice(payload)
                    if (notice.text.isNotBlank() && seenNotices.add(notice.id)) onToolNotice(notice)
                }
                "tater.response_chunk" -> payload.string("chunk", "content", "delta").takeIf { it.isNotBlank() }?.let {
                    content += it; onResponseChunk(it)
                }
                "tater.message" -> {
                    payload.optJSONArray("tool_notices")?.objects().orEmpty().forEach { item ->
                        val notice = parseNotice(item)
                        if (notice.text.isNotBlank() && seenNotices.add(notice.id)) onToolNotice(notice)
                    }
                    content = payload.string("content")
                    resultAttachments += normalizeAssistantArtifacts(payload.objectArray("artifacts"), session)
                }
                "tater.artifacts" -> resultAttachments += normalizeAssistantArtifacts(payload.objectArray("artifacts"), session)
                "tater.follow_up" -> payload.objectOrNull("follow_up")?.let { followUp ->
                    reopenMic = followUp.booleanOrNull("enabled") == true && followUp.booleanOrNull("reopen_mic") == true
                }
                "tater.error" -> throw SpudLinkException(payloadErrorMessage(payload, "Tater request failed."))
                "tater.done" -> return true
                "message" -> {
                    val first = payload.optJSONArray("choices")?.optJSONObject(0)
                    first?.objectOrNull("delta")?.string("content")?.takeIf { it.isNotBlank() }?.let {
                        content += it; onResponseChunk(it)
                    }
                    first?.objectOrNull("message")?.string("content")?.takeIf { it.isNotBlank() }?.let { content = it }
                }
            }
            return false
        }

        call.execute().use { response ->
            validate(response, "Chat request")
            val source = response.body.source()
            val block = StringBuilder()
            while (!source.exhausted()) {
                currentCoroutineContext().ensureActive()
                val line = source.readUtf8Line() ?: break
                if (line.isEmpty()) {
                    if (block.isNotEmpty() && handle(block.toString())) {
                        return@withContext ChatResponse(content, reopenMic, dedupeAttachments(resultAttachments))
                    }
                    block.clear()
                } else {
                    if (block.isNotEmpty()) block.append('\n')
                    block.append(line)
                }
            }
            if (block.isNotEmpty()) handle(block.toString())
        }
        ChatResponse(content, reopenMic, dedupeAttachments(resultAttachments))
    }

    fun parsePairingInput(rawInput: String, hubUrlInput: String): PairingInput {
        val input = rawInput.trim()
        val fallback = normalizeUrl(hubUrlInput)
        if (input.isBlank()) throw SpudLinkException("Enter a sync code or scan a QR payload.")
        if (input.startsWith("tater-spudlink://")) {
            val dataValue = Uri.parse(input).getQueryParameter("data")
                ?: throw SpudLinkException("QR payload is missing pairing data.")
            val decoded = decodeBase64Url(dataValue)
            val payload = runCatching { JSONObject(decoded.toString(Charsets.UTF_8)) }.getOrElse {
                throw SpudLinkException("QR payload is missing pairing data.")
            }
            return pairingInput(payload, fallback)
        }
        if (input.startsWith("{") || input.startsWith("[")) {
            val payload = runCatching { JSONObject(input) }.getOrElse {
                throw SpudLinkException("Pairing payload is not valid JSON.")
            }
            return pairingInput(payload, fallback)
        }
        if (fallback.isBlank()) throw SpudLinkException("Enter the Tater URL when using a manual pairing code.")
        val pairUrl = hubApiUrl(fallback, "/api/spudlink/pair")
        return PairingInput(fallback, fallback, "", pairUrl, listOf(pairUrl), input)
    }

    private fun pairingInput(payload: JSONObject, fallback: String): PairingInput {
        val routes = payload.objectOrNull("route_urls")
        val home = normalizeUrl(routes?.string("home", "local").orEmpty()
            .ifBlank { payload.string("home_url", "local_url", "lan_url") }.ifBlank { fallback })
        val away = normalizeUrl(routes?.string("away", "remote").orEmpty()
            .ifBlank { payload.string("away_url", "remote_url", "public_url") })
        val payloadHub = normalizeUrl(payload.string("hub_url", "server_url").ifBlank { home }.ifBlank { away }.ifBlank { fallback })
        val payloadPair = normalizeUrl(payload.string("pair_url"))
        val pairBase = hubBaseFromApiUrl(payloadPair, "/api/spudlink/pair")
        val hub = pairBase.ifBlank { payloadHub }.ifBlank { home }.ifBlank { away }
        val pairUrl = payloadPair.ifBlank { if (hub.isBlank()) "" else hubApiUrl(hub, "/api/spudlink/pair") }
        val code = payload.string("pairing_code", "code")
        if (code.isBlank()) throw SpudLinkException("Pairing payload is missing a code.")
        if (hub.isBlank() && pairUrl.isBlank()) throw SpudLinkException("Pairing payload is missing a Tater URL.")
        val pairUrls = listOf(
            home.takeIf { it.isNotBlank() }?.let { hubApiUrl(it, "/api/spudlink/pair") }.orEmpty(),
            away.takeIf { it.isNotBlank() }?.let { hubApiUrl(it, "/api/spudlink/pair") }.orEmpty(),
            pairUrl,
        ).filter { it.isNotBlank() }.distinct()
        return PairingInput(hub.ifBlank { hubBaseFromApiUrl(pairUrl, "/api/spudlink/pair") }, home, away, pairUrl, pairUrls, code)
    }

    private fun updatedSession(payload: JSONObject, session: LittleSpudSession): LittleSpudSession {
        val node = payload.objectOrNull("node")
        val hub = payload.objectOrNull("server") ?: payload.objectOrNull("hub")
        return session.copy(
            nodeName = node?.string("name").orEmpty().ifBlank { session.nodeName },
            hubName = hub?.string("name").orEmpty().ifBlank { session.hubName },
            hubMode = hub?.string("mode").orEmpty().ifBlank { session.hubMode },
            assistantName = hub?.string("assistant_name", "tater_name").orEmpty().ifBlank { session.assistantName },
            toolsEnabled = hub?.booleanOrNull("tools_enabled") ?: session.toolsEnabled,
            lastSeenAt = System.currentTimeMillis(),
        )
    }

    private fun normalizeHistoryMessage(item: JSONObject, session: LittleSpudSession): HubHistoryMessage? {
        val role = LittleSpudRole.fromWire(item.string("role")) ?: return null
        val rawAttachments = item.optJSONArray("attachments")?.objects() ?: item.optJSONArray("artifacts")?.objects().orEmpty()
        val attachments = normalizeAssistantArtifacts(rawAttachments, session)
        val content = normalizeHistoryContent(item.string("content"), role, attachments)
        if (content.isBlank() && attachments.isEmpty()) return null
        return HubHistoryMessage(
            id = item.string("id").ifBlank { UUID.randomUUID().toString() }, role = role, content = content,
            createdAt = item.dateMillis("createdAt", "created_at", "ts") ?: System.currentTimeMillis(),
            kind = item.objectOrNull("meta")?.string("kind"), attachments = attachments,
        )
    }

    private fun normalizeHomeSnapshot(payload: JSONObject): HomeSnapshot {
        val rooms = payload.objectArray("rooms").mapNotNull { room ->
            val roomId = room.string("id"); if (roomId.isBlank()) return@mapNotNull null
            val categories = room.objectArray("categories").mapNotNull { category ->
                val categoryId = category.string("id"); if (categoryId.isBlank()) return@mapNotNull null
                val actions = category.stringArray("available_actions")
                val cameras = category.objectArray("camera_previews").mapNotNull { preview ->
                    preview.string("id").takeIf { it.isNotBlank() }?.let { CameraPreview(it, preview.string("label").ifBlank { "Camera" }) }
                }
                val controllable = category.booleanOrNull("controllable") ?: actions.isNotEmpty()
                HomeCategory(
                    id = categoryId,
                    name = category.string("name").ifBlank { categoryId.replace('_', ' ').titleCase() },
                    count = category.intValue("count"),
                    state = category.string("state").ifBlank { "unknown" },
                    summary = category.string("summary", "reading").ifBlank { "Status unavailable" },
                    controlType = category.string("control_type").ifBlank { "read_only" },
                    availableActions = actions,
                    controllable = controllable,
                    readOnly = category.booleanOrNull("read_only") ?: !controllable,
                    supportsBrightness = category.booleanOrNull("supports_brightness") ?: false,
                    brightness = category.doubleOrNull("brightness"),
                    onCount = category.opt("on_count").takeUnless { it == null || it === JSONObject.NULL }?.let { category.intValue("on_count") },
                    openCount = category.opt("open_count").takeUnless { it == null || it === JSONObject.NULL }?.let { category.intValue("open_count") },
                    currentTemperature = category.doubleOrNull("current_temperature"),
                    targetTemperature = category.doubleOrNull("target_temperature"),
                    temperatureUnit = category.string("temperature_unit").ifBlank { "F" },
                    hvacMode = category.string("hvac_mode"),
                    availableHvacModes = category.stringArray("available_hvac_modes"),
                    minimumTemperature = category.doubleOrNull("minimum_temperature"),
                    maximumTemperature = category.doubleOrNull("maximum_temperature"),
                    temperatureStep = category.doubleOrNull("temperature_step"),
                    cameraPreviews = cameras,
                )
            }
            HomeRoom(roomId, room.string("name").ifBlank { "Room" }, room.intValue("device_count"), room.stringArray("summary"), categories)
        }
        return HomeSnapshot(rooms, payload.dateMillis("generated_at", "generatedAt") ?: System.currentTimeMillis())
    }

    private fun normalizeMusicSnapshot(payload: JSONObject): MusicSnapshot {
        val provider = normalizeMusicProvider(payload.objectOrNull("provider"))
        val providers = payload.objectArray("providers").mapNotNull(::normalizeMusicProvider)
        val tracks = payload.objectArray("tracks").mapNotNull(::normalizeMusicTrack)
        val feed = payload.objectOrNull("track_feed") ?: JSONObject()
        val recommendations = payload.objectArray("recommendations").mapNotNull { item ->
            val id = item.string("id"); if (id.isBlank()) return@mapNotNull null
            MusicRecommendation(
                id, item.string("name", "title").ifBlank { "Tater Mix" }, item.string("description", "subtitle"),
                item.objectArray("tracks").mapNotNull(::normalizeMusicTrack), item.string("artwork_url"),
            )
        }
        val targets = payload.objectArray("targets").mapNotNull { item ->
            val id = item.string("id", "value"); if (id.isBlank()) return@mapNotNull null
            val transportOptions = item.optJSONArray("transport_options")?.let { array ->
                buildList {
                    for (index in 0 until array.length()) {
                        val value = when (val option = array.opt(index)) {
                            is JSONObject -> option.string("value")
                            else -> option?.toString().orEmpty()
                        }
                        if (value.isNotBlank()) add(value)
                    }
                }
            }.orEmpty()
            MusicTarget(
                id, item.string("label", "name").ifBlank { id }, item.string("kind").ifBlank { "player" },
                item.string("description", "meta"), item.string("airplay_bridge_target"), item.string("transport_mode"), transportOptions,
            )
        }
        val playerJson = payload.objectOrNull("player") ?: JSONObject()
        val player = MusicPlayerState(
            status = playerJson.string("status").ifBlank { "idle" },
            provider = playerJson.string("provider"),
            current = normalizeMusicTrack(playerJson.objectOrNull("current")),
            targets = playerJson.stringArray("targets"),
            queueCount = playerJson.intValue("queue_count"),
            queueIndex = playerJson.intValue("queue_index", -1),
            queue = playerJson.objectArray("queue").mapNotNull(::normalizeMusicTrack),
            shuffle = playerJson.booleanOrNull("shuffle") ?: false,
            repeatMode = playerJson.string("repeat").ifBlank { "off" },
            continuousRadio = playerJson.booleanOrNull("continuous_radio") ?: false,
            radioName = playerJson.string("radio_name"),
            positionSeconds = playerJson.doubleOrNull("position_seconds")?.coerceAtLeast(0.0) ?: 0.0,
            durationSeconds = playerJson.doubleOrNull("duration_seconds")?.coerceAtLeast(0.0) ?: 0.0,
            seekable = playerJson.booleanOrNull("seekable") ?: false,
            volumePercent = playerJson.intValue("volume_percent", 75).coerceIn(0, 100),
        )
        val syncedAt = payload.doubleOrNull("synced_at")?.takeIf { it > 0 }?.let { (it * 1000).toLong() }
        return MusicSnapshot(
            available = payload.booleanOrNull("available") ?: true,
            provider = provider,
            providers = providers,
            tracks = tracks,
            trackFeedKind = feed.string("kind").ifBlank { "library" },
            trackFeedTitle = feed.string("title").ifBlank { "Library" },
            trackFeedSummary = feed.string("summary"),
            trackCount = payload.intValue("track_count", tracks.size),
            artists = payload.stringArray("artists"), albums = payload.stringArray("albums"), genres = payload.stringArray("genres"),
            recommendations = recommendations, recommendationSummary = payload.string("recommendation_summary"),
            targets = targets, player = player, syncedAt = syncedAt,
        )
    }

    private fun normalizeMusicProvider(item: JSONObject?): MusicProvider? {
        item ?: return null
        val id = item.string("id"); if (id.isBlank()) return null
        return MusicProvider(
            id, item.string("label").ifBlank { id.replace('_', ' ').titleCase() },
            item.booleanOrNull("connected") ?: false, item.booleanOrNull("active") ?: false,
            item.booleanOrNull("local_playback") ?: false,
        )
    }

    private fun normalizeMusicTrack(item: JSONObject?): MusicTrack? {
        item ?: return null
        val id = item.string("id"); val title = item.string("title")
        if (id.isBlank() || title.isBlank()) return null
        val duration = item.doubleOrNull("duration_seconds") ?: 0.0
        val display = item.string("duration_display").ifBlank {
            if (duration > 0) "%d:%02d".format(duration.toInt() / 60, duration.toInt() % 60) else ""
        }
        return MusicTrack(
            id, title, item.string("artist"), item.string("album_artist"), item.string("album"), item.string("genre"),
            duration, display, item.string("provider"), item.string("artwork_url"),
        )
    }

    private fun normalizeActiveRun(item: JSONObject): HubActiveRun? {
        val id = item.string("run_id", "id"); if (id.isBlank()) return null
        val now = System.currentTimeMillis()
        return HubActiveRun(
            id, item.string("status").ifBlank { "running" }, item.string("phase").ifBlank { "thinking" },
            item.string("text", "wait_text").ifBlank { "Tater is thinking" },
            item.dateMillis("started_at", "startedAt", "created_at", "createdAt") ?: now,
            item.dateMillis("updated_at", "updatedAt", "started_at", "startedAt") ?: now,
        )
    }

    private fun normalizeNotification(item: JSONObject): HubNotification? {
        val title = item.string("title"); val message = item.string("message", "content")
        if (title.isBlank() && message.isBlank()) return null
        return HubNotification(
            item.string("id").ifBlank { UUID.randomUUID().toString() }, title, message,
            item.dateMillis("createdAt", "created_at", "ts") ?: System.currentTimeMillis(),
            item.string("priority").ifBlank { item.objectOrNull("meta")?.string("priority").orEmpty() }.ifBlank { "normal" },
        )
    }

    private fun normalizeAssistantArtifacts(items: List<JSONObject>, session: LittleSpudSession): List<LittleSpudAttachment> =
        items.mapNotNull { item ->
            val kind = item.string("type").lowercase()
            val type = item.string("mimetype", "mime_type").ifBlank {
                when (kind) { "image" -> "image/remote"; "video" -> "video/remote"; "audio" -> "audio/remote"; else -> "application/octet-stream" }
            }
            val preview = spudLinkMediaUrl(item.string("previewUrl", "preview_url", "url", "uri"), session)
            val data = item.string("dataUrl", "data_url")
            val name = item.string("name", "filename").ifBlank { "attachment" }
            if (preview.isBlank() && data.isBlank() && name.isBlank()) return@mapNotNull null
            LittleSpudAttachment(
                item.string("id", "file_id").ifBlank { UUID.randomUUID().toString() }, name, type,
                item.intValue("size"), preview, data,
            )
        }

    private fun normalizeHistoryContent(value: String, role: LittleSpudRole, attachments: List<LittleSpudAttachment>): String {
        var text = value.trim()
        if (role != LittleSpudRole.USER || attachments.isEmpty()) return text
        val markerIndex = text.indexOf("\nAttached media:", ignoreCase = true)
        if (markerIndex >= 0) text = text.substring(0, markerIndex).trim()
        if (text.trim('.', ' ', '\n', '\r').equals("Please review the attached media", true) || text.isBlank()) {
            val images = attachments.count { it.type.lowercase().startsWith("image/") }
            return if (images == attachments.size) if (attachments.size == 1) "Attached image" else "Attached images" else "Attached media"
        }
        return text
    }

    private fun attachmentSummary(attachments: List<LittleSpudAttachment>): String {
        if (attachments.isEmpty()) return ""
        return attachments.mapIndexed { index, item ->
            "${index + 1}. ${item.displayName} (${item.type}, ${formatBytes(item.size)})"
        }.joinToString("\n", prefix = "\n\nAttached media:\n")
    }

    private fun formatBytes(size: Int): String = when {
        size < 1024 -> "$size B"
        size < 1024 * 1024 -> "%.1f KB".format(size / 1024.0)
        else -> "%.1f MB".format(size / (1024.0 * 1024.0))
    }

    private fun dedupeAttachments(items: List<LittleSpudAttachment>): List<LittleSpudAttachment> =
        items.distinctBy { "${it.id}|${it.previewUrl}|${it.dataUrl}|${it.name}|${it.type}" }

    private fun spudLinkMediaUrl(value: String, session: LittleSpudSession): String {
        val raw = value.trim(); if (raw.isBlank()) return ""
        val absolute = if (raw.startsWith('/')) hubApiUrl(session.hubUrl, raw) else raw
        val uri = runCatching { Uri.parse(absolute) }.getOrNull() ?: return absolute
        if (!isSpudLinkApiPath(uri.path.orEmpty())) return absolute
        return uri.buildUpon().clearQuery().apply {
            uri.queryParameterNames.filter { it != "token" }.forEach { key ->
                uri.getQueryParameters(key).forEach { appendQueryParameter(key, it) }
            }
            appendQueryParameter("token", session.token)
        }.build().toString()
    }

    private fun isSpudLinkApiPath(path: String): Boolean =
        path.startsWith("/api/spudlink/") || path.contains("/api/spudlink/")

    private fun routeCandidates(session: LittleSpudSession, preferHome: Boolean): List<Pair<String, ConnectionRoute>> {
        val candidates = if (preferHome) listOf(
            session.homeHubUrl to ConnectionRoute.HOME,
            session.awayHubUrl to ConnectionRoute.AWAY,
            session.hubUrl to session.routeFor(session.hubUrl),
        ) else listOf(
            session.hubUrl to session.routeFor(session.hubUrl),
            session.homeHubUrl to ConnectionRoute.HOME,
            session.awayHubUrl to ConnectionRoute.AWAY,
        )
        return candidates.map { normalizeUrl(it.first) to it.second }.filter { it.first.isNotBlank() }.distinctBy { it.first }
    }

    private fun authorizedRequest(session: LittleSpudSession, path: String): Request.Builder =
        authorizedRequestUrl(session, hubApiUrl(session.hubUrl, path))

    private fun authorizedRequestUrl(session: LittleSpudSession, url: String): Request.Builder = Request.Builder()
        .url(validHttpUrl(url, "Tater URL"))
        .header("Content-Type", "application/json")
        .header("Accept", "application/json")
        .header("Authorization", "Bearer ${session.token}")
        .header("X-SpudLink-User", session.userName)
        .header("X-SpudLink-Device", session.deviceName)

    private suspend fun executeJson(request: Request, action: String, timeoutSeconds: Long): JSONObject {
        val bytes = executeBytes(request, action, timeoutSeconds)
        if (bytes.isEmpty()) return JSONObject()
        val payload = runCatching { JSONObject(bytes.toString(Charsets.UTF_8)) }.getOrElse {
            throw SpudLinkException("$action returned an invalid response.")
        }
        if (payload.booleanOrNull("ok") == false || (payload.has("error") && payload.opt("error") !== JSONObject.NULL)) {
            throw SpudLinkException("$action failed: ${payloadErrorMessage(payload, "Unknown error")}")
        }
        return payload
    }

    private suspend fun executeBytes(request: Request, action: String, timeoutSeconds: Long): ByteArray = withContext(Dispatchers.IO) {
        val requestClient = client.newBuilder().callTimeout(timeoutSeconds, TimeUnit.SECONDS).build()
        val call = requestClient.newCall(request)
        currentCoroutineContext().job.invokeOnCompletion { call.cancel() }
        call.execute().use { response ->
            val bytes = response.body.bytes()
            validate(response, action, bytes)
            bytes
        }
    }

    private fun validate(response: Response, action: String, bytes: ByteArray = ByteArray(0)) {
        if (response.isSuccessful) return
        val payload = runCatching { JSONObject(bytes.toString(Charsets.UTF_8)) }.getOrNull()
        val fallback = response.message.ifBlank { "HTTP ${response.code}" }
        throw SpudLinkException("$action failed: ${payload?.let { payloadErrorMessage(it, fallback) } ?: fallback}", response.code)
    }

    private fun payloadErrorMessage(payload: JSONObject, fallback: String): String {
        payload.string("detail").takeIf { it.isNotBlank() }?.let { return it }
        when (val error = payload.opt("error")) {
            is JSONObject -> error.string("message").takeIf { it.isNotBlank() }?.let { return it }
            is String -> error.takeIf { it.isNotBlank() }?.let { return it }
        }
        return fallback
    }

    private fun normalizeUrl(value: String): String {
        var trimmed = value.trim(); if (trimmed.isBlank()) return ""
        trimmed = when {
            trimmed.startsWith("//") -> "http:$trimmed"
            "://" !in trimmed -> "http://$trimmed"
            else -> trimmed
        }
        return trimmed.trimEnd('/')
    }

    private fun hubApiUrl(hubUrl: String, path: String): String =
        normalizeUrl(hubUrl).trimEnd('/') + if (path.startsWith('/')) path else "/$path"

    private fun hubBaseFromApiUrl(apiUrl: String, endpoint: String): String {
        val normalized = normalizeUrl(apiUrl); if (normalized.isBlank()) return ""
        val index = normalized.indexOf(endpoint); return if (index >= 0) normalized.substring(0, index).trimEnd('/') else ""
    }

    private fun validHttpUrl(value: String, label: String): String {
        val uri = runCatching { Uri.parse(value) }.getOrNull()
        if (uri == null || uri.scheme !in setOf("http", "https") || uri.host.isNullOrBlank()) {
            throw SpudLinkException("$label is not a valid URL.")
        }
        return value
    }

    private fun decodeBase64Url(value: String): ByteArray = runCatching {
        Base64.decode(value, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    }.getOrElse { throw SpudLinkException("QR payload is missing pairing data.") }

    private fun encodePath(value: String): String = URLEncoder.encode(value, StandardCharsets.UTF_8.name()).replace("+", "%20")

    private fun String.titleCase(): String = split(' ').joinToString(" ") { word ->
        word.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
    }

    private companion object {
        const val CLIENT_VERSION = "1.0.0"
        const val CLIENT_ID = "little-spud-android"
        const val APPLICATION_ID = "com.tatertotterson.littlespud.android"
        const val PUSH_GATEWAY_REGISTER_URL = "https://push.taterassistant.com/little-spud/register"
        const val PUSH_GATEWAY_SEND_URL = "https://push.taterassistant.com/little-spud/send"
        val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        val EMPTY_BODY = ByteArray(0).toRequestBody(JSON_MEDIA_TYPE)
    }
}
