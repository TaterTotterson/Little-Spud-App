package com.tatertotterson.littlespud.android

import android.app.Application
import com.tatertotterson.littlespud.android.data.MessageStore
import com.tatertotterson.littlespud.android.data.SecureStore
import com.tatertotterson.littlespud.android.data.SettingsStore
import com.tatertotterson.littlespud.android.data.SpudLinkApi
import com.tatertotterson.littlespud.android.push.NotificationHelper
import com.tatertotterson.littlespud.android.push.NotificationUpdates

class LittleSpudApplication : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        container.notifications.createChannel()
    }
}

class AppContainer(application: Application) {
    val secureStore = SecureStore(application)
    val messageStore = MessageStore(application)
    val settings = SettingsStore(application)
    val api = SpudLinkApi(secureStore)
    val notifications = NotificationHelper(application)
    val notificationUpdates = NotificationUpdates()
}
