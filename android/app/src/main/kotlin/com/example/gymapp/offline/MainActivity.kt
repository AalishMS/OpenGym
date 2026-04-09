package com.example.gymapp.offline

import android.os.Build
import android.view.Display
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.gymapp/refresh_rate"
    private var highRefreshRateEnabled = true

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setHighRefreshRate" -> {
                    highRefreshRateEnabled = call.arguments as Boolean
                    if (highRefreshRateEnabled) {
                        enableHighRefreshRate()
                    }
                    result.success(true)
                }
                "getHighRefreshRate" -> {
                    result.success(highRefreshRateEnabled)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun enableHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val display = display
            display?.let {
                val modes = it.supportedModes
                val highestMode = modes.maxByOrNull { mode -> mode.refreshRate }
                highestMode?.let { mode ->
                    val params = window.attributes
                    params.preferredDisplayModeId = mode.modeId
                    window.attributes = params
                }
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val display = windowManager.defaultDisplay
            val modes = display.supportedModes
            val highestMode = modes.maxByOrNull { mode -> mode.refreshRate }
            highestMode?.let { mode ->
                val params = window.attributes
                params.preferredDisplayModeId = mode.modeId
                window.attributes = params
            }
        }
    }
    
    override fun onResume() {
        super.onResume()
        if (highRefreshRateEnabled) {
            enableHighRefreshRate()
        }
    }
}
