@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.tatertotterson.littlespud.android.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.core.content.ContextCompat
import coil3.compose.AsyncImage
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.tatertotterson.littlespud.android.BuildConfig
import com.tatertotterson.littlespud.android.model.LittleSpudAttachment
import com.tatertotterson.littlespud.android.model.LittleSpudLane
import com.tatertotterson.littlespud.android.model.LittleSpudMessage
import com.tatertotterson.littlespud.android.model.LittleSpudRole
import com.tatertotterson.littlespud.android.model.TemperatureUnitPreference
import com.tatertotterson.littlespud.android.ui.theme.SpudDanger
import com.tatertotterson.littlespud.android.ui.theme.SpudGreen
import com.tatertotterson.littlespud.android.ui.theme.SpudMuted
import com.tatertotterson.littlespud.android.ui.theme.SpudOrange
import com.tatertotterson.littlespud.android.ui.theme.SpudPanel
import com.tatertotterson.littlespud.android.ui.theme.SpudPanelRaised
import java.text.DateFormat
import java.util.Date

@Composable
fun LittleSpudApp(model: LittleSpudViewModel) {
    val state by model.state.collectAsStateWithLifecycle()
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        if (state.session == null) PairingScreen(state, model) else MainShell(state, model)
    }
}

@Composable
private fun PairingScreen(state: LittleSpudUiState, model: LittleSpudViewModel) {
    val context = LocalContext.current
    val scannerOptions = remember {
        GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .enableAutoZoom()
            .build()
    }
    val scanner = remember(context) { GmsBarcodeScanning.getClient(context, scannerOptions) }

    LazyColumn(
        modifier = Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding(),
        contentPadding = PaddingValues(horizontal = 24.dp, vertical = 28.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        item {
            Text("Little Spud", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Black)
            Text("Your pocket-sized connection to Tater", color = SpudMuted)
        }
        item {
            Card(colors = CardDefaults.cardColors(containerColor = SpudPanel), modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text("Pair this device", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text("Scan the QR code from Tater, or enter its URL and pairing code manually.", color = SpudMuted)
                    OutlinedTextField(
                        value = state.userName,
                        onValueChange = model::updateUserName,
                        label = { Text("Your name") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = state.deviceName,
                        onValueChange = model::updateDeviceName,
                        label = { Text("Device name") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = state.hubUrl,
                        onValueChange = model::updateHubUrl,
                        label = { Text("Tater URL (manual pairing)") },
                        placeholder = { Text("http://tater.local:8000") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = state.syncCode,
                        onValueChange = model::updateSyncCode,
                        label = { Text("Pairing code or QR payload") },
                        minLines = 2,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedButton(
                        onClick = {
                            scanner.startScan()
                                .addOnSuccessListener { barcode -> barcode.rawValue?.let(model::applyPairingPayload) }
                                .addOnFailureListener { error -> model.reportStatus(error.localizedMessage ?: "QR scanning is unavailable.", true) }
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(Icons.Default.QrCodeScanner, null)
                        Spacer(Modifier.width(8.dp))
                        Text("Scan Tater QR")
                    }
                    Button(onClick = model::pair, enabled = !state.isPairing, modifier = Modifier.fillMaxWidth()) {
                        if (state.isPairing) {
                            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(10.dp))
                        }
                        Text(if (state.isPairing) "Pairing…" else "Pair Little Spud")
                    }
                    TextButton(onClick = model::startDemoMode, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                        Text("Explore demo mode")
                    }
                }
            }
        }
        if (state.statusText.isNotBlank()) item { StatusBanner(state.statusText, state.statusIsError) }
    }
}

@Composable
private fun MainShell(state: LittleSpudUiState, model: LittleSpudViewModel) {
    val focusManager = LocalFocusManager.current
    val lanes = remember {
        listOf(
            LittleSpudLane.NOTIFICATIONS,
            LittleSpudLane.CHAT,
            LittleSpudLane.HOME,
            LittleSpudLane.MUSIC,
        )
    }
    val pagerState = rememberPagerState(
        initialPage = lanes.indexOf(state.activeLane).coerceAtLeast(0),
        pageCount = { lanes.size },
    )

    LaunchedEffect(state.activeLane) {
        val targetPage = lanes.indexOf(state.activeLane)
        if (targetPage >= 0 && pagerState.currentPage != targetPage) {
            pagerState.animateScrollToPage(targetPage)
        }
    }
    LaunchedEffect(pagerState.settledPage) {
        lanes.getOrNull(pagerState.settledPage)?.let { lane ->
            if (lane != LittleSpudLane.CHAT) focusManager.clearFocus()
            if (lane != state.activeLane) model.selectLane(lane)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(
                            when (state.activeLane) {
                                LittleSpudLane.NOTIFICATIONS -> "Notifications"
                                LittleSpudLane.CHAT -> state.assistantName
                                LittleSpudLane.HOME -> "Home"
                                LittleSpudLane.MUSIC -> "Music Core"
                            },
                            fontWeight = FontWeight.Bold,
                        )
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.size(7.dp).clip(CircleShape).background(if (state.hubConnected) SpudGreen else SpudMuted))
                            Spacer(Modifier.width(6.dp))
                            Text(state.connectionText, style = MaterialTheme.typography.labelSmall, color = SpudMuted)
                        }
                    }
                },
                actions = { IconButton(onClick = { model.showSettings(true) }) { Icon(Icons.Default.Settings, "Settings") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        HorizontalPager(
            state = pagerState,
            modifier = Modifier.fillMaxSize().padding(padding),
            beyondViewportPageCount = lanes.lastIndex,
            key = { page -> lanes[page] },
        ) { page ->
            when (lanes[page]) {
                LittleSpudLane.NOTIFICATIONS -> NotificationsScreen(state)
                LittleSpudLane.CHAT -> ChatScreen(state, model)
                LittleSpudLane.HOME -> HomeScreen(state, model)
                LittleSpudLane.MUSIC -> MusicScreen(state, model)
            }
        }
    }
    if (state.showSettings) SettingsSheet(state, model)
}

@Composable
private fun ChatScreen(state: LittleSpudUiState, model: LittleSpudViewModel) {
    val context = LocalContext.current
    val listState = rememberLazyListState()
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri?.let(model::addAttachment) }
    val microphonePermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) model.toggleVoiceInput()
        else model.reportStatus("Microphone access is blocked in Android Settings.", isError = true)
    }
    LaunchedEffect(state.messages.size, state.messages.lastOrNull()?.content?.length) {
        if (state.messages.isNotEmpty()) listState.animateScrollToItem(state.messages.lastIndex)
    }
    Column(Modifier.fillMaxSize().imePadding()) {
        if (state.statusText.isNotBlank() && state.statusIsError) {
            StatusBanner(state.statusText, true, Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
        }
        LazyColumn(
            state = listState,
            modifier = Modifier.weight(1f).fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 14.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (state.messages.isEmpty()) item { EmptyChat(state.assistantName) }
            items(state.messages, key = { it.id }) { MessageBubble(it, state.assistantName) }
        }
        if (state.pendingAttachments.isNotEmpty()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                state.pendingAttachments.forEach { attachment ->
                    AssistChip(
                        onClick = { model.removeAttachment(attachment.id) },
                        label = { Text(attachment.displayName, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        trailingIcon = { Icon(Icons.Default.Close, "Remove", Modifier.size(16.dp)) },
                    )
                }
            }
        }
        if (state.speechStatus.isNotBlank()) {
            Row(
                Modifier.fillMaxWidth().background(SpudPanel).padding(horizontal = 14.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(Icons.Default.GraphicEq, null, Modifier.size(18.dp), tint = SpudOrange)
                Text(state.speechStatus, style = MaterialTheme.typography.labelMedium, color = SpudMuted)
            }
        }
        Row(
            Modifier.fillMaxWidth().background(SpudPanel).padding(8.dp),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            IconButton(onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) {
                Icon(Icons.Default.AttachFile, "Attach image")
            }
            OutlinedTextField(
                value = state.draft,
                onValueChange = model::updateDraft,
                placeholder = { Text("Message ${state.assistantName}…") },
                modifier = Modifier.weight(1f),
                maxLines = 5,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(onSend = { if (state.canSend) model.sendMessage() }),
            )
            IconButton(
                onClick = {
                    if (state.isVoiceRecording || state.isVoiceSubmitting ||
                        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                    ) {
                        model.toggleVoiceInput()
                    } else {
                        microphonePermission.launch(Manifest.permission.RECORD_AUDIO)
                    }
                },
                enabled = state.canUseVoiceInput || state.isVoiceRecording || state.isVoiceSubmitting,
            ) {
                Icon(
                    if (state.isVoiceSubmitting) Icons.Default.GraphicEq else Icons.Default.Mic,
                    when {
                        state.isVoiceRecording -> "Stop voice input"
                        state.isVoiceSubmitting -> "Cancel voice input"
                        else -> "Start voice input"
                    },
                    tint = if (state.isVoiceRecording || state.isVoiceSubmitting) SpudOrange else MaterialTheme.colorScheme.onSurface,
                )
            }
            FilledIconButton(onClick = { model.sendMessage() }, enabled = state.canSend) {
                if (state.isSending) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                else Icon(Icons.AutoMirrored.Filled.Send, "Send")
            }
        }
    }
}

@Composable
private fun EmptyChat(assistantName: String) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 72.dp, horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(Icons.Default.SmartToy, null, Modifier.size(54.dp), tint = SpudOrange)
        Text("Talk with $assistantName", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text("Ask a question, use a Tater tool, or attach an image.", color = SpudMuted)
    }
}

@Composable
private fun MessageBubble(message: LittleSpudMessage, assistantName: String) {
    if (message.kind == "tool_notice") {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
            AssistChip(onClick = {}, label = { Text(message.content) }, leadingIcon = { Icon(Icons.Default.SmartToy, null, Modifier.size(16.dp)) })
        }
        return
    }
    val isUser = message.role == LittleSpudRole.USER
    Row(Modifier.fillMaxWidth(), horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start) {
        Column(
            Modifier.fillMaxWidth(0.88f),
            horizontalAlignment = if (isUser) Alignment.End else Alignment.Start,
        ) {
            Text(if (isUser) "You" else assistantName, style = MaterialTheme.typography.labelSmall, color = SpudMuted)
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = when {
                        message.kind == "error" -> SpudDanger.copy(alpha = 0.18f)
                        isUser -> MaterialTheme.colorScheme.primaryContainer
                        else -> SpudPanelRaised
                    },
                ),
                shape = RoundedCornerShape(18.dp),
            ) {
                Column(Modifier.padding(13.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (message.content.isNotBlank()) Text(message.content)
                    message.attachments.forEach { AttachmentView(it) }
                    if (message.kind == "streaming" && message.content.isBlank()) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(8.dp)); Text("Thinking…", color = SpudMuted)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AttachmentView(attachment: LittleSpudAttachment) {
    val dataBitmap = remember(attachment.dataUrl) {
        attachment.dataUrl.takeIf { it.startsWith("data:image") }?.substringAfter("base64,", "")?.takeIf { it.isNotBlank() }?.let { encoded ->
            runCatching {
                val bytes = Base64.decode(encoded, Base64.DEFAULT)
                android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
            }.getOrNull()
        }
    }
    when {
        dataBitmap != null -> Image(dataBitmap, attachment.displayName, Modifier.fillMaxWidth().height(210.dp).clip(RoundedCornerShape(12.dp)), contentScale = ContentScale.Crop)
        attachment.previewUrl.isNotBlank() && attachment.type.startsWith("image/") -> AsyncImage(
            model = attachment.previewUrl,
            contentDescription = attachment.displayName,
            modifier = Modifier.fillMaxWidth().height(210.dp).clip(RoundedCornerShape(12.dp)),
            contentScale = ContentScale.Crop,
        )
        else -> AssistChip(onClick = {}, label = { Text(attachment.displayName) }, leadingIcon = { Icon(Icons.Default.AttachFile, null) })
    }
}

@Composable
private fun NotificationsScreen(state: LittleSpudUiState) {
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (state.notifications.isEmpty()) item {
            Column(Modifier.fillMaxWidth().padding(vertical = 80.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Default.Notifications, null, Modifier.size(52.dp), tint = SpudMuted)
                Spacer(Modifier.height(12.dp))
                Text("No notifications yet", style = MaterialTheme.typography.titleLarge)
                Text("Tater alerts will appear here.", color = SpudMuted)
            }
        }
        items(state.notifications.reversed(), key = { it.id }) { notification ->
            val urgent = notification.notificationPriority.equals("urgent", true) || notification.notificationPriority.equals("high", true)
            Card(
                colors = CardDefaults.cardColors(containerColor = if (urgent) SpudDanger.copy(alpha = 0.13f) else SpudPanel),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(notification.notificationTitle?.ifBlank { "Little Spud" } ?: "Little Spud", fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                        if (urgent) Text("URGENT", style = MaterialTheme.typography.labelSmall, color = SpudDanger, fontWeight = FontWeight.Black)
                    }
                    Text(notification.notificationBody?.ifBlank { notification.content } ?: notification.content)
                    Text(DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(notification.createdAt)), style = MaterialTheme.typography.labelSmall, color = SpudMuted)
                    notification.attachments.forEach { AttachmentView(it) }
                }
            }
        }
    }
}

@Composable
private fun SettingsSheet(state: LittleSpudUiState, model: LittleSpudViewModel) {
    var confirmDisconnect by rememberSaveable { mutableStateOf(false) }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        model.setNotificationsEnabled(granted)
        if (!granted) model.reportStatus("Notification permission was not granted.", true)
    }
    ModalBottomSheet(onDismissRequest = { model.showSettings(false) }) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 22.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Little Spud settings", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Temperature", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text(
                    "Choose how Little Spud displays room temperatures, thermostat controls, and whole-home averages.",
                    style = MaterialTheme.typography.bodySmall,
                    color = SpudMuted,
                )
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    TemperatureUnitPreference.entries.forEachIndexed { index, preference ->
                        SegmentedButton(
                            selected = state.temperatureUnitPreference == preference,
                            onClick = { model.setTemperatureUnitPreference(preference) },
                            shape = SegmentedButtonDefaults.itemShape(
                                index = index,
                                count = TemperatureUnitPreference.entries.size,
                            ),
                        ) {
                            Text(preference.label)
                        }
                    }
                }
                Text(
                    state.temperatureUnitPreference.description,
                    style = MaterialTheme.typography.bodySmall,
                    color = SpudMuted,
                )
            }
            HorizontalDivider()
            SettingSwitch(
                title = "Device notifications",
                description = if (BuildConfig.FIREBASE_CONFIGURED) "Wake this device for Tater alerts." else "Add google-services.json to activate FCM delivery.",
                checked = state.notificationsEnabled,
                onCheckedChange = { enabled ->
                    if (enabled && Build.VERSION.SDK_INT >= 33) permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                    else model.setNotificationsEnabled(enabled)
                },
            )
            HorizontalDivider()
            SettingSwitch(
                title = "Speak Tater replies",
                description = "Play replies from your paired Tater’s speech endpoint.",
                checked = state.ttsEnabled,
                onCheckedChange = { model.toggleTts() },
            )
            HorizontalDivider()
            state.session?.let { session ->
                Text("Paired Tater", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text(session.hubName, color = SpudOrange)
                Text(session.displayNodeName, color = SpudMuted)
                Text(session.hubUrl, color = SpudMuted, style = MaterialTheme.typography.bodySmall)
            }
            OutlinedButton(onClick = { confirmDisconnect = true }, modifier = Modifier.fillMaxWidth()) {
                Text("Forget pairing", color = SpudDanger)
            }
            Spacer(Modifier.height(12.dp))
        }
    }
    if (confirmDisconnect) AlertDialog(
        onDismissRequest = { confirmDisconnect = false },
        title = { Text("Forget this Tater?") },
        text = { Text("This removes the pairing token, local chat history, notifications, and push registration from this Android device.") },
        confirmButton = { TextButton(onClick = { confirmDisconnect = false; model.disconnect() }) { Text("Forget", color = SpudDanger) } },
        dismissButton = { TextButton(onClick = { confirmDisconnect = false }) { Text("Cancel") } },
    )
}

@Composable
private fun SettingSwitch(title: String, description: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.SemiBold)
            Text(description, style = MaterialTheme.typography.bodySmall, color = SpudMuted)
        }
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
private fun StatusBanner(message: String, isError: Boolean, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = (if (isError) SpudDanger else SpudGreen).copy(alpha = 0.14f)),
    ) {
        Text(message, Modifier.padding(12.dp), color = if (isError) SpudDanger else SpudGreen)
    }
}
