package com.currentsuspect.tunes

import android.os.Bundle
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val probe = object : Runnable {
            var n = 0
            val delays = longArrayOf(1000, 3000, 6000, 10000, 20000, 30000)
            override fun run() {
                val v = android.provider.Settings.System.getInt(
                    contentResolver,
                    android.provider.Settings.System.ACCELEROMETER_ROTATION,
                    -1
                )
                android.util.Log.i("tunes-orient", "t=${delays.getOrElse(n.coerceAtMost(delays.size - 1)) { 0 }}ms rot=$v")
                n += 1
                if (n < delays.size) {
                    window.decorView.postDelayed(this, delays[n] - delays[n - 1])
                }
            }
        }
        window.decorView.postDelayed(probe, 1000)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
    }
}