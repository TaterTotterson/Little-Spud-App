package com.tatertotterson.littlespud.android.model

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.util.Locale
import java.util.UUID

enum class LittleSpudRole(val wireName: String) {
    USER("user"), ASSISTANT("assistant"), SYSTEM("system");

    companion object {
        fun fromWire(value: String): LittleSpudRole? = entries.firstOrNull { it.wireName == value }
    }
}

enum class ConnectionRoute(val wireName: String) {
    HOME("home"), AWAY("away"), UNKNOWN("unknown");

    companion object {
        fun fromWire(value: String): ConnectionRoute = entries.firstOrNull { it.wireName == value } ?: UNKNOWN
    }
}

enum class LittleSpudLane { NOTIFICATIONS, CHAT, HOME, MUSIC }

enum class TemperatureUnitPreference(
    val storageValue: String,
    val label: String,
    val description: String,
) {
    AUTOMATIC("automatic", "Auto", "Use the thermostat's unit when available."),
    FAHRENHEIT("fahrenheit", "°F", "Show temperatures in Fahrenheit."),
    CELSIUS("celsius", "°C", "Show temperatures in Celsius.");

    fun resolvedUnit(reportedUnit: String): String = when (this) {
        AUTOMATIC -> if (reportedUnit.equals("C", ignoreCase = true)) "C" else "F"
        FAHRENHEIT -> "F"
        CELSIUS -> "C"
    }

    companion object {
        fun fromStorage(value: String): TemperatureUnitPreference =
            entries.firstOrNull { it.storageValue == value } ?: AUTOMATIC
    }
}

data class LittleSpudSession(
    val hubUrl: String,
    val homeHubUrl: String = "",
    val awayHubUrl: String = "",
    val activeRoute: ConnectionRoute = ConnectionRoute.UNKNOWN,
    val token: String,
    val userName: String,
    val deviceName: String,
    val nodeName: String,
    val hubName: String,
    val hubMode: String,
    val assistantName: String = "Tater",
    val toolsEnabled: Boolean? = null,
    val pairedAt: Long = System.currentTimeMillis(),
    val lastSeenAt: Long = System.currentTimeMillis(),
) {
    val displayNodeName: String get() = nodeName.ifBlank { "$userName on $deviceName" }
    val isDemo: Boolean get() = hubUrl == "demo://little-spud" || token == "little-spud-demo-token"
    val displayRoute: ConnectionRoute get() = if (activeRoute == ConnectionRoute.UNKNOWN) routeFor(hubUrl) else activeRoute

    fun routeFor(url: String): ConnectionRoute {
        val clean = url.cleanUrl()
        return when {
            homeHubUrl.isNotBlank() && clean == homeHubUrl.cleanUrl() -> ConnectionRoute.HOME
            awayHubUrl.isNotBlank() && clean == awayHubUrl.cleanUrl() -> ConnectionRoute.AWAY
            else -> ConnectionRoute.UNKNOWN
        }
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("hubUrl", hubUrl)
        put("homeHubUrl", homeHubUrl)
        put("awayHubUrl", awayHubUrl)
        put("activeRoute", activeRoute.wireName)
        put("token", token)
        put("userName", userName)
        put("deviceName", deviceName)
        put("nodeName", nodeName)
        put("hubName", hubName)
        put("hubMode", hubMode)
        put("assistantName", assistantName)
        put("toolsEnabled", toolsEnabled ?: JSONObject.NULL)
        put("pairedAt", pairedAt)
        put("lastSeenAt", lastSeenAt)
    }

    companion object {
        fun fromJson(json: JSONObject): LittleSpudSession {
            val hubUrl = json.string("hubUrl")
            var home = json.string("homeHubUrl")
            val away = json.string("awayHubUrl")
            var route = ConnectionRoute.fromWire(json.string("activeRoute"))
            if (home.isBlank() && away.isBlank()) {
                home = hubUrl
                route = ConnectionRoute.HOME
            }
            val provisional = LittleSpudSession(
                hubUrl = hubUrl,
                homeHubUrl = home,
                awayHubUrl = away,
                activeRoute = route,
                token = json.string("token"),
                userName = json.string("userName"),
                deviceName = json.string("deviceName"),
                nodeName = json.string("nodeName"),
                hubName = json.string("hubName"),
                hubMode = json.string("hubMode"),
                assistantName = json.string("assistantName").ifBlank { "Tater" },
                toolsEnabled = json.booleanOrNull("toolsEnabled"),
                pairedAt = json.longValue("pairedAt", System.currentTimeMillis()),
                lastSeenAt = json.longValue("lastSeenAt", System.currentTimeMillis()),
            )
            return if (route == ConnectionRoute.UNKNOWN) provisional.copy(activeRoute = provisional.routeFor(hubUrl)) else provisional
        }
    }
}

data class LittleSpudAttachment(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val type: String,
    val size: Int,
    val previewUrl: String = "",
    val dataUrl: String = "",
) {
    val displayName: String get() = name.trim().ifBlank { "attachment" }

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id); put("name", name); put("type", type); put("size", size)
        put("previewUrl", previewUrl); put("dataUrl", dataUrl)
    }

    companion object {
        fun fromJson(json: JSONObject) = LittleSpudAttachment(
            id = json.string("id").ifBlank { UUID.randomUUID().toString() },
            name = json.string("name"),
            type = json.string("type"),
            size = json.intValue("size"),
            previewUrl = json.string("previewUrl", "preview_url", "url"),
            dataUrl = json.string("dataUrl", "data_url"),
        )
    }
}

data class LittleSpudMessage(
    val id: String = UUID.randomUUID().toString(),
    val role: LittleSpudRole,
    val content: String,
    val createdAt: Long = System.currentTimeMillis(),
    val kind: String? = null,
    val attachments: List<LittleSpudAttachment> = emptyList(),
    val notificationTitle: String? = null,
    val notificationBody: String? = null,
    val notificationPriority: String? = null,
) {
    val notificationDisplayBody: String
        get() = notificationBodyParts().first

    val notificationFaceIdSummary: String?
        get() = notificationBodyParts().second.ifBlank { null }

    private fun notificationBodyParts(): Pair<String, String> {
        val explicitBody = notificationBody.orEmpty().trim()
        val rawBody = when {
            explicitBody.isNotBlank() -> explicitBody
            content.contains("\n\n") -> content.substringAfter("\n\n")
            else -> content
        }
        var faceSummary = ""
        val bodyLines = rawBody.lines().filterNot { line ->
            val trimmed = line.trim()
            if (trimmed.startsWith("Face ID:", ignoreCase = true)) {
                faceSummary = trimmed.substringAfter(':').trim().trimEnd('.')
                true
            } else {
                false
            }
        }
        return bodyLines.joinToString("\n").trim() to faceSummary
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id); put("role", role.wireName); put("content", content); put("createdAt", createdAt)
        put("kind", kind ?: JSONObject.NULL)
        put("attachments", attachments.toJsonArray { it.toJson() })
        put("notificationTitle", notificationTitle ?: JSONObject.NULL)
        put("notificationBody", notificationBody ?: JSONObject.NULL)
        put("notificationPriority", notificationPriority ?: JSONObject.NULL)
    }

    companion object {
        fun fromJson(json: JSONObject): LittleSpudMessage? {
            val role = LittleSpudRole.fromWire(json.string("role")) ?: return null
            return LittleSpudMessage(
                id = json.string("id").ifBlank { UUID.randomUUID().toString() },
                role = role,
                content = json.string("content"),
                createdAt = json.dateMillis("createdAt", "created_at", "ts") ?: System.currentTimeMillis(),
                kind = json.nullableString("kind"),
                attachments = json.objectArray("attachments").map(LittleSpudAttachment::fromJson),
                notificationTitle = json.nullableString("notificationTitle"),
                notificationBody = json.nullableString("notificationBody"),
                notificationPriority = json.nullableString("notificationPriority"),
            )
        }
    }
}

data class PairingInput(
    val hubUrl: String,
    val homeHubUrl: String,
    val awayHubUrl: String,
    val pairUrl: String,
    val pairUrls: List<String>,
    val pairingCode: String,
)

data class HubHistoryMessage(
    val id: String,
    val role: LittleSpudRole,
    val content: String,
    val createdAt: Long,
    val kind: String?,
    val attachments: List<LittleSpudAttachment> = emptyList(),
)

data class HubActiveRun(
    val id: String,
    val status: String,
    val phase: String,
    val text: String,
    val startedAt: Long,
    val updatedAt: Long,
)

data class HubSyncState(
    val messages: List<HubHistoryMessage>,
    val activeRuns: List<HubActiveRun>,
    val assistantName: String,
)

data class HubNotification(
    val id: String,
    val title: String,
    val message: String,
    val createdAt: Long,
    val priority: String,
    val attachments: List<LittleSpudAttachment> = emptyList(),
) {
    val content: String get() = when {
        title.isNotBlank() && message.isNotBlank() -> "$title\n\n$message"
        title.isBlank() -> message
        else -> title
    }
}

data class HomeSnapshot(val rooms: List<HomeRoom> = emptyList(), val generatedAt: Long = 0L)

data class HomeRoom(
    val id: String,
    val name: String,
    val deviceCount: Int,
    val summary: List<String>,
    val categories: List<HomeCategory>,
) {
    val sensors: List<HomeCategory> get() = categories.filter { it.readOnly && it.id != "camera" }
    val controls: List<HomeCategory> get() = categories.filterNot { it.readOnly }
    val cameras: HomeCategory? get() = categories.firstOrNull { it.id == "camera" }
}

data class CameraPreview(val id: String, val label: String)

data class HomeCategory(
    val id: String,
    val name: String,
    val count: Int,
    val state: String,
    val summary: String,
    val controlType: String,
    val availableActions: List<String>,
    val controllable: Boolean,
    val readOnly: Boolean,
    val supportsBrightness: Boolean,
    val brightness: Double?,
    val onCount: Int? = null,
    val openCount: Int? = null,
    val currentTemperature: Double? = null,
    val targetTemperature: Double? = null,
    val temperatureUnit: String = "F",
    val hvacMode: String = "",
    val availableHvacModes: List<String> = emptyList(),
    val minimumTemperature: Double? = null,
    val maximumTemperature: Double? = null,
    val temperatureStep: Double? = null,
    val cameraPreviews: List<CameraPreview> = emptyList(),
) {
    fun supports(action: String): Boolean = action in availableActions
}

data class MusicProvider(val id: String, val label: String, val connected: Boolean, val active: Boolean, val localPlayback: Boolean)

data class MusicTrack(
    val id: String,
    val title: String,
    val artist: String,
    val albumArtist: String,
    val album: String,
    val genre: String,
    val durationSeconds: Double,
    val durationDisplay: String,
    val provider: String,
    val artworkUrl: String,
) {
    val displayArtist: String get() = artist.ifBlank { albumArtist }
    val subtitle: String get() = listOf(displayArtist, album).filter { it.isNotBlank() }.joinToString(" · ")
    val artworkCacheKey: String
        get() {
            val cleanAlbum = normalizeArtworkIdentity(album)
            if (cleanAlbum.isNotBlank()) {
                val cleanArtist = normalizeArtworkIdentity(albumArtist.ifBlank { displayArtist })
                return "album:${normalizeArtworkIdentity(provider)}:$cleanArtist:$cleanAlbum"
            }
            val cleanArtwork = artworkUrl.trim()
            if (cleanArtwork.isNotBlank()) return "artwork:$cleanArtwork"
            return "track:${normalizeArtworkIdentity(provider)}:$id"
        }

    private fun normalizeArtworkIdentity(value: String): String = value
        .trim()
        .lowercase(Locale.ROOT)
        .replace(Regex("\\s+"), " ")
}

data class MusicRecommendation(
    val id: String,
    val name: String,
    val description: String,
    val tracks: List<MusicTrack>,
    val artworkUrl: String,
)

data class MusicTarget(
    val id: String,
    val label: String,
    val kind: String,
    val description: String = "",
    val airplayBridgeTarget: String = "",
    val transportMode: String = "",
    val transportOptions: List<String> = emptyList(),
) {
    val isLocal: Boolean get() = kind == "local" || id == "little_spud:local"
}

data class MusicPlayerState(
    val status: String = "idle",
    val provider: String = "",
    val current: MusicTrack? = null,
    val targets: List<String> = emptyList(),
    val queueCount: Int = 0,
    val queueIndex: Int = -1,
    val queue: List<MusicTrack> = emptyList(),
    val shuffle: Boolean = false,
    val repeatMode: String = "off",
    val continuousRadio: Boolean = false,
    val radioName: String = "",
    val positionSeconds: Double = 0.0,
    val durationSeconds: Double = 0.0,
    val seekable: Boolean = false,
    val volumePercent: Int = 75,
)

data class MusicSnapshot(
    val available: Boolean = false,
    val provider: MusicProvider? = null,
    val providers: List<MusicProvider> = emptyList(),
    val tracks: List<MusicTrack> = emptyList(),
    val trackFeedKind: String = "library",
    val trackFeedTitle: String = "Library",
    val trackFeedSummary: String = "",
    val trackCount: Int = 0,
    val artists: List<String> = emptyList(),
    val albums: List<String> = emptyList(),
    val genres: List<String> = emptyList(),
    val recommendations: List<MusicRecommendation> = emptyList(),
    val recommendationSummary: String = "",
    val targets: List<MusicTarget> = emptyList(),
    val player: MusicPlayerState = MusicPlayerState(),
    val syncedAt: Long? = null,
)

data class PushRegistration(
    val provider: String,
    val app: String,
    val environment: String,
    val pushDeviceId: String,
    val pushSecret: String,
    val gatewayUrl: String,
    val tokenFingerprint: String,
    val registeredAt: Long,
) {
    val isComplete: Boolean get() = provider.isNotBlank() && pushDeviceId.isNotBlank() && pushSecret.isNotBlank()

    fun toJson(): JSONObject = JSONObject().apply {
        put("provider", provider); put("app", app); put("environment", environment)
        put("pushDeviceId", pushDeviceId); put("pushSecret", pushSecret); put("gatewayUrl", gatewayUrl)
        put("tokenFingerprint", tokenFingerprint); put("registeredAt", registeredAt)
    }

    companion object {
        fun fromJson(json: JSONObject) = PushRegistration(
            provider = json.string("provider"),
            app = json.string("app"),
            environment = json.string("environment"),
            pushDeviceId = json.string("pushDeviceId", "push_device_id"),
            pushSecret = json.string("pushSecret", "push_secret"),
            gatewayUrl = json.string("gatewayUrl", "gateway_url", "relayUrl", "relay_url"),
            tokenFingerprint = json.string("tokenFingerprint", "token_fingerprint"),
            registeredAt = json.longValue("registeredAt", System.currentTimeMillis()),
        )
    }
}

fun String.cleanUrl(): String = trim().trimEnd('/')

fun JSONObject.string(vararg keys: String): String {
    for (key in keys) {
        val value = opt(key)
        if (value != null && value !== JSONObject.NULL) {
            val clean = value.toString().trim()
            if (clean.isNotEmpty() && clean != "null") return clean
        }
    }
    return ""
}

fun JSONObject.nullableString(vararg keys: String): String? = string(*keys).ifBlank { null }

fun JSONObject.booleanOrNull(vararg keys: String): Boolean? {
    for (key in keys) {
        when (val value = opt(key)) {
            is Boolean -> return value
            is Number -> return value.toInt() != 0
            is String -> when (value.trim().lowercase()) {
                "true", "1", "yes", "on" -> return true
                "false", "0", "no", "off" -> return false
            }
        }
    }
    return null
}

fun JSONObject.intValue(key: String, fallback: Int = 0): Int = when (val value = opt(key)) {
    is Number -> value.toInt()
    is String -> value.toDoubleOrNull()?.toInt() ?: fallback
    else -> fallback
}

fun JSONObject.longValue(key: String, fallback: Long = 0L): Long = when (val value = opt(key)) {
    is Number -> value.toLong()
    is String -> value.toDoubleOrNull()?.toLong() ?: fallback
    else -> fallback
}

fun JSONObject.doubleOrNull(vararg keys: String): Double? {
    for (key in keys) {
        when (val value = opt(key)) {
            is Number -> return value.toDouble()
            is String -> value.toDoubleOrNull()?.let { return it }
        }
    }
    return null
}

fun JSONObject.objectOrNull(key: String): JSONObject? = opt(key) as? JSONObject
fun JSONObject.objectArray(key: String): List<JSONObject> = optJSONArray(key)?.objects().orEmpty()

fun JSONObject.stringArray(key: String): List<String> = optJSONArray(key)?.let { array ->
    buildList {
        for (index in 0 until array.length()) {
            val clean = array.opt(index)?.toString()?.trim().orEmpty()
            if (clean.isNotBlank() && clean != "null") add(clean)
        }
    }
}.orEmpty()

fun JSONObject.dateMillis(vararg keys: String): Long? {
    for (key in keys) {
        val value = opt(key) ?: continue
        when (value) {
            is Number -> {
                val raw = value.toDouble()
                return if (raw > 10_000_000_000.0) raw.toLong() else (raw * 1000).toLong()
            }
            is String -> {
                value.toDoubleOrNull()?.let { raw ->
                    return if (raw > 10_000_000_000.0) raw.toLong() else (raw * 1000).toLong()
                }
                runCatching { Instant.parse(value).toEpochMilli() }.getOrNull()?.let { return it }
            }
        }
    }
    return null
}

fun JSONArray.objects(): List<JSONObject> = buildList {
    for (index in 0 until length()) optJSONObject(index)?.let(::add)
}

inline fun <T> Iterable<T>.toJsonArray(transform: (T) -> Any?): JSONArray = JSONArray().apply {
    for (item in this@toJsonArray) put(transform(item))
}
