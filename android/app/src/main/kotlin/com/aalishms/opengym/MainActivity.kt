package com.aalishms.opengym

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.Display
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.aalishms.opengym/refresh_rate"

    // Backs the in-app updater's pre-flight check. "Install unknown apps" is not
    // a runtime permission — it is a per-app settings toggle — so there is
    // nothing to request, only something to read and a screen to open.
    private val INSTALLER_CHANNEL = "com.aalishms.opengym/installer"

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALLER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> {
                    result.success(canRequestPackageInstalls())
                }
                "openInstallPermissionSettings" -> {
                    result.success(openInstallPermissionSettings())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    /**
     * Whether the user has allowed this app to install APKs. Before Android 8
     * the manifest permission was sufficient and no toggle exists.
     */
    private fun canRequestPackageInstalls(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    /**
     * Opens this app's "Install unknown apps" screen. Returns false if the
     * screen could not be opened, so Dart can say something useful instead of
     * leaving the user waiting for a settings page that never appeared.
     */
    private fun openInstallPermissionSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
            )
            true
        } catch (e: Exception) {
            false
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
