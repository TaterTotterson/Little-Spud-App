@file:OptIn(
    androidx.compose.material3.ExperimentalMaterial3Api::class,
    androidx.compose.foundation.layout.ExperimentalLayoutApi::class,
)

package com.tatertotterson.littlespud.android.ui

import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.AcUnit
import androidx.compose.material.icons.filled.Bathtub
import androidx.compose.material.icons.filled.Bed
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.ElectricBolt
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.Garage
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Speaker
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material.icons.filled.ToggleOn
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material.icons.filled.Weekend
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.tatertotterson.littlespud.android.model.HomeCategory
import com.tatertotterson.littlespud.android.model.HomeRoom
import com.tatertotterson.littlespud.android.model.MusicRecommendation
import com.tatertotterson.littlespud.android.model.MusicTrack
import com.tatertotterson.littlespud.android.model.TemperatureUnitPreference
import com.tatertotterson.littlespud.android.ui.theme.SpudDanger
import com.tatertotterson.littlespud.android.ui.theme.SpudGreen
import com.tatertotterson.littlespud.android.ui.theme.SpudMuted
import com.tatertotterson.littlespud.android.ui.theme.SpudOrange
import com.tatertotterson.littlespud.android.ui.theme.SpudPanel
import com.tatertotterson.littlespud.android.ui.theme.SpudPanelRaised
import kotlin.math.roundToInt

@Composable
fun HomeScreen(state: LittleSpudUiState, model: LittleSpudViewModel) {
    var selectedRoomId by remember { mutableStateOf<String?>(null) }
    var selectedOverview by remember { mutableStateOf<HomeOverviewStat?>(null) }
    val selectedRoom = state.home.rooms.firstOrNull { it.id == selectedRoomId }
    if (selectedRoom != null) {
        RoomDetailScreen(selectedRoom, state, model, onBack = { selectedRoomId = null })
        return
    }
    selectedOverview?.let { stat ->
        HomeOverviewDetailsSheet(
            stat = stat,
            rooms = state.home.rooms,
            state = state,
            model = model,
            onDismiss = { selectedOverview = null },
        )
    }
    val overviewStats = homeOverviewStats(state.home.rooms, state.temperatureUnitPreference)
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Your rooms", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text("Provider-neutral controls from your paired Tater", color = SpudMuted)
                }
                IconButton(onClick = { model.refreshHome(force = true) }) {
                    if (state.homeLoading) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                    else Icon(Icons.Default.Refresh, "Refresh home")
                }
            }
        }
        if (state.homeError.isNotBlank()) item { FeatureError(state.homeError) }
        if (state.home.rooms.isEmpty() && !state.homeLoading) item {
            EmptyFeature("No rooms available", "Pair with a Tater that has Home controls configured.")
        }
        if (overviewStats.isNotEmpty()) item {
            HomeOverviewStrip(overviewStats, onSelect = { selectedOverview = it })
        }
        items(state.home.rooms, key = { it.id }) { room ->
            val displaySummary = homeRoomDisplaySummary(room, state.temperatureUnitPreference)
            Card(
                onClick = { selectedRoomId = room.id },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(18.dp),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                colors = CardDefaults.cardColors(containerColor = Color.Transparent),
            ) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .background(
                            Brush.linearGradient(listOf(SpudPanelRaised, SpudPanel)),
                            RoundedCornerShape(18.dp),
                        )
                        .padding(15.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Box(
                        Modifier
                            .size(54.dp)
                            .background(SpudOrange.copy(alpha = 0.14f), RoundedCornerShape(14.dp)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(roomIcon(room), null, tint = SpudOrange, modifier = Modifier.size(25.dp))
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(room.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                            Text(
                                room.deviceCount.toString(),
                                color = SpudMuted,
                                style = MaterialTheme.typography.labelSmall,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier
                                    .background(Color.White.copy(alpha = 0.06f), CircleShape)
                                    .padding(horizontal = 7.dp, vertical = 3.dp),
                            )
                        }
                        if (displaySummary.isEmpty()) {
                            Text("Connected devices ready", color = SpudMuted, style = MaterialTheme.typography.bodyMedium)
                        } else {
                            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                displaySummary.take(3).forEach { summary ->
                                    Text(
                                        summary,
                                        color = SpudMuted,
                                        style = MaterialTheme.typography.bodyMedium,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            }
                        }
                    }
                    Icon(Icons.Default.ChevronRight, "Open ${room.name}", tint = SpudMuted, modifier = Modifier.size(18.dp))
                }
            }
        }
    }
}

private data class HomeOverviewContributor(
    val id: String,
    val roomId: String,
    val roomName: String,
    val sourceName: String,
    val value: String,
    val categoryId: String? = null,
)

private data class HomeOverviewStat(
    val id: String,
    val value: String,
    val label: String,
    val icon: ImageVector,
    val color: Color,
    val contributors: List<HomeOverviewContributor>,
)

@Composable
private fun HomeOverviewStrip(stats: List<HomeOverviewStat>, onSelect: (HomeOverviewStat) -> Unit) {
    LazyRow(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
        items(stats, key = { it.id }) { stat ->
            Card(
                onClick = { onSelect(stat) },
                shape = RoundedCornerShape(14.dp),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                colors = CardDefaults.cardColors(containerColor = SpudPanelRaised),
            ) {
                Row(
                    Modifier.padding(horizontal = 11.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(9.dp),
                ) {
                    Box(
                        Modifier
                            .size(28.dp)
                            .background(stat.color.copy(alpha = 0.13f), CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(stat.icon, null, tint = stat.color, modifier = Modifier.size(15.dp))
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(stat.value, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
                            Icon(Icons.Default.Info, null, tint = SpudMuted, modifier = Modifier.size(11.dp))
                        }
                        Text(stat.label, style = MaterialTheme.typography.labelSmall, color = SpudMuted)
                    }
                }
            }
        }
    }
}

@Composable
private fun HomeOverviewDetailsSheet(
    stat: HomeOverviewStat,
    rooms: List<HomeRoom>,
    state: LittleSpudUiState,
    model: LittleSpudViewModel,
    onDismiss: () -> Unit,
) {
    val liveLightsOn = if (stat.id == "lights") {
        stat.contributors.sumOf { contributor ->
            rooms.firstOrNull { it.id == contributor.roomId }
                ?.categories
                ?.firstOrNull { it.id == contributor.categoryId }
                ?.let(::homePoweredOnCount)
                ?: 0
        }
    } else 0
    val displayValue = if (stat.id == "lights") liveLightsOn.toString() else stat.value
    val displayLabel = if (stat.id == "lights") {
        if (liveLightsOn == 1) "light on" else "lights on"
    } else stat.label
    val thermostats = if (stat.id == "temperature") {
        rooms.flatMap { room ->
            room.categories
                .filter { it.id == "climate" && it.controlType == "thermostat" && !it.readOnly }
                .map { room to it }
        }
    } else emptyList()

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = SpudPanel,
    ) {
        LazyColumn(
            Modifier
                .fillMaxWidth()
                .navigationBarsPadding(),
            contentPadding = PaddingValues(start = 18.dp, end = 18.dp, bottom = 26.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                Row(
                    Modifier.padding(bottom = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(13.dp),
                ) {
                    Box(
                        Modifier
                            .size(48.dp)
                            .background(stat.color.copy(alpha = 0.14f), RoundedCornerShape(13.dp)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(stat.icon, null, tint = stat.color, modifier = Modifier.size(25.dp))
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(displayValue, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                        Text(displayLabel.replaceFirstChar { it.uppercase() }, color = SpudMuted)
                    }
                }
            }
            if (thermostats.isNotEmpty()) {
                item {
                    Text(
                        if (thermostats.size == 1) "THERMOSTAT" else "THERMOSTATS",
                        style = MaterialTheme.typography.labelSmall,
                        color = SpudMuted,
                        fontWeight = FontWeight.Bold,
                    )
                }
                thermostats.forEach { (room, category) ->
                    if (thermostats.size > 1) {
                        item(key = "thermostat-room-${room.id}") {
                            Text(room.name, style = MaterialTheme.typography.labelMedium, color = SpudMuted, fontWeight = FontWeight.SemiBold)
                        }
                    }
                    item(key = "thermostat-${room.id}-${category.id}") {
                        HomeControlCard(
                            roomId = room.id,
                            category = category,
                            busy = "${room.id}|${category.id}" in state.homeControlsInFlight,
                            temperaturePreference = state.temperatureUnitPreference,
                            model = model,
                        )
                    }
                }
            }
            item {
                Text(
                    "${stat.contributors.size} CONTRIBUTING ROOM${if (stat.contributors.size == 1) "" else "S"}",
                    style = MaterialTheme.typography.labelSmall,
                    color = SpudMuted,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(top = if (thermostats.isEmpty()) 2.dp else 8.dp),
                )
            }
            items(stat.contributors, key = { it.id }) { contributor ->
                if (stat.id == "lights") {
                    HomeOverviewLightRow(contributor, rooms, state, model)
                } else {
                    HomeOverviewContributorRow(contributor, stat.color)
                }
            }
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = onDismiss) { Text("Done") }
                }
            }
        }
    }
}

@Composable
private fun HomeOverviewLightRow(
    contributor: HomeOverviewContributor,
    rooms: List<HomeRoom>,
    state: LittleSpudUiState,
    model: LittleSpudViewModel,
) {
    val category = rooms.firstOrNull { it.id == contributor.roomId }
        ?.categories
        ?.firstOrNull { it.id == contributor.categoryId }
    if (category == null) {
        HomeOverviewContributorRow(contributor, SpudOrange)
        return
    }
    val onCount = homePoweredOnCount(category)
    val anyOn = onCount > 0
    val action = if (anyOn) "turn_off" else "turn_on"
    val busy = "${contributor.roomId}|${category.id}" in state.homeControlsInFlight
    val supportsBrightness = category.supportsBrightness && category.supports("set_brightness")
    var brightness by remember(category.brightness) {
        mutableFloatStateOf((category.brightness ?: 50.0).toFloat().coerceIn(1f, 100f))
    }

    Card(
        colors = CardDefaults.cardColors(containerColor = SpudPanelRaised),
        shape = RoundedCornerShape(14.dp),
        border = BorderStroke(
            1.dp,
            if (anyOn) SpudOrange.copy(alpha = 0.35f) else MaterialTheme.colorScheme.outline,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(13.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .clickable(enabled = !busy && category.supports(action)) {
                        model.toggleHomePower(contributor.roomId, category)
                    },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(contributor.roomName, fontWeight = FontWeight.SemiBold)
                    Text(contributor.sourceName, style = MaterialTheme.typography.bodySmall, color = SpudMuted)
                }
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        if (onCount == 0) "All off" else "$onCount of ${maxOf(onCount, category.count)} on",
                        color = if (anyOn) SpudOrange else SpudMuted,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        if (busy) CircularProgressIndicator(Modifier.size(13.dp), strokeWidth = 2.dp)
                        else Icon(Icons.Default.ElectricBolt, null, modifier = Modifier.size(13.dp))
                        Text(if (anyOn) "Tap off" else "Tap on", style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
            if (supportsBrightness) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Default.Lightbulb, null, tint = SpudMuted, modifier = Modifier.size(15.dp))
                    Slider(
                        value = brightness,
                        onValueChange = { brightness = it },
                        onValueChangeFinished = {
                            model.performHomeAction(
                                contributor.roomId,
                                category,
                                "set_brightness",
                                value = brightness.toDouble(),
                            )
                        },
                        valueRange = 1f..100f,
                        enabled = !busy,
                        modifier = Modifier.weight(1f),
                    )
                    Text("${brightness.toInt()}%", style = MaterialTheme.typography.labelSmall, color = SpudMuted)
                }
            }
        }
    }
}

@Composable
private fun HomeOverviewContributorRow(contributor: HomeOverviewContributor, color: Color) {
    Card(
        colors = CardDefaults.cardColors(containerColor = SpudPanelRaised),
        shape = RoundedCornerShape(14.dp),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(Modifier.padding(13.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(contributor.roomName, fontWeight = FontWeight.SemiBold)
                Text(contributor.sourceName, style = MaterialTheme.typography.bodySmall, color = SpudMuted)
            }
            Text(contributor.value, color = color, fontWeight = FontWeight.Bold)
        }
    }
}

private fun homeOverviewStats(
    rooms: List<HomeRoom>,
    temperaturePreference: TemperatureUnitPreference,
): List<HomeOverviewStat> {
    val stats = mutableListOf<HomeOverviewStat>()
    val lightContributors = mutableListOf<HomeOverviewContributor>()
    val fanContributors = mutableListOf<HomeOverviewContributor>()
    val doorContributors = mutableListOf<HomeOverviewContributor>()
    val lockContributors = mutableListOf<HomeOverviewContributor>()
    val leakContributors = mutableListOf<HomeOverviewContributor>()
    val motionContributors = mutableListOf<HomeOverviewContributor>()
    val temperatureContributors = mutableListOf<HomeOverviewContributor>()
    val humidityContributors = mutableListOf<HomeOverviewContributor>()
    val temperatures = mutableListOf<Pair<Double, String>>()
    val humidities = mutableListOf<Double>()
    var lightsOn = 0
    var fansOn = 0
    var doorsOpen = 0
    var unlocked = 0

    rooms.forEach { room ->
        room.categories.forEach { category ->
            when (category.id) {
                "light" -> {
                    val count = homePoweredOnCount(category)
                    lightsOn += count
                    val value = if (count == 0) "All off" else "$count of ${maxOf(count, category.count)} on"
                    lightContributors += HomeOverviewContributor(
                        "lights-${room.id}", room.id, room.name,
                        homeCategorySourceName(category, "light"), value, category.id,
                    )
                }
                "fan" -> {
                    val count = homePoweredOnCount(category)
                    fansOn += count
                    if (count > 0) fanContributors += HomeOverviewContributor(
                        "fans-${room.id}", room.id, room.name,
                        homeCategorySourceName(category, "fan"), "$count of ${maxOf(count, category.count)} on",
                    )
                }
                "garage_door", "entry_sensor" -> {
                    val count = homeOpenCount(category)
                    doorsOpen += count
                    if (count > 0) doorContributors += HomeOverviewContributor(
                        "doors-${room.id}-${category.id}", room.id, room.name,
                        homeCategorySourceName(category, if (category.id == "garage_door") "garage door" else "door/window sensor"),
                        "$count open",
                    )
                }
                "lock" -> {
                    val count = when (category.state) {
                        "unlocked" -> maxOf(1, category.count)
                        "mixed" -> maxOf(1, homeFirstNumber(category.summary)?.toInt() ?: 1)
                        else -> 0
                    }
                    unlocked += count
                    if (count > 0) lockContributors += HomeOverviewContributor(
                        "locks-${room.id}", room.id, room.name,
                        homeCategorySourceName(category, "lock"), "$count unlocked",
                    )
                }
                "leak" -> {
                    val active = category.summary.contains("leak detected", ignoreCase = true) || category.state in setOf("wet", "active")
                    if (active) leakContributors += HomeOverviewContributor(
                        "leak-${room.id}", room.id, room.name,
                        homeCategorySourceName(category, "leak sensor"), "Alert",
                    )
                }
                "motion" -> if (category.summary.contains("motion detected", ignoreCase = true)) {
                    motionContributors += HomeOverviewContributor(
                        "motion-${room.id}", room.id, room.name,
                        homeCategorySourceName(category, "motion sensor"), "Active",
                    )
                }
            }
        }

        val temperature = room.categories.firstOrNull { it.id == "temperature" && it.currentTemperature != null }
            ?: room.categories.firstOrNull { it.id == "climate" && it.currentTemperature != null }
        temperature?.currentTemperature?.let { value ->
            val unit = temperature.temperatureUnit.uppercase().takeIf { it == "C" } ?: "F"
            temperatures += value to unit
            temperatureContributors += HomeOverviewContributor(
                "temperature-${room.id}", room.id, room.name,
                if (temperature.id == "climate") "Thermostat" else homeMeasurementSourceName(temperature, "temperature"),
                "${formatTemperature(value)}°$unit", temperature.id,
            )
        }

        room.categories.firstOrNull { it.id == "humidity" }?.let { humidity ->
            homeFirstNumber(humidity.summary)?.let { value ->
                humidities += value
                humidityContributors += HomeOverviewContributor(
                    "humidity-${room.id}", room.id, room.name,
                    homeMeasurementSourceName(humidity, "humidity"), "${value.roundToInt()}%", humidity.id,
                )
            }
        }
    }

    if (leakContributors.isNotEmpty()) stats += HomeOverviewStat("leak", "Alert", "leak detected", Icons.Default.WaterDrop, SpudDanger, leakContributors)
    if (doorsOpen > 0) stats += HomeOverviewStat("doors", doorsOpen.toString(), if (doorsOpen == 1) "door open" else "doors open", Icons.Default.Garage, SpudDanger, doorContributors)
    if (unlocked > 0) stats += HomeOverviewStat("locks", unlocked.toString(), if (unlocked == 1) "door unlocked" else "doors unlocked", Icons.Default.Lock, SpudDanger, lockContributors)
    if (lightsOn > 0) stats += HomeOverviewStat("lights", lightsOn.toString(), if (lightsOn == 1) "light on" else "lights on", Icons.Default.Lightbulb, SpudOrange, lightContributors)
    if (fansOn > 0) stats += HomeOverviewStat("fans", fansOn.toString(), if (fansOn == 1) "fan on" else "fans on", Icons.Default.AcUnit, SpudOrange, fanContributors)
    if (motionContributors.isNotEmpty()) stats += HomeOverviewStat("motion", "Active", "motion detected", Icons.AutoMirrored.Filled.DirectionsWalk, SpudOrange, motionContributors)
    if (temperatures.isNotEmpty()) {
        val automaticUnit = rooms.asSequence()
            .flatMap { it.categories.asSequence() }
            .firstOrNull { it.id == "climate" && it.currentTemperature != null }
            ?.temperatureUnit
            ?: temperatures.first().second
        val targetUnit = temperaturePreference.resolvedUnit(automaticUnit)
        val converted = temperatures.map { (value, unit) -> homeConvertTemperature(value, unit, targetUnit) }
        val average = converted.average()
        val convertedContributors = temperatureContributors.mapIndexed { index, contributor ->
            contributor.copy(value = "${formatTemperature(converted[index])}°$targetUnit")
        }
        stats += HomeOverviewStat(
            "temperature", "${formatTemperature(average)}°$targetUnit", "average temperature",
            Icons.Default.Home, SpudGreen, convertedContributors,
        )
    }
    if (humidities.isNotEmpty()) {
        stats += HomeOverviewStat(
            "humidity", "${humidities.average().roundToInt()}%", "average humidity",
            Icons.Default.WaterDrop, SpudGreen, humidityContributors,
        )
    }
    return stats
}

private fun homeRoomDisplaySummary(
    room: HomeRoom,
    temperaturePreference: TemperatureUnitPreference,
): List<String> {
    val temperatureCategories = room.categories.filter {
        it.id in setOf("temperature", "climate") && it.currentTemperature != null
    }
    return room.summary.map { line ->
        val category = temperatureCategories.firstOrNull { candidate ->
            line.startsWith("${candidate.name}:", ignoreCase = true) ||
                line.trim().equals(candidate.summary.trim(), ignoreCase = true) ||
                (temperatureCategories.size == 1 && Regex("°\\s*[FC]", RegexOption.IGNORE_CASE).containsMatchIn(line))
        } ?: return@map line
        val current = category.currentTemperature ?: return@map line
        val targetUnit = temperaturePreference.resolvedUnit(category.temperatureUnit)
        val converted = homeConvertTemperature(current, category.temperatureUnit, targetUnit)
        val mode = category.hvacMode
            .replace('_', ' ')
            .replaceFirstChar { it.uppercase() }
            .takeIf { category.id == "climate" && it.isNotBlank() }
        val value = listOfNotNull("${formatTemperature(converted)}°$targetUnit", mode).joinToString(" · ")
        if (line.startsWith("${category.name}:", ignoreCase = true)) "${category.name}: $value" else value
    }
}

private fun homeCategoryDisplaySummary(
    category: HomeCategory,
    temperaturePreference: TemperatureUnitPreference,
): String {
    val current = category.currentTemperature
    if (current == null || (category.id !in setOf("temperature", "climate") && category.controlType != "thermostat")) {
        return category.summary
    }
    val targetUnit = temperaturePreference.resolvedUnit(category.temperatureUnit)
    val converted = homeConvertTemperature(current, category.temperatureUnit, targetUnit)
    val mode = category.hvacMode
        .replace('_', ' ')
        .replaceFirstChar { it.uppercase() }
        .takeIf { category.controlType == "thermostat" && it.isNotBlank() }
    return listOfNotNull("${formatTemperature(converted)}°$targetUnit", mode).joinToString(" · ")
}

private fun homeFirstNumber(text: String): Double? =
    Regex("-?\\d+(?:\\.\\d+)?").find(text)?.value?.toDoubleOrNull()

private fun homePoweredOnCount(category: HomeCategory): Int = when {
    category.onCount != null -> maxOf(0, category.onCount)
    category.state == "on" -> maxOf(1, category.count)
    category.state == "mixed" -> maxOf(1, homeFirstNumber(category.summary)?.toInt() ?: 1)
    else -> 0
}

private fun homeOpenCount(category: HomeCategory): Int = when {
    category.openCount != null -> maxOf(0, category.openCount)
    category.state in setOf("open", "opening") -> maxOf(1, category.count)
    category.summary.contains("open", ignoreCase = true) && !category.summary.contains("closed", ignoreCase = true) ->
        maxOf(1, homeFirstNumber(category.summary)?.toInt() ?: 1)
    else -> 0
}

private fun homeCategorySourceName(category: HomeCategory, singular: String): String {
    val count = maxOf(1, category.count)
    return "$count $singular${if (count == 1) "" else "s"}"
}

private fun homeMeasurementSourceName(category: HomeCategory, measurement: String): String {
    val count = maxOf(1, category.count)
    return "$count $measurement sensor${if (count == 1) "" else "s"}${if (count > 1) " · room average" else ""}"
}

private fun homeConvertTemperature(value: Double, sourceUnit: String, targetUnit: String): Double {
    if (sourceUnit.uppercase() == targetUnit.uppercase()) return value
    return if (targetUnit.uppercase() == "C") (value - 32) * 5 / 9 else value * 9 / 5 + 32
}

@Composable
private fun RoomDetailScreen(room: HomeRoom, state: LittleSpudUiState, model: LittleSpudViewModel, onBack: () -> Unit) {
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onBack) { Icon(Icons.Default.ChevronLeft, "Back") }
                Column {
                    Text(room.name, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                    Text("${room.controls.size} controls · ${room.sensors.size} sensors", color = SpudMuted)
                }
            }
        }
        if (state.homeError.isNotBlank()) item { FeatureError(state.homeError) }
        room.controls.forEach { category ->
            item(key = "control-${category.id}") {
                HomeControlCard(
                    room.id,
                    category,
                    "${room.id}|${category.id}" in state.homeControlsInFlight,
                    state.temperatureUnitPreference,
                    model,
                )
            }
        }
        room.cameras?.cameraPreviews.orEmpty().forEach { camera ->
            item(key = "camera-${camera.id}") {
                CameraCard(room.id, camera.id, camera.label, state, model)
            }
        }
        if (room.sensors.isNotEmpty()) item {
            Text("Sensors", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 8.dp))
        }
        items(room.sensors, key = { "sensor-${it.id}" }) { sensor ->
            Card(colors = CardDefaults.cardColors(containerColor = SpudPanel), modifier = Modifier.fillMaxWidth()) {
                Row(Modifier.padding(15.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(categoryIcon(sensor.id), null, tint = SpudGreen)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(sensor.name, fontWeight = FontWeight.SemiBold)
                        Text(homeCategoryDisplaySummary(sensor, state.temperatureUnitPreference), color = SpudMuted)
                    }
                }
            }
        }
        item { Spacer(Modifier.height(12.dp)) }
    }
}

@Composable
private fun HomeControlCard(
    roomId: String,
    category: HomeCategory,
    busy: Boolean,
    temperaturePreference: TemperatureUnitPreference,
    model: LittleSpudViewModel,
) {
    var brightness by remember(category.brightness) { mutableFloatStateOf((category.brightness ?: 50.0).toFloat()) }
    Card(colors = CardDefaults.cardColors(containerColor = SpudPanel), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(11.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(categoryIcon(category.id), null, tint = if (category.state == "on" || category.state == "mixed") SpudOrange else SpudMuted)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(category.name, fontWeight = FontWeight.Bold)
                    Text(homeCategoryDisplaySummary(category, temperaturePreference), color = SpudMuted)
                }
                if (busy) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                else if (category.supports("turn_on") || category.supports("turn_off")) {
                    Button(onClick = { model.toggleHomePower(roomId, category) }) {
                        Text(if (category.state == "on" || category.state == "mixed") "Off" else "On")
                    }
                }
            }
            if (category.supportsBrightness && category.supports("set_brightness")) {
                Text("Brightness ${brightness.toInt()}%", style = MaterialTheme.typography.labelMedium, color = SpudMuted)
                Slider(
                    value = brightness,
                    onValueChange = { brightness = it },
                    onValueChangeFinished = { model.performHomeAction(roomId, category, "set_brightness", value = brightness.toDouble()) },
                    valueRange = 1f..100f,
                    enabled = !busy,
                )
            }
            if (category.controlType.contains("thermostat") || category.id.contains("thermostat")) {
                ThermostatControl(roomId, category, busy, temperaturePreference, model)
            }
            if (category.availableActions.any { it in setOf("open", "close", "lock", "unlock") }) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    category.availableActions.filter { it in setOf("open", "close", "lock", "unlock") }.forEach { action ->
                        OutlinedButton(onClick = { model.performHomeAction(roomId, category, action) }, enabled = !busy) {
                            Text(action.replaceFirstChar { it.titlecase() })
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ThermostatControl(
    roomId: String,
    category: HomeCategory,
    busy: Boolean,
    temperaturePreference: TemperatureUnitPreference,
    model: LittleSpudViewModel,
) {
    val reportedUnit = if (category.temperatureUnit.equals("C", ignoreCase = true)) "C" else "F"
    val displayUnit = temperaturePreference.resolvedUnit(reportedUnit)
    var target by remember(category.targetTemperature, category.currentTemperature, reportedUnit, displayUnit) {
        mutableStateOf(
            homeConvertTemperature(
                category.targetTemperature ?: category.currentTemperature ?: if (reportedUnit == "C") 21.0 else 70.0,
                reportedUnit,
                displayUnit,
            ),
        )
    }
    val step = if (reportedUnit != displayUnit) {
        if (displayUnit == "C") 0.5 else 1.0
    } else {
        maxOf(0.5, category.temperatureStep ?: if (displayUnit == "C") 0.5 else 1.0)
    }
    val minimum = category.minimumTemperature?.let {
        homeConvertTemperature(it, reportedUnit, displayUnit)
    } ?: if (displayUnit == "C") 7.0 else 45.0
    val maximum = category.maximumTemperature?.let {
        homeConvertTemperature(it, reportedUnit, displayUnit)
    } ?: if (displayUnit == "C") 32.0 else 90.0
    val current = category.currentTemperature?.let {
        homeConvertTemperature(it, reportedUnit, displayUnit)
    }

    fun setTarget(value: Double) {
        val next = value.coerceIn(minimum, maximum)
        target = next
        model.performHomeAction(
            roomId,
            category,
            "set_temperature",
            value = next,
            temperatureUnit = displayUnit,
        )
    }

    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
        OutlinedButton(
            onClick = { setTarget(target - step) },
            enabled = !busy,
        ) { Text("−") }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("${formatTemperature(target)}°$displayUnit", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            current?.let { Text("Current ${formatTemperature(it)}°$displayUnit", color = SpudMuted, style = MaterialTheme.typography.bodySmall) }
        }
        OutlinedButton(
            onClick = { setTarget(target + step) },
            enabled = !busy,
        ) { Text("+") }
    }
    if (category.availableHvacModes.isNotEmpty() && category.supports("set_hvac_mode")) {
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(7.dp),
            verticalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            category.availableHvacModes.forEach { mode ->
                FilterChip(
                    selected = mode.equals(category.hvacMode, true),
                    onClick = { model.performHomeAction(roomId, category, "set_hvac_mode", mode = mode) },
                    label = { Text(mode.uppercase()) },
                    enabled = !busy,
                )
            }
        }
    }
}

@Composable
private fun CameraCard(roomId: String, cameraId: String, label: String, state: LittleSpudUiState, model: LittleSpudViewModel) {
    val key = "$roomId|$cameraId"
    val image = remember(state.cameraSnapshots[key]) {
        state.cameraSnapshots[key]?.let { bytes -> BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() }
    }
    Card(colors = CardDefaults.cardColors(containerColor = SpudPanel), modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.fillMaxWidth().height(210.dp), contentAlignment = Alignment.Center) {
                if (image != null) Image(image, label, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                else Icon(Icons.Default.CameraAlt, null, Modifier.size(48.dp), tint = SpudMuted)
                if (key in state.cameraLoading) CircularProgressIndicator()
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(label, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                IconButton(onClick = { model.refreshCamera(roomId, cameraId) }) { Icon(Icons.Default.Refresh, "Refresh camera") }
            }
            state.cameraErrors[key]?.let { Text(it, color = SpudDanger, modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp)) }
        }
    }
}

private enum class MusicLibrarySection(val label: String) {
    SEARCH("Search"),
    GENRES("Genres"),
    ARTISTS("Artists"),
    ALBUMS("Albums"),
    RECOMMENDATIONS("Tater Picks"),
}

private data class MusicBrowseSelection(
    val section: MusicLibrarySection,
    val value: String,
)

@Composable
fun MusicScreen(state: LittleSpudUiState, model: LittleSpudViewModel) {
    var section by remember { mutableStateOf(MusicLibrarySection.SEARCH) }
    var browseSelection by remember { mutableStateOf<MusicBrowseSelection?>(null) }
    var playerExpanded by rememberSaveable { mutableStateOf(false) }
    var showTargets by rememberSaveable { mutableStateOf(false) }
    val nowPlaying = state.localMusicTrack ?: state.music.player.current
    val displayedTracks = remember(state.music.tracks, browseSelection) {
        if (browseSelection?.section != MusicLibrarySection.ALBUMS) {
            state.music.tracks
        } else {
            state.music.tracks.filter { it.album.equals(browseSelection?.value, ignoreCase = true) }
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val collapsedPlayerHeight = 168.dp
        val playerHeight by animateDpAsState(
            targetValue = if (playerExpanded) maxHeight else minOf(collapsedPlayerHeight, maxHeight),
            label = "music-player-height",
        )
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = 14.dp,
                top = 14.dp,
                end = 14.dp,
                bottom = collapsedPlayerHeight + 16.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
        if (state.musicError.isNotBlank()) item { FeatureError(state.musicError) }
        if (browseSelection == null) {
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(MusicLibrarySection.entries) { entry ->
                        FilterChip(
                            selected = section == entry,
                            onClick = { section = entry },
                            label = { Text(entry.label) },
                        )
                    }
                }
            }
        } else {
            item {
                val selection = browseSelection ?: return@item
                Card(
                    colors = CardDefaults.cardColors(containerColor = SpudPanelRaised),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        TextButton(
                            onClick = {
                                browseSelection = null
                                section = selection.section
                                model.clearMusicBrowse()
                            },
                        ) {
                            Icon(Icons.Default.ChevronLeft, null)
                            Spacer(Modifier.width(4.dp))
                            Text(selection.section.label)
                        }
                        Text(selection.value, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                        if (selection.section == MusicLibrarySection.ALBUMS) {
                            Button(
                                onClick = { model.playAlbum(displayedTracks) },
                                enabled = displayedTracks.isNotEmpty()
                                    && !state.musicLoading
                                    && state.selectedMusicTargetIds.isNotEmpty(),
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Icon(Icons.Default.PlayArrow, null)
                                Spacer(Modifier.width(6.dp))
                                Text("Play Album")
                            }
                        }
                    }
                }
            }
        }

        when (section) {
            MusicLibrarySection.SEARCH -> {
                if (browseSelection == null) {
                    item {
                        Row(
                            Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            OutlinedTextField(
                                value = state.musicQuery,
                                onValueChange = model::updateMusicQuery,
                                placeholder = { Text("Song, artist, album, or genre") },
                                leadingIcon = { Icon(Icons.Default.Search, null) },
                                singleLine = true,
                                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                                keyboardActions = KeyboardActions(onSearch = { model.searchMusic() }),
                                modifier = Modifier.weight(1f),
                            )
                            IconButton(onClick = { model.refreshMusic(force = true) }) {
                                if (state.musicLoading) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                                else Icon(Icons.Default.Refresh, "Refresh music")
                            }
                        }
                    }
                }
                item {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                        Column(Modifier.weight(1f)) {
                            Text(
                                browseSelection?.value ?: state.music.trackFeedTitle,
                                style = MaterialTheme.typography.titleLarge,
                                fontWeight = FontWeight.Bold,
                            )
                            if (browseSelection == null && state.music.trackFeedSummary.isNotBlank()) {
                                Text(state.music.trackFeedSummary, color = SpudMuted)
                            }
                        }
                        Text("${displayedTracks.size} tracks", color = SpudMuted, style = MaterialTheme.typography.labelMedium)
                    }
                }
                if (state.musicLoading) {
                    item { Box(Modifier.fillMaxWidth().padding(vertical = 44.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
                } else if (displayedTracks.isEmpty()) {
                    item { EmptyFeature("No music found", "Connect Music Core or try another search.") }
                } else {
                    items(displayedTracks, key = { "track-${it.id}" }) { track ->
                        TrackRow(track, state, model)
                    }
                }
            }

            MusicLibrarySection.RECOMMENDATIONS -> {
                item {
                    Column {
                        Text("Tater Recommendations", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        if (state.music.recommendationSummary.isNotBlank()) {
                            Text(state.music.recommendationSummary, color = SpudMuted)
                        }
                    }
                }
                if (state.music.recommendations.isEmpty()) {
                    item { EmptyFeature("No Tater Picks yet", "Play some music to help Tater prepare recommendations.") }
                } else {
                    items(state.music.recommendations, key = { "recommendation-${it.id}" }) { recommendation ->
                        RecommendationCard(recommendation, state, model)
                    }
                }
            }

            else -> {
                val values = when (section) {
                    MusicLibrarySection.GENRES -> state.music.genres
                    MusicLibrarySection.ARTISTS -> state.music.artists
                    MusicLibrarySection.ALBUMS -> state.music.albums
                    else -> emptyList()
                }
                item {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(section.label, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                        Text(values.size.toString(), color = SpudMuted, style = MaterialTheme.typography.labelMedium)
                    }
                }
                if (values.isEmpty()) {
                    item { EmptyFeature("No ${section.label.lowercase()}", "Sync your Music Core catalog and try again.") }
                } else {
                    items(values, key = { "${section.name}-$it" }) { value ->
                        Card(
                            onClick = {
                                browseSelection = MusicBrowseSelection(section, value)
                                model.browseMusic(value)
                                section = MusicLibrarySection.SEARCH
                            },
                            colors = CardDefaults.cardColors(containerColor = SpudPanel),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Default.MusicNote, null, tint = SpudOrange)
                                Spacer(Modifier.width(12.dp))
                                Text(value, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                                Icon(Icons.Default.ChevronRight, null, tint = SpudMuted)
                            }
                        }
                    }
                }
            }
        }
            item { Spacer(Modifier.height(8.dp)) }
        }

        MusicExpandablePlayer(
            track = nowPlaying,
            state = state,
            model = model,
            expanded = playerExpanded,
            onExpandedChange = { playerExpanded = it },
            onChooseTarget = { showTargets = true },
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(
                    horizontal = if (playerExpanded) 0.dp else 10.dp,
                    vertical = if (playerExpanded) 0.dp else 8.dp,
                )
                .fillMaxWidth()
                .height(playerHeight),
        )
    }
    if (showTargets) MusicTargetSheet(state, model, onDismiss = { showTargets = false })
}

@Composable
private fun MusicExpandablePlayer(
    track: MusicTrack?,
    state: LittleSpudUiState,
    model: LittleSpudViewModel,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    onChooseTarget: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isPlaying = if (state.localMusicTrack != null) state.localMusicPlaying else state.music.player.status == "playing"
    val queue = if (state.localMusicTrack != null) state.localMusicQueue else state.music.player.queue
    val queueIndex = if (state.localMusicTrack != null) state.localMusicQueueIndex else state.music.player.queueIndex
    val targetSummary = state.music.targets
        .filter { it.id in state.selectedMusicTargetIds }
        .joinToString { it.label }
        .ifBlank { "Choose player" }
    val duration = (track?.durationSeconds ?: 0.0).coerceAtLeast(state.music.player.durationSeconds).coerceAtLeast(0.0)
    val position = if (state.localMusicTrack != null) 0.0 else state.music.player.positionSeconds.coerceIn(0.0, duration.coerceAtLeast(0.0))
    var volume by remember(state.music.player.volumePercent) {
        mutableFloatStateOf(state.music.player.volumePercent.toFloat())
    }

    Card(
        colors = CardDefaults.cardColors(containerColor = SpudPanelRaised),
        elevation = CardDefaults.cardElevation(defaultElevation = 18.dp),
        shape = RoundedCornerShape(if (expanded) 28.dp else 24.dp),
        modifier = modifier,
    ) {
        Column(Modifier.fillMaxSize()) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(if (expanded) 30.dp else 18.dp)
                    .pointerInput(expanded) {
                        var verticalDrag = 0f
                        detectVerticalDragGestures(
                            onDragStart = { verticalDrag = 0f },
                            onVerticalDrag = { _, amount -> verticalDrag += amount },
                            onDragEnd = {
                                when {
                                    verticalDrag < -24f -> onExpandedChange(true)
                                    verticalDrag > 24f -> onExpandedChange(false)
                                }
                            },
                        )
                    }
                    .clickable { onExpandedChange(!expanded) },
                contentAlignment = Alignment.Center,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Box(
                        Modifier
                            .width(if (expanded) 36.dp else 32.dp)
                            .height(4.dp)
                            .background(SpudMuted.copy(alpha = 0.5f), RoundedCornerShape(50)),
                    )
                    Icon(
                        if (expanded) Icons.Default.KeyboardArrowDown else Icons.Default.KeyboardArrowUp,
                        if (expanded) "Collapse music player" else "Expand music player",
                        tint = SpudMuted,
                        modifier = Modifier.size(15.dp),
                    )
                }
            }

            if (expanded) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    PlayerArtwork(track, state, 62)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(track?.title ?: "Nothing playing", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(
                            track?.subtitle?.ifBlank { state.music.provider?.label.orEmpty() }
                                ?: state.music.provider?.label
                                ?: "Choose something from your library",
                            color = SpudMuted,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Row(
                            Modifier.clickable(onClick = onChooseTarget).padding(vertical = 3.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(5.dp),
                        ) {
                            Icon(Icons.Default.Speaker, null, Modifier.size(16.dp), tint = SpudOrange)
                            Text(targetSummary, color = SpudOrange, style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            } else {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    PlayerArtwork(track, state, 48)
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(track?.title ?: "Nothing playing", fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(
                            track?.displayArtist?.ifBlank { state.music.provider?.label.orEmpty() }
                                ?: state.music.provider?.label
                                ?: "Music Core",
                            color = SpudMuted,
                            style = MaterialTheme.typography.labelMedium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    IconButton(onClick = { model.skipMusic(-1) }, enabled = track != null, modifier = Modifier.size(38.dp)) {
                        Icon(Icons.Default.SkipPrevious, "Previous", Modifier.size(22.dp))
                    }
                    IconButton(
                        onClick = model::toggleMusicPlayback,
                        enabled = track != null,
                        modifier = Modifier.size(44.dp).background(
                            if (track != null) SpudOrange else SpudMuted.copy(alpha = 0.25f),
                            CircleShape,
                        ),
                    ) {
                        Icon(
                            if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                            if (isPlaying) "Pause" else "Play",
                            Modifier.size(27.dp),
                            tint = MaterialTheme.colorScheme.background,
                        )
                    }
                    IconButton(onClick = { model.skipMusic(1) }, enabled = track != null, modifier = Modifier.size(38.dp)) {
                        Icon(Icons.Default.SkipNext, "Next", Modifier.size(22.dp))
                    }
                }
            }

            Column(Modifier.fillMaxWidth().padding(horizontal = if (expanded) 14.dp else 12.dp, vertical = 2.dp)) {
                LinearProgressIndicator(
                    progress = { if (duration > 0) (position / duration).toFloat() else 0f },
                    modifier = Modifier.fillMaxWidth().height(3.dp),
                    color = SpudOrange,
                    trackColor = SpudMuted.copy(alpha = 0.22f),
                )
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(formatMusicTime(position), color = SpudMuted, style = MaterialTheme.typography.labelSmall)
                    Text(formatMusicTime(duration), color = SpudMuted, style = MaterialTheme.typography.labelSmall)
                }
            }

            if (expanded) {
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = { model.skipMusic(-1) }, enabled = track != null) { Icon(Icons.Default.SkipPrevious, "Previous") }
                    IconButton(
                        onClick = model::toggleMusicPlayback,
                        enabled = track != null,
                        modifier = Modifier.size(48.dp).background(
                            if (track != null) SpudOrange else SpudMuted.copy(alpha = 0.25f),
                            CircleShape,
                        ),
                    ) {
                        Icon(
                            if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                            if (isPlaying) "Pause" else "Play",
                            Modifier.size(30.dp),
                            tint = MaterialTheme.colorScheme.background,
                        )
                    }
                    IconButton(onClick = model::stopMusic, enabled = track != null) { Icon(Icons.Default.Stop, "Stop") }
                    IconButton(onClick = { model.skipMusic(1) }, enabled = track != null) { Icon(Icons.Default.SkipNext, "Next") }
                }
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 1.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.AutoMirrored.Filled.VolumeUp, null, Modifier.size(18.dp), tint = SpudMuted)
                    Slider(
                        value = volume,
                        onValueChange = { volume = it },
                        onValueChangeFinished = { model.setMusicVolume(volume.toInt()) },
                        valueRange = 0f..100f,
                        modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
                    )
                    Text("${volume.toInt()}%", color = SpudMuted, style = MaterialTheme.typography.labelSmall, modifier = Modifier.width(34.dp))
                }
                HorizontalDivider(color = SpudMuted.copy(alpha = 0.2f))
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(state.music.player.radioName.ifBlank { "Current Playlist" }, fontWeight = FontWeight.Bold)
                        Text("${queue.size} tracks", color = SpudMuted, style = MaterialTheme.typography.labelMedium)
                    }
                    if (state.music.player.continuousRadio) {
                        Text("∞ Continuous", color = SpudOrange, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                    }
                }

                if (queue.isEmpty()) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text("Choose something from your library to build a playlist.", color = SpudMuted)
                    }
                } else {
                    LazyColumn(
                        Modifier.fillMaxWidth().weight(1f),
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                        verticalArrangement = Arrangement.spacedBy(7.dp),
                    ) {
                        items(queue.size, key = { index -> "queue-$index-${queue[index].id}" }) { index ->
                            val queuedTrack = queue[index]
                            val current = index == queueIndex
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .background(
                                        if (current) SpudOrange.copy(alpha = 0.13f) else SpudPanel,
                                        RoundedCornerShape(13.dp),
                                    )
                                    .padding(horizontal = 10.dp, vertical = 7.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text("${index + 1}", color = if (current) SpudOrange else SpudMuted, style = MaterialTheme.typography.labelSmall)
                                Spacer(Modifier.width(9.dp))
                                Artwork(queuedTrack, state, 38)
                                Spacer(Modifier.width(10.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(queuedTrack.title, fontWeight = if (current) FontWeight.SemiBold else FontWeight.Normal, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text(queuedTrack.artist, color = SpudMuted, style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                }
                                Text(queuedTrack.durationDisplay, color = SpudMuted, style = MaterialTheme.typography.labelSmall)
                            }
                        }
                    }
                }
            } else {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    TextButton(onClick = onChooseTarget, modifier = Modifier.weight(0.9f)) {
                        Icon(Icons.Default.Speaker, null, Modifier.size(16.dp))
                        Spacer(Modifier.width(5.dp))
                        Text(targetSummary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Icon(Icons.AutoMirrored.Filled.VolumeUp, null, Modifier.size(17.dp), tint = SpudMuted)
                    Slider(
                        value = volume,
                        onValueChange = { volume = it },
                        onValueChangeFinished = { model.setMusicVolume(volume.toInt()) },
                        valueRange = 0f..100f,
                        modifier = Modifier.weight(1f).padding(horizontal = 5.dp),
                    )
                    Text("${volume.toInt()}%", color = SpudMuted, style = MaterialTheme.typography.labelSmall, modifier = Modifier.width(32.dp))
                }
            }
        }
    }
}

@Composable
private fun MusicTargetSheet(
    state: LittleSpudUiState,
    model: LittleSpudViewModel,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(horizontal = 16.dp, vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Play on", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                    Text("Choose one or more playback devices.", color = SpudMuted, style = MaterialTheme.typography.bodySmall)
                }
                TextButton(onClick = onDismiss) { Text("Done") }
            }
            if (state.music.targets.isEmpty()) {
                Text("No playback devices are available.", color = SpudMuted, modifier = Modifier.padding(vertical = 28.dp))
            } else {
                state.music.targets.forEach { target ->
                    val selected = target.id in state.selectedMusicTargetIds
                    Card(
                        onClick = { model.toggleMusicTarget(target.id) },
                        colors = CardDefaults.cardColors(
                            containerColor = if (selected) SpudOrange.copy(alpha = 0.14f) else SpudPanel,
                        ),
                        shape = RoundedCornerShape(16.dp),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Row(
                            Modifier.fillMaxWidth().padding(13.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Icon(Icons.Default.Speaker, null, tint = SpudOrange, modifier = Modifier.size(24.dp))
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(target.label, fontWeight = FontWeight.SemiBold, maxLines = 2)
                                Text(
                                    target.description.ifBlank {
                                        if (target.isLocal) "This Android device" else "Music Core playback device"
                                    },
                                    color = SpudMuted,
                                    style = MaterialTheme.typography.bodySmall,
                                )
                            }
                            Icon(
                                if (selected) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked,
                                if (selected) "Selected" else "Not selected",
                                tint = if (selected) SpudOrange else SpudMuted,
                            )
                        }
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun PlayerArtwork(track: MusicTrack?, state: LittleSpudUiState, size: Int) {
    if (track != null) {
        Artwork(track, state, size)
    } else {
        Card(
            colors = CardDefaults.cardColors(containerColor = SpudPanelRaised),
            shape = RoundedCornerShape((size / 5).dp),
            modifier = Modifier.size(size.dp),
        ) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Icon(Icons.Default.MusicNote, null, tint = SpudOrange)
            }
        }
    }
}

private fun formatMusicTime(seconds: Double): String {
    val total = seconds.coerceAtLeast(0.0).toInt()
    return "%d:%02d".format(total / 60, total % 60)
}

@Composable
private fun RecommendationCard(recommendation: MusicRecommendation, state: LittleSpudUiState, model: LittleSpudViewModel) {
    Card(colors = CardDefaults.cardColors(containerColor = SpudPanel), modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            val first = recommendation.tracks.firstOrNull()
            if (first != null) Artwork(first, state, 58) else Icon(Icons.Default.MusicNote, null, Modifier.size(58.dp), tint = SpudOrange)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(recommendation.name, fontWeight = FontWeight.Bold)
                Text(recommendation.description.ifBlank { "${recommendation.tracks.size} tracks" }, color = SpudMuted, maxLines = 2)
            }
            IconButton(onClick = { model.playRecommendation(recommendation) }) { Icon(Icons.Default.PlayArrow, "Play mix") }
        }
    }
}

@Composable
private fun TrackRow(track: MusicTrack, state: LittleSpudUiState, model: LittleSpudViewModel) {
    Card(onClick = { model.playMusic(track) }, colors = CardDefaults.cardColors(containerColor = SpudPanel), modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Artwork(track, state, 52)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(track.title, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(track.subtitle, color = SpudMuted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (track.durationDisplay.isNotBlank()) Text(track.durationDisplay, color = SpudMuted, style = MaterialTheme.typography.labelMedium)
            Icon(Icons.Default.PlayArrow, null, tint = SpudOrange)
        }
    }
}

@Composable
private fun Artwork(track: MusicTrack, state: LittleSpudUiState, size: Int) {
    val url = remember(track.artworkUrl, state.session?.hubUrl) { resolveArtworkUrl(state.session?.hubUrl.orEmpty(), track.artworkUrl) }
    if (url.isNotBlank()) {
        AsyncImage(
            model = url,
            contentDescription = track.title,
            modifier = Modifier.size(size.dp).clip(RoundedCornerShape((size / 5).dp)),
            contentScale = ContentScale.Crop,
        )
    } else {
        Card(
            colors = CardDefaults.cardColors(containerColor = SpudPanelRaised),
            shape = RoundedCornerShape((size / 5).dp),
            modifier = Modifier.size(size.dp),
        ) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(Icons.Default.MusicNote, null, tint = SpudOrange) }
        }
    }
}

private fun resolveArtworkUrl(base: String, value: String): String {
    val clean = value.trim()
    if (clean.isBlank() || clean.startsWith("data:")) return ""
    val parsed = Uri.parse(clean)
    if (!parsed.scheme.isNullOrBlank()) return clean
    return base.trimEnd('/') + "/" + clean.trimStart('/')
}

@Composable
private fun FeatureError(message: String) {
    Card(colors = CardDefaults.cardColors(containerColor = SpudDanger.copy(alpha = 0.14f)), modifier = Modifier.fillMaxWidth()) {
        Text(message, Modifier.padding(12.dp), color = SpudDanger)
    }
}

@Composable
private fun EmptyFeature(title: String, description: String) {
    Column(Modifier.fillMaxWidth().padding(vertical = 60.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(6.dp)); Text(description, color = SpudMuted)
    }
}

private fun roomIcon(room: HomeRoom) = when {
    room.name.contains("garage", ignoreCase = true) -> Icons.Default.Garage
    room.name.contains("bed", ignoreCase = true) -> Icons.Default.Bed
    room.name.contains("kitchen", ignoreCase = true) -> Icons.Default.Restaurant
    room.name.contains("office", ignoreCase = true) -> Icons.Default.Computer
    room.name.contains("living", ignoreCase = true) -> Icons.Default.Weekend
    room.name.contains("bath", ignoreCase = true) -> Icons.Default.Bathtub
    else -> Icons.Default.Home
}

private fun categoryIcon(id: String) = when {
    id.contains("light") -> Icons.Default.Lightbulb
    id.contains("temperature") || id.contains("thermostat") -> Icons.Default.Thermostat
    id.contains("lock") || id.contains("door") -> Icons.Default.Lock
    id.contains("leak") || id.contains("water") -> Icons.Default.WaterDrop
    id.contains("climate") || id.contains("fan") -> Icons.Default.AcUnit
    else -> Icons.Default.ToggleOn
}

private fun formatTemperature(value: Double): String = if (value % 1.0 == 0.0) value.toInt().toString() else "%.1f".format(value)
