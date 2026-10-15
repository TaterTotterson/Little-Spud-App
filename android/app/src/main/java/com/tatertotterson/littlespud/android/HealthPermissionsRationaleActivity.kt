package com.tatertotterson.littlespud.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.tatertotterson.littlespud.android.ui.theme.LittleSpudTheme

class HealthPermissionsRationaleActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            LittleSpudTheme {
                HealthPermissionsRationale(onClose = ::finish)
            }
        }
    }
}

@Composable
private fun HealthPermissionsRationale(onClose: () -> Unit) {
    Surface(Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp, vertical = 56.dp),
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                "Little Spud and Health Connect",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.height(18.dp))
            Text(
                "Little Spud reads only the health and fitness categories you approve. " +
                    "It converts them into daily totals and sends those totals to the Fitness Core " +
                    "on your own Tater system.",
                style = MaterialTheme.typography.bodyLarge,
            )
            Spacer(Modifier.height(14.dp))
            Text(
                "Raw Health Connect samples stay on this phone. Little Spud does not sell health " +
                    "data or use it for advertising. You can change or revoke access at any time " +
                    "in Health Connect settings.",
                style = MaterialTheme.typography.bodyLarge,
            )
            Spacer(Modifier.height(28.dp))
            Button(onClick = onClose, modifier = Modifier.fillMaxWidth()) {
                Text("Close")
            }
        }
    }
}
