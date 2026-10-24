package com.currentsuspect.tunes

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioManager
import android.os.SystemClock
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews

/**
 * Tunes on the home screen (the Roon pass, approved 24 Oct; asked for by
 * Angel): a player, the lyric line being sung, and a small one.
 *
 * The app reports what is playing over "tunes/widgets" (Dart
 * HomeWidgetsBridge), only when something they show changes; it is kept
 * here and every widget redrawn. Their buttons send media keys, as the Quick
 * Settings tile does, so they reach whichever session is playing without
 * binding to anything.
 */
object TunesWidgets {
    private const val PREFS = "tunes_widgets"
    const val ACTION = "com.currentsuspect.tunes.WIDGET_ACTION"
    const val EXTRA_KEY = "key"

    /** The app's report, kept and drawn. */
    fun publish(context: Context, report: Map<String, Any?>) {
        val e = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        for ((k, v) in report) {
            when (v) {
                is Boolean -> e.putBoolean(k, v)
                is Int -> e.putLong(k, v.toLong())
                is Long -> e.putLong(k, v)
                is String -> e.putString(k, v)
                else -> e.remove(k)
            }
        }
        e.apply()
        redrawAll(context)
    }

    fun redrawAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        for (provider in listOf(
            PlayerWidgetProvider::class.java,
            LyricsWidgetProvider::class.java,
            MiniWidgetProvider::class.java,
        )) {
            val ids = manager.getAppWidgetIds(ComponentName(context, provider))
            if (ids.isNotEmpty()) draw(context, manager, ids, provider)
        }
    }

    fun draw(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
        provider: Class<*>,
    ) {
        val p = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val has = p.getBoolean("hasTrack", false)
        val playing = p.getBoolean("playing", false)
        val title = p.getString("title", "") ?: ""
        val artist = p.getString("artist", "") ?: ""
        val views = when (provider) {
            PlayerWidgetProvider::class.java -> RemoteViews(context.packageName, R.layout.widget_player).apply {
                setTextViewText(R.id.widget_kicker, if (!has) "TUNES" else if (playing) "TUNES · PLAYING" else "TUNES · PAUSED")
                setTextViewText(R.id.widget_title, if (has) title else "Pick up where you left off")
                setTextViewText(R.id.widget_artist, if (has) artist else "Open Tunes to play")
                val dur = p.getLong("durationMs", 0)
                val pos = p.getLong("positionMs", 0)
                setProgressBar(R.id.widget_progress, 1000, if (dur > 0) ((pos * 1000) / dur).toInt() else 0, false)
                val art = cover(p.getString("art", null))
                if (art != null) setImageViewBitmap(R.id.widget_art, art)
                else setImageViewResource(R.id.widget_art, android.R.color.transparent)
                setImageViewResource(R.id.widget_play, if (playing) R.drawable.ic_widget_pause_white else R.drawable.ic_widget_play_white)
                setOnClickPendingIntent(R.id.widget_play, key(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
                setOnClickPendingIntent(R.id.widget_next, key(context, KeyEvent.KEYCODE_MEDIA_NEXT))
                setOnClickPendingIntent(R.id.widget_prev, key(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
                setOnClickPendingIntent(R.id.widget_root, open(context))
            }
            LyricsWidgetProvider::class.java -> RemoteViews(context.packageName, R.layout.widget_lyrics).apply {
                val kind = p.getString("lyricsKind", "none")
                val line = p.getString("line", "") ?: ""
                val prev = p.getString("linePrev", "") ?: ""
                val next = p.getString("lineNext", "") ?: ""
                when {
                    !has -> {
                        setTextViewText(R.id.widget_line_prev, "")
                        setTextViewText(R.id.widget_line, "Nothing playing")
                        setTextViewText(R.id.widget_line_next, "The words follow along when a song plays.")
                    }
                    kind == "timed" -> {
                        setTextViewText(R.id.widget_line_prev, prev)
                        // Before the first line, the first line is what comes.
                        setTextViewText(R.id.widget_line, if (line.isEmpty()) "♪" else line)
                        setTextViewText(R.id.widget_line_next, next)
                    }
                    kind == "plain" -> {
                        setTextViewText(R.id.widget_line_prev, "")
                        setTextViewText(R.id.widget_line, line)
                        setTextViewText(R.id.widget_line_next, "These lyrics are not timed yet, so they don't follow along.")
                    }
                    else -> {
                        setTextViewText(R.id.widget_line_prev, "")
                        setTextViewText(R.id.widget_line, "No lyrics for this song")
                        setTextViewText(R.id.widget_line_next, "")
                    }
                }
                setViewVisibility(R.id.widget_line_prev, if (prev.isEmpty() || kind != "timed") View.GONE else View.VISIBLE)
                setTextViewText(R.id.widget_song, if (has) "$title · $artist" else "Tunes")
                setOnClickPendingIntent(R.id.widget_root, open(context))
            }
            else -> RemoteViews(context.packageName, R.layout.widget_mini).apply {
                setTextViewText(R.id.widget_title, if (has) title else "Tunes")
                setTextViewText(R.id.widget_artist, if (has) artist else "Nothing playing")
                setImageViewResource(R.id.widget_play, if (playing) R.drawable.ic_widget_pause_ink else R.drawable.ic_widget_play_ink)
                setOnClickPendingIntent(R.id.widget_play, key(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
                setOnClickPendingIntent(R.id.widget_root, open(context))
            }
        }
        manager.updateAppWidget(ids, views)
    }

    /** The cover, read small: a widget is a few hundred pixels, and a
     *  RemoteViews bitmap travels between processes. */
    private fun cover(path: String?): Bitmap? {
        if (path.isNullOrEmpty()) return null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= 320) sample *= 2
            BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
        } catch (e: Exception) {
            null
        }
    }

    private fun key(context: Context, code: Int): PendingIntent {
        val intent = Intent(context, WidgetActionReceiver::class.java)
            .setAction(ACTION)
            .putExtra(EXTRA_KEY, code)
        return PendingIntent.getBroadcast(
            context,
            code,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun open(context: Context): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

/** A widget button: the media key it stands for, to whatever is playing. */
class WidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TunesWidgets.ACTION) return
        val code = intent.getIntExtra(TunesWidgets.EXTRA_KEY, 0)
        if (code == 0) return
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val now = SystemClock.uptimeMillis()
        for (action in intArrayOf(KeyEvent.ACTION_DOWN, KeyEvent.ACTION_UP)) {
            audio.dispatchMediaKeyEvent(KeyEvent(now, now, action, code, 0))
        }
    }
}

open class TunesWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        TunesWidgets.draw(context, manager, ids, javaClass)
    }
}

class PlayerWidgetProvider : TunesWidgetProvider()
class LyricsWidgetProvider : TunesWidgetProvider()
class MiniWidgetProvider : TunesWidgetProvider()
