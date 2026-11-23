package io.github.m15uk.deskpilot

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Keeps the screen on while DeskPilot is open, when its settings say so.
        // Android drops the flag by itself when the app goes to the background.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "deskpilot/screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepOn" -> {
                        val flag = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                        if (call.arguments == true) window.addFlags(flag) else window.clearFlags(flag)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
