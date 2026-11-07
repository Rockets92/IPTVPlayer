package com.rockets92.iptv_player

import android.app.ActivityManager
import android.content.Context
import android.media.AudioManager
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
        // Volume del dispositivo comandato dal telecomando sul telefono. Sulle
        // chiavette TV con HDMI-CEC (es. Chromecast) il sistema inoltra il
        // comando al televisore, come il tasto volume del telecomando originale.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "iptv_player/volume")
            .setMethodCallHandler { call, result ->
                if (call.method != "adjust") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val direction = call.argument<Int>("direction") ?: 0
                val adjust = when {
                    direction > 0 -> AudioManager.ADJUST_RAISE
                    direction < 0 -> AudioManager.ADJUST_LOWER
                    else -> AudioManager.ADJUST_TOGGLE_MUTE
                }
                try {
                    am.adjustStreamVolume(AudioManager.STREAM_MUSIC, adjust, AudioManager.FLAG_SHOW_UI)
                    val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
                    val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                    result.success(
                        mapOf(
                            "level" to cur * 100 / max,
                            "muted" to am.isStreamMute(AudioManager.STREAM_MUSIC),
                            "fixed" to am.isVolumeFixed,
                        )
                    )
                } catch (e: Exception) {
                    result.error("volume", e.message, null)
                }
            }
    }
}
