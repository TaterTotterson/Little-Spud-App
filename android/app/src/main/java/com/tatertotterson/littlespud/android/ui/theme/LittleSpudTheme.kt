package com.tatertotterson.littlespud.android.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val SpudBackground = Color(0xFF050506)
val SpudPanel = Color(0xFF121214)
val SpudPanelRaised = Color(0xFF1B1B1E)
val SpudText = Color(0xFFF7F2E8)
val SpudMuted = Color(0xFFADA09A)
val SpudOrange = Color(0xFFFF6B00)
val SpudOrangeLight = Color(0xFFFF9C24)
val SpudGreen = Color(0xFF59D999)
val SpudDanger = Color(0xFFF56D5E)

private val LittleSpudColors = darkColorScheme(
    primary = SpudOrange,
    onPrimary = Color.Black,
    primaryContainer = Color(0xFF4B2105),
    onPrimaryContainer = Color(0xFFFFDCC2),
    secondary = SpudOrangeLight,
    onSecondary = Color.Black,
    background = SpudBackground,
    onBackground = SpudText,
    surface = SpudPanel,
    onSurface = SpudText,
    surfaceVariant = SpudPanelRaised,
    onSurfaceVariant = SpudMuted,
    error = SpudDanger,
    onError = Color.Black,
    outline = Color.White.copy(alpha = 0.15f),
)

@Composable
fun LittleSpudTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = LittleSpudColors, content = content)
}
