package io.github.m15uk.deskpilot

import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // The click plays at media volume, so it works even when the tablet's touch sounds are off.
    private val sounds = SoundPool.Builder()
        .setMaxStreams(4)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        )
        .build()
    private var click = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        click = sounds.load(this, R.raw.click, 1)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Keeps the screen on while DeskPilot is open, when its settings say so.
        // Android drops the flag by itself when the app goes to the background.
        MethodChannel(messenger, "deskpilot/screen").setMethodCallHandler { call, result ->
            when (call.method) {
                "keepOn" -> {
                    val flag = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                    if (call.arguments == true) window.addFlags(flag) else window.clearFlags(flag)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Press feedback that doesn't depend on Android's touch sound and touch vibration settings.
        MethodChannel(messenger, "deskpilot/feedback").setMethodCallHandler { call, result ->
            when (call.method) {
                "click" -> {
                    sounds.play(click, 1f, 1f, 1, 0, 1f)
                    result.success(null)
                }
                "vibrate" -> {
                    vibrate()
                    result.success(null)
                }
                "canVibrate" -> result.success(vibrator()?.hasVibrator() == true)
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        sounds.release()
        super.onDestroy()
    }

    private fun vibrator(): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Vibrator::class.java)
        }

    private fun vibrate() {
        val vibrator = vibrator() ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(25, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(25)
        }
    }
}
