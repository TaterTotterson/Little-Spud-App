package com.tatertotterson.littlespud.android.playback

import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.tatertotterson.littlespud.android.MainActivity
import com.tatertotterson.littlespud.android.model.MusicTrack

class MusicPlaybackService : MediaSessionService() {
    private var player: ExoPlayer? = null
    private var mediaSession: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        val playbackPlayer = ExoPlayer.Builder(this)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .setUsage(C.USAGE_MEDIA)
                    .build(),
                true,
            )
            .setHandleAudioBecomingNoisy(true)
            .build()
            .apply {
                setWakeMode(C.WAKE_MODE_NETWORK)
            }
        val activityIntent = Intent(this, MainActivity::class.java)
        val sessionActivity = PendingIntent.getActivity(
            this,
            0,
            activityIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        player = playbackPlayer
        mediaSession = MediaSession.Builder(this, playbackPlayer)
            .setSessionActivity(sessionActivity)
            .build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = mediaSession

    override fun onTaskRemoved(rootIntent: Intent?) {
        val activePlayer = player
        if (activePlayer == null ||
            activePlayer.mediaItemCount == 0 ||
            (!activePlayer.playWhenReady && activePlayer.playbackState != Player.STATE_BUFFERING)
        ) {
            stopSelf()
        }
    }

    override fun onDestroy() {
        mediaSession?.release()
        mediaSession = null
        player?.release()
        player = null
        super.onDestroy()
    }
}

fun MusicTrack.toPlaybackMediaItem(streamUrl: String, hubUrl: String): MediaItem {
    val extras = Bundle().apply {
        putString(EXTRA_TITLE, title)
        putString(EXTRA_ARTIST, artist)
        putString(EXTRA_ALBUM_ARTIST, albumArtist)
        putString(EXTRA_ALBUM, album)
        putString(EXTRA_GENRE, genre)
        putDouble(EXTRA_DURATION_SECONDS, durationSeconds)
        putString(EXTRA_DURATION_DISPLAY, durationDisplay)
        putString(EXTRA_PROVIDER, provider)
        putString(EXTRA_ARTWORK_URL, artworkUrl)
    }
    val metadata = MediaMetadata.Builder()
        .setTitle(title)
        .setArtist(displayArtist)
        .setAlbumArtist(albumArtist)
        .setAlbumTitle(album)
        .setGenre(genre)
        .setDurationMs((durationSeconds.coerceAtLeast(0.0) * 1_000).toLong())
        .setIsPlayable(true)
        .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
        .setExtras(extras)
        .apply {
            resolveArtworkUri(hubUrl, artworkUrl)?.let { setArtworkUri(it) }
        }
        .build()
    return MediaItem.Builder()
        .setMediaId(id)
        .setUri(streamUrl)
        .setMediaMetadata(metadata)
        .build()
}

fun MediaItem.toMusicTrack(): MusicTrack? {
    if (mediaId.isBlank()) return null
    val extras = mediaMetadata.extras
    return MusicTrack(
        id = mediaId,
        title = extras?.getString(EXTRA_TITLE).orEmpty().ifBlank {
            mediaMetadata.title?.toString().orEmpty()
        },
        artist = extras?.getString(EXTRA_ARTIST).orEmpty().ifBlank {
            mediaMetadata.artist?.toString().orEmpty()
        },
        albumArtist = extras?.getString(EXTRA_ALBUM_ARTIST).orEmpty().ifBlank {
            mediaMetadata.albumArtist?.toString().orEmpty()
        },
        album = extras?.getString(EXTRA_ALBUM).orEmpty().ifBlank {
            mediaMetadata.albumTitle?.toString().orEmpty()
        },
        genre = extras?.getString(EXTRA_GENRE).orEmpty().ifBlank {
            mediaMetadata.genre?.toString().orEmpty()
        },
        durationSeconds = extras?.getDouble(EXTRA_DURATION_SECONDS)
            ?.takeIf { it > 0.0 }
            ?: ((mediaMetadata.durationMs ?: 0L) / 1_000.0),
        durationDisplay = extras?.getString(EXTRA_DURATION_DISPLAY).orEmpty(),
        provider = extras?.getString(EXTRA_PROVIDER).orEmpty(),
        artworkUrl = extras?.getString(EXTRA_ARTWORK_URL).orEmpty()
            .ifBlank { mediaMetadata.artworkUri?.toString().orEmpty() },
    )
}

private fun resolveArtworkUri(hubUrl: String, artworkUrl: String): Uri? {
    val clean = artworkUrl.trim()
    if (clean.isBlank() || clean.startsWith("data:", ignoreCase = true)) return null
    val parsed = Uri.parse(clean)
    if (!parsed.scheme.isNullOrBlank()) return parsed
    if (hubUrl.isBlank()) return null
    return Uri.parse(hubUrl.trimEnd('/') + "/" + clean.trimStart('/'))
}

private const val EXTRA_TITLE = "little_spud.title"
private const val EXTRA_ARTIST = "little_spud.artist"
private const val EXTRA_ALBUM_ARTIST = "little_spud.album_artist"
private const val EXTRA_ALBUM = "little_spud.album"
private const val EXTRA_GENRE = "little_spud.genre"
private const val EXTRA_DURATION_SECONDS = "little_spud.duration_seconds"
private const val EXTRA_DURATION_DISPLAY = "little_spud.duration_display"
private const val EXTRA_PROVIDER = "little_spud.provider"
private const val EXTRA_ARTWORK_URL = "little_spud.artwork_url"
