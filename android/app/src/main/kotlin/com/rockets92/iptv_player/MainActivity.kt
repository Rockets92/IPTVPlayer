package com.rockets92.iptv_player

import android.app.ActivityManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Informazioni sulla RAM per scegliere automaticamente il profilo "light".
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "iptv_player/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "memoryInfo") {
                    val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    val info = ActivityManager.MemoryInfo()
                    am.getMemoryInfo(info)
                    result.success(
                        mapOf(
                            "totalMem" to info.totalMem,
                            "isLowRamDevice" to am.isLowRamDevice,
                            "memoryClass" to am.memoryClass,
                        )
                    )
                } else {
                    result.notImplemented()
                }
            }
    }
}
