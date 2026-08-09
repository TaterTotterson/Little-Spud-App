package com.tatertotterson.littlespud.android.push

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.tatertotterson.littlespud.android.LittleSpudApplication
import com.tatertotterson.littlespud.android.model.HubNotification
import com.tatertotterson.littlespud.android.model.LittleSpudMessage
import com.tatertotterson.littlespud.android.model.LittleSpudRole
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import java.util.UUID

class LittleSpudMessagingService : FirebaseMessagingService() {
    // FCM 25 still delivers the actual gateway token through this callback;
    // onRegistered supplies an installation ID, which cannot yet address Admin messages.
    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        app().container.secureStore.saveFcmToken(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val container = app().container
        if (!container.settings.notificationsEnabled) return
        val session = container.secureStore.loadSession() ?: return
        val eventId = message.data["event_id"]
            ?: message.data["eventId"]
            ?: message.data["notification_id"]
            ?: ""
        val resolved = runBlocking {
            withTimeoutOrNull(9_000) {
                runCatching {
                    container.api.pollNotification(
                        session = session,
                        waitSeconds = 1,
                        consume = true,
                        eventId = eventId,
                    )
                }.getOrNull()
            }
        } ?: HubNotification(
            id = eventId.ifBlank { UUID.randomUUID().toString() },
            title = "Little Spud",
            message = "New Little Spud notification",
            createdAt = System.currentTimeMillis(),
            priority = "normal",
        )

        val local = LittleSpudMessage(
            id = resolved.id,
            role = LittleSpudRole.ASSISTANT,
            content = resolved.content,
            createdAt = resolved.createdAt,
            kind = "notification",
            notificationTitle = resolved.title,
            notificationBody = resolved.message,
            notificationPriority = resolved.priority,
        )
        if (container.messageStore.appendNotification(local)) {
            container.settings.notificationUnreadCount += 1
        }
        container.notificationUpdates.publish()
        container.notifications.show(resolved)
    }

    private fun app(): LittleSpudApplication = application as LittleSpudApplication
}
