package com.tatertotterson.littlespud.android

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import com.tatertotterson.littlespud.android.model.LittleSpudLane
import com.tatertotterson.littlespud.android.push.NotificationHelper
import com.tatertotterson.littlespud.android.ui.LittleSpudApp
import com.tatertotterson.littlespud.android.ui.LittleSpudViewModel
import com.tatertotterson.littlespud.android.ui.theme.LittleSpudTheme

class MainActivity : ComponentActivity() {
    private val model: LittleSpudViewModel by viewModels {
        val app = application as LittleSpudApplication
        LittleSpudViewModel.Factory(app, app.container)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            LittleSpudTheme { LittleSpudApp(model) }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun onStart() {
        super.onStart()
        model.resume()
    }

    override fun onStop() {
        model.pauseForegroundWork()
        super.onStop()
    }

    private fun handleIntent(intent: Intent?) {
        intent?.dataString?.takeIf { it.startsWith("tater-spudlink://") }?.let(model::applyPairingPayload)
        if (intent?.getBooleanExtra(NotificationHelper.EXTRA_OPEN_NOTIFICATIONS, false) == true) {
            model.selectLane(LittleSpudLane.NOTIFICATIONS)
            intent.removeExtra(NotificationHelper.EXTRA_OPEN_NOTIFICATIONS)
        }
    }
}
