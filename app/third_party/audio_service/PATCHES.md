# audio_service, vendored

Copy of `audio_service` **0.18.19** from pub.dev, with one change. Vendored
rather than forked on GitHub so there is no second repository to keep alive,
and so the difference from upstream is one file that can be read in a minute.

`example/` and `test/` are not copied.

## The change

`android/src/main/java/com/ryanheise/audioservice/AudioService.java`,
`buildNotification()`: `builder.setStyle(style)` is now conditional.

Some OEM system UIs intercept MediaStyle notifications and re-render them with
their own media widget, which shows artwork, title and artist and **drops every
transport action**. On the device this app is built for — Transsion XOS,
Android 11 — the notification was provably complete:

```
android.template   = android.app.Notification$MediaStyle
android.compactActions = int[] (3)
android.mediaSession   = Token
actions=4  category=transport  flags=0x62
```

and the rendered view tree contained `album_art`, `header_title`,
`header_artist`, `media_page_indicator` — and no `action0..action4` at all. The
same system UI draws action buttons correctly on ordinary notifications, which
is what made the cause identifiable rather than a guess.

Opting out of MediaStyle keeps the identical notification and the identical
actions, and lets them be drawn as an ordinary notification.

## Taking it

Off by default — without the meta-data below the behaviour is stock upstream.

```xml
<meta-data
    android:name="com.ryanheise.audioservice.PLAIN_NOTIFICATION"
    android:value="true"/>
```

## What it costs

MediaStyle is the better presentation everywhere it is honoured: the compact
media card, and on stock Android the media panel in Quick Settings. Turning it
off trades that for controls that exist. Only turn it on for a build whose
target device is known to strip them.

The media session itself is untouched, so headset buttons, Bluetooth controls
and anything else driving `MediaSession` keep working either way.

## Re-syncing to a newer audio_service

1. `rsync -a --exclude example/ --exclude test/ ~/.pub-cache/hosted/pub.dev/audio_service-<v>/ app/third_party/audio_service/`
2. Re-apply the patch above — it is one `if` and one helper method.
3. Update the version named at the top of this file.
