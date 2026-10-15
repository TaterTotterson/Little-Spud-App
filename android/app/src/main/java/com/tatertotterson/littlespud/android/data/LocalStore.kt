package com.tatertotterson.littlespud.android.data

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.util.AtomicFile
import com.tatertotterson.littlespud.android.model.LittleSpudMessage
import com.tatertotterson.littlespud.android.model.TemperatureUnitPreference
import com.tatertotterson.littlespud.android.model.objects
import com.tatertotterson.littlespud.android.model.toJsonArray
import org.json.JSONArray
import java.io.File

class MessageStore(context: Context) {
    private val messagesFile = AtomicFile(File(context.filesDir, "little-spud/messages.json"))
    private val notificationsFile = AtomicFile(File(context.filesDir, "little-spud/notifications.json"))

    @Synchronized
    fun loadMessages(): List<LittleSpudMessage> = read(messagesFile)

    @Synchronized
    fun saveMessages(messages: List<LittleSpudMessage>) = write(messagesFile, messages.takeLast(200))

    @Synchronized
    fun loadNotifications(): List<LittleSpudMessage> = read(notificationsFile)

    @Synchronized
    fun saveNotifications(notifications: List<LittleSpudMessage>) = write(notificationsFile, notifications.takeLast(80))

    @Synchronized
    fun appendNotification(notification: LittleSpudMessage): Boolean {
        val current = loadNotifications().toMutableList()
        if (current.any { it.id == notification.id }) return false
        current += notification
        saveNotifications(current)
        return true
    }

    @Synchronized
    fun clear() {
        messagesFile.baseFile.delete()
        notificationsFile.baseFile.delete()
    }

    private fun read(file: AtomicFile): List<LittleSpudMessage> {
        if (!file.baseFile.exists()) return emptyList()
        return runCatching {
            val text = file.openRead().bufferedReader().use { it.readText() }
            JSONArray(text).objects().mapNotNull(LittleSpudMessage::fromJson)
                .sortedBy { it.createdAt }
        }.getOrElse { emptyList() }
    }

    private fun write(file: AtomicFile, messages: List<LittleSpudMessage>) {
        file.baseFile.parentFile?.mkdirs()
        val stream = file.startWrite()
        try {
            stream.write(messages.toJsonArray { it.toJson() }.toString().toByteArray(Charsets.UTF_8))
            file.finishWrite(stream)
        } catch (error: Throwable) {
            file.failWrite(stream)
            throw error
        }
    }
}

class SettingsStore(private val context: Context) {
    private val preferences = context.getSharedPreferences("little-spud-settings", Context.MODE_PRIVATE)

    var userName: String
        get() = preferences.getString("user-name", "").orEmpty()
        set(value) = preferences.edit().putString("user-name", value.trim()).apply()

    var notificationsEnabled: Boolean
        get() = preferences.getBoolean("notifications-enabled", false)
        set(value) = preferences.edit().putBoolean("notifications-enabled", value).apply()

    var ttsEnabled: Boolean
        get() = preferences.getBoolean("tts-enabled", false)
        set(value) = preferences.edit().putBoolean("tts-enabled", value).apply()

    var temperatureUnitPreference: TemperatureUnitPreference
        get() = TemperatureUnitPreference.fromStorage(
            preferences.getString("temperature-unit", "").orEmpty(),
        )
        set(value) = preferences.edit().putString("temperature-unit", value.storageValue).apply()

    var notificationUnreadCount: Int
        get() = preferences.getInt("notification-unread-count", 0)
        set(value) = preferences.edit().putInt("notification-unread-count", value.coerceAtLeast(0)).apply()

    fun defaultDeviceName(): String {
        val friendly = runCatching {
            Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)
        }.getOrNull().orEmpty().trim()
        if (friendly.isNotBlank()) return friendly
        return listOf(Build.MANUFACTURER, Build.MODEL)
            .filter { it.isNotBlank() }
            .joinToString(" ")
            .trim()
            .ifBlank { "Android device" }
    }
}
