package com.tatertotterson.littlespud.android.model

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelsTest {
    @Test
    fun legacySessionMigratesToHomeRoute() {
        val json = JSONObject().apply {
            put("hubUrl", "http://tater.local:8000/")
            put("token", "secret")
            put("userName", "Alex")
            put("deviceName", "Pixel")
            put("nodeName", "Alex on Pixel")
            put("hubName", "Kitchen Tater")
            put("hubMode", "home")
        }

        val session = LittleSpudSession.fromJson(json)

        assertEquals("http://tater.local:8000/", session.homeHubUrl)
        assertEquals(ConnectionRoute.HOME, session.activeRoute)
        assertEquals(ConnectionRoute.HOME, session.displayRoute)
        assertEquals("Tater", session.assistantName)
    }

    @Test
    fun sessionRoundTripPreservesAwayRouteAndOptionalValues() {
        val source = LittleSpudSession(
            hubUrl = "https://tater.example.com",
            homeHubUrl = "http://tater.local:8000",
            awayHubUrl = "https://tater.example.com",
            activeRoute = ConnectionRoute.AWAY,
            token = "secret",
            userName = "Alex",
            deviceName = "Pixel",
            nodeName = "Little Spud",
            hubName = "Tater",
            hubMode = "away",
            assistantName = "Tot",
            toolsEnabled = null,
            pairedAt = 1_700_000_000_000,
            lastSeenAt = 1_700_000_001_000,
        )

        val decoded = LittleSpudSession.fromJson(source.toJson())

        assertEquals(source, decoded)
        assertEquals(ConnectionRoute.AWAY, decoded.displayRoute)
        assertNull(decoded.toolsEnabled)
    }

    @Test
    fun messageRoundTripKeepsNotificationAndAttachmentMetadata() {
        val source = LittleSpudMessage(
            id = "notification-1",
            role = LittleSpudRole.ASSISTANT,
            content = "Front door opened",
            createdAt = 1_700_000_000_000,
            kind = "notification",
            attachments = listOf(
                LittleSpudAttachment("camera-1", "porch.jpg", "image/jpeg", 42, "https://example.test/porch", ""),
            ),
            notificationTitle = "Front Door",
            notificationBody = "Front door opened",
            notificationPriority = "urgent",
        )

        val decoded = LittleSpudMessage.fromJson(source.toJson())

        assertEquals(source, decoded)
        assertEquals("porch.jpg", decoded?.attachments?.single()?.displayName)
    }

    @Test
    fun awarenessFaceIdSummaryIsSeparatedFromTheNotificationBody() {
        val notification = LittleSpudMessage(
            role = LittleSpudRole.ASSISTANT,
            content = "Back Yard Camera\n\nA person walked through the yard.\n\nFace ID: Fred recognized.",
            kind = "notification",
            notificationTitle = "Back Yard Camera",
            notificationBody = "A person walked through the yard.\n\nFace ID: Fred recognized.",
        )

        assertEquals("A person walked through the yard.", notification.notificationDisplayBody)
        assertEquals("Fred recognized", notification.notificationFaceIdSummary)
    }

    @Test
    fun dateParserHandlesSecondsMillisecondsAndIso8601() {
        assertEquals(1_700_000_000_000, JSONObject().put("ts", 1_700_000_000).dateMillis("ts"))
        assertEquals(1_700_000_000_000, JSONObject().put("ts", 1_700_000_000_000).dateMillis("ts"))
        assertEquals(1_700_000_000_000, JSONObject().put("ts", "2023-11-14T22:13:20Z").dateMillis("ts"))
    }

    @Test
    fun jsonBooleanParserAcceptsWireRepresentations() {
        assertTrue(JSONObject().put("value", "yes").booleanOrNull("value") == true)
        assertFalse(JSONObject().put("value", 0).booleanOrNull("value") == true)
        assertNull(JSONObject().put("value", "unknown").booleanOrNull("value"))
    }

    @Test
    fun temperaturePreferenceResolvesAndRestoresUnits() {
        assertEquals("C", TemperatureUnitPreference.AUTOMATIC.resolvedUnit("C"))
        assertEquals("F", TemperatureUnitPreference.AUTOMATIC.resolvedUnit("unknown"))
        assertEquals("F", TemperatureUnitPreference.FAHRENHEIT.resolvedUnit("C"))
        assertEquals("C", TemperatureUnitPreference.CELSIUS.resolvedUnit("F"))
        assertEquals(
            TemperatureUnitPreference.CELSIUS,
            TemperatureUnitPreference.fromStorage("celsius"),
        )
        assertEquals(
            TemperatureUnitPreference.AUTOMATIC,
            TemperatureUnitPreference.fromStorage("unsupported"),
        )
    }

    @Test
    fun artworkCacheKeyIsSharedBySongsOnTheSameAlbum() {
        val first = musicTrack(
            id = "track-one",
            title = "One",
            artworkUrl = "/artwork/track-one",
        )
        val second = musicTrack(
            id = "track-two",
            title = "Two",
            artworkUrl = "/artwork/track-two",
        )

        assertEquals(first.artworkCacheKey, second.artworkCacheKey)
    }

    @Test
    fun artworkCacheKeyFallsBackPerTrackWithoutAlbumMetadata() {
        val first = musicTrack(id = "track-one", title = "One", album = "", artworkUrl = "")
        val second = musicTrack(id = "track-two", title = "Two", album = "", artworkUrl = "")

        assertFalse(first.artworkCacheKey == second.artworkCacheKey)
    }

    private fun musicTrack(
        id: String,
        title: String,
        album: String = "Shared Album",
        artworkUrl: String,
    ) = MusicTrack(
        id = id,
        title = title,
        artist = "Track Artist",
        albumArtist = "Album Artist",
        album = album,
        genre = "",
        durationSeconds = 180.0,
        durationDisplay = "3:00",
        provider = "tater_tube",
        artworkUrl = artworkUrl,
    )
}
