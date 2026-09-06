package com.aalishms.opengym

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
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
    private val TIMER_NOTIFICATION_CHANNEL = "com.aalishms.opengym/workout_timer_notification"
    private val NOTIFICATION_PERMISSION_REQUEST = 4103

    private var highRefreshRateEnabled = true
    private var timerChannel: MethodChannel? = null
    private var pendingTimerIntentAction: String? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

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

        pendingTimerIntentAction = timerIntentAction(intent) ?: pendingTimerIntentAction
        timerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TIMER_NOTIFICATION_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> requestNotificationPermission(result)
                    "show" -> {
                        WorkoutTimerNotification.show(this, call.arguments as Map<*, *>)
                        result.success(null)
                    }
                    "pause" -> {
                        WorkoutTimerNotification.pauseFromDart(this, call.arguments as Map<*, *>)
                        result.success(null)
                    }
                    "dismiss" -> {
                        WorkoutTimerNotification.dismiss(this)
                        result.success(null)
                    }
                    "acknowledgeStop" -> {
                        WorkoutTimerNotification.acknowledgeStop(this)
                        result.success(null)
                    }
                    "snapshot" -> result.success(WorkoutTimerNotification.state(this)?.toMap())
                    "restore" -> {
                        WorkoutTimerNotification.restore(this)
                        result.success(null)
                    }
                    "consumeIntent" -> {
                        val action = pendingTimerIntentAction
                        pendingTimerIntentAction = null
                        result.success(action?.let { timerEvent(it) })
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = timerIntentAction(intent) ?: return
        pendingTimerIntentAction = action
        timerChannel?.invokeMethod("notificationIntent", timerEvent(action))
    }

    private fun timerIntentAction(intent: Intent?): String? = when (intent?.action) {
        ACTION_OPEN_TIMER -> "open"
        ACTION_STOP_TIMER -> "stop"
        else -> null
    }

    private fun timerEvent(action: String): Map<String, Any?>? {
        val snapshot = WorkoutTimerNotification.state(this)?.toMap() ?: return null
        return mapOf("action" to action, "snapshot" to snapshot)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("permission_in_progress", "Notification permission is already being requested.", null)
            return
        }
        pendingPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
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
