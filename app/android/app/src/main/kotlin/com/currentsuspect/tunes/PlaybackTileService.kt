package com.currentsuspect.tunes

import android.content.ComponentName
import android.content.Context
import android.graphics.drawable.Icon
import android.media.AudioManager
import android.os.Build
import android.os.SystemClock
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.view.KeyEvent

/**
 * Play and pause from the Quick Settings panel.
 *
 * A tile rather than another notification: this ROM's system UI rewrites media
 * notifications and can drop what they carry, but a tile is drawn from our own
 * [Tile] object and there is nothing in between to reinterpret it. It is also
 * reachable from the lock screen and from inside any other app, which is where
 * a pause is usually wanted.
 *
 * The click is dispatched as a media key rather than by binding to the audio
 * service. A media key goes to whichever session is active, so the tile keeps
 * working regardless of how playback was started, and it needs no permission
 * to talk to anything.
 */
class PlaybackTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        refresh()
    }

    override fun onClick() {
        super.onClick()
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val now = SystemClock.uptimeMillis()
        for (action in intArrayOf(KeyEvent.ACTION_DOWN, KeyEvent.ACTION_UP)) {
            audio.dispatchMediaKeyEvent(
                KeyEvent(now, now, action, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 0)
            )
        }
        // Flip locally so the tile answers the tap immediately. The app
        // corrects this the moment playback actually changes; a tile that
        // waits for a round trip reads as a tile that did not register.
        val prefs = prefs()
        prefs.edit()
            .putBoolean(KEY_PLAYING, !prefs.getBoolean(KEY_PLAYING, false))
            .apply()
        refresh()
    }

    private fun prefs() = applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun refresh() {
        val tile = qsTile ?: return
        val prefs = prefs()
        val playing = prefs.getBoolean(KEY_PLAYING, false)
        val track = prefs.getString(KEY_TITLE, null)

        tile.label = "tunes"
        tile.state = if (playing) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.icon = Icon.createWithResource(
            this,
            if (playing) R.drawable.ic_tile_pause else R.drawable.ic_tile_play,
        )
        tile.contentDescription = if (playing) "Pause tunes" else "Play tunes"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Says what it would act on. A transport control with no idea what
            // it is controlling is a coin toss.
            tile.subtitle = track ?: "Nothing playing"
        }
        tile.updateTile()
    }

    companion object {
        private const val PREFS = "tunes_tile"
        private const val KEY_PLAYING = "playing"
        private const val KEY_TITLE = "title"

        /**
         * Called from the app when playback changes, so the tile is right
         * before it is looked at rather than after it is tapped.
         */
        fun publish(context: Context, playing: Boolean, title: String?) {
            context.applicationContext
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_PLAYING, playing)
                .putString(KEY_TITLE, title)
                .apply()
            try {
                requestListeningState(
                    context,
                    ComponentName(context, PlaybackTileService::class.java),
                )
            } catch (e: Exception) {
                // The tile may not be added to Quick Settings at all, which is
                // not a failure -- it just means nobody is listening.
            }
        }
    }
}
