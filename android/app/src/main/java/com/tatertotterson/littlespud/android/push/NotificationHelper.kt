package com.tatertotterson.littlespud.android.push

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.tatertotterson.littlespud.android.MainActivity
import com.tatertotterson.littlespud.android.R
import com.tatertotterson.littlespud.android.model.HubNotification

class NotificationHelper(private val context: Context) {
    fun createChannel() {
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = context.getString(R.string.notification_channel_description)
            enableVibration(true)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)

        manager.getNotificationChannel(LEGACY_CHANNEL_ID)?.let { legacyChannel ->
            legacyChannel.setShowBadge(false)
            manager.createNotificationChannel(legacyChannel)
        }
    }

    fun show(notification: HubNotification) {
        if (Build.VERSION.SDK_INT >= 33 && ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) return

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_OPEN_NOTIFICATIONS, true)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            notification.id.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val urgent = notification.priority.equals("urgent", true) || notification.priority.equals("high", true)
        val built = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_spud_foreground)
            .setContentTitle(notification.title.ifBlank { "Little Spud" })
            .setContentText(notification.message.ifBlank { "New Little Spud notification" })
            .setStyle(NotificationCompat.BigTextStyle().bigText(notification.message.ifBlank { notification.content }))
            .setPriority(if (urgent) NotificationCompat.PRIORITY_MAX else NotificationCompat.PRIORITY_HIGH)
            .setCategory(if (urgent) NotificationCompat.CATEGORY_ALARM else NotificationCompat.CATEGORY_MESSAGE)
            .setNumber(0)
            .setBadgeIconType(NotificationCompat.BADGE_ICON_NONE)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        NotificationManagerCompat.from(context).notify(notification.id.hashCode(), built)
    }

    companion object {
        const val CHANNEL_ID = "little-spud-alerts-no-badge"
        private const val LEGACY_CHANNEL_ID = "little-spud-alerts"
        const val EXTRA_OPEN_NOTIFICATIONS = "little_spud_open_notifications"
    }
}
