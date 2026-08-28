package com.currentsuspect.tunes

import android.content.pm.ActivityInfo
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
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
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