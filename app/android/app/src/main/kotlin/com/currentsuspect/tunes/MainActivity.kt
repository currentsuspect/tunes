package com.currentsuspect.tunes

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: android.content.Context): FlutterEngine? {
        val engine = super.provideFlutterEngine(context) ?: FlutterEngine(context)
        FlutterEngineCache.getInstance().put("audio_service_engine", engine)
        return engine
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Lets the app tell the Quick Settings tile what is playing, so the
        // tile is right before it is looked at rather than after it is
        // tapped. Fire and forget -- the tile may not even be added.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tunes/tile")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "publish" -> {
                        PlaybackTileService.publish(
                            applicationContext,
                            call.argument<Boolean>("playing") ?: false,
                            call.argument<String>("title"),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // Whether any app is playing audio right now. Asked while this app is
        // paused because another one took the output for good, so it can wait
        // for that app to finish and carry on, instead of staying silent.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tunes/audio")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "otherAudioActive" -> {
                        val audio = getSystemService(android.content.Context.AUDIO_SERVICE)
                            as android.media.AudioManager
                        result.success(audio.isMusicActive)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tunes/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPostNotifications" -> {
                        result.success(null)
                        if (android.os.Build.VERSION.SDK_INT >= 33) {
                            try {
                                if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                                    android.content.pm.PackageManager.PERMISSION_GRANTED
                                ) {
                                    androidx.core.app.ActivityCompat.requestPermissions(
                                        this,
                                        arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                                        4001,
                                    )
                                }
                            } catch (e: Exception) {
                                // never let a permission request take the app down
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // Hands a downloaded APK to the system installer.
        //
        // The app never installs anything itself and could not if it wanted
        // to: Android shows its own confirmation and the user taps Install.
        // All this does is open that dialog on a file the app has already
        // fetched from the daemon.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tunes/updates")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("no_path", "install needs a path", null)
                            return@setMethodCallHandler
                        }
                        try {
                            installApk(path)
                            result.success(null)
                        } catch (e: Exception) {
                            // Reported rather than swallowed: unlike the tile,
                            // somebody is waiting on this and has just agreed
                            // to a download. Silence would read as the button
                            // doing nothing.
                            result.error("install_failed", e.message, null)
                        }
                    }
                    "canInstall" -> {
                        result.success(
                            if (android.os.Build.VERSION.SDK_INT >= 26) {
                                packageManager.canRequestPackageInstalls()
                            } else {
                                true
                            },
                        )
                    }
                    // Opens the settings page where the permission is granted.
                    // Android 8+ makes this per-app and only grantable there;
                    // there is no runtime prompt for it.
                    "openInstallSettings" -> {
                        if (android.os.Build.VERSION.SDK_INT >= 26) {
                            startActivity(
                                android.content.Intent(
                                    android.provider.Settings
                                        .ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    android.net.Uri.parse("package:$packageName"),
                                ),
                            )
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun installApk(path: String) {
        val file = java.io.File(path)
        if (!file.exists()) throw java.io.FileNotFoundException(path)
        // A content:// URI, not file://. Since Android 7 handing a file:// URI
        // to another app throws FileUriExposedException, and the installer is
        // another app.
        val uri = androidx.core.content.FileProvider.getUriForFile(
            this,
            "$packageName.updates",
            file,
        )
        val intent = android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            // The installer runs in its own process and needs read access to a
            // URI belonging to this app's provider.
            addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}