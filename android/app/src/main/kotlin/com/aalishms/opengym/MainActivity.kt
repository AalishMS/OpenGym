package com.aalishms.opengym

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

class MainActivity: FlutterActivity() {
    // Backs the in-app updater's pre-flight check. "Install unknown apps" is not
    // a runtime permission — it is a per-app settings toggle — so there is
    // nothing to request, only something to read and a screen to open.
    private val INSTALLER_CHANNEL = "com.aalishms.opengym/installer"
    private val TIMER_NOTIFICATION_CHANNEL = "com.aalishms.opengym/workout_timer_notification"
    private val NOTIFICATION_PERMISSION_REQUEST = 4103

    private var timerChannel: MethodChannel? = null
    private var pendingTimerIntentAction: String? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    private var installerChannel: MethodChannel? = null
    private var installListener: ((Map<String, Any?>) -> Unit)? = null

    // Set when the app was opened from the "Update ready to install"
    // notification, until Dart asks for it at startup.
    private var pendingOpenUpdate = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val installer = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALLER_CHANNEL)
        installerChannel = installer
        UpdateInstaller.activity = WeakReference(this)
        val listener: (Map<String, Any?>) -> Unit = { outcome ->
            // Before Dart registers its handler, or if it fails, keep the
            // result for takeInstallResult instead of losing it.
            installer.invokeMethod("installResult", outcome, object : MethodChannel.Result {
                override fun success(result: Any?) {}
                override fun error(code: String, message: String?, details: Any?) {
                    UpdateInstaller.hold(outcome)
                }
                override fun notImplemented() {
                    UpdateInstaller.hold(outcome)
                }
            })
        }
        installListener = listener
        UpdateInstaller.listener = listener
        if (intent?.action == ACTION_OPEN_UPDATE) {
            pendingOpenUpdate = true
            // Consumed: a recreated activity must not reopen the prompt.
            setIntent(Intent(intent).setAction(Intent.ACTION_MAIN))
        }
        installer.setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> {
                    result.success(canRequestPackageInstalls())
                }
                "openInstallPermissionSettings" -> {
                    result.success(openInstallPermissionSettings())
                }
                "startDownload" -> {
                    try {
                        UpdateDownloads.start(
                            this,
                            url = call.argument<String>("url")!!,
                            tag = call.argument<String>("tag")!!,
                            fileName = call.argument<String>("fileName")!!,
                            title = call.argument<String>("title") ?: "OpenGym update",
                            label = call.argument<String>("label") ?: "the latest version",
                            background = call.argument<Boolean>("background") ?: false,
                        )
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("download_failed", e.message, null)
                    }
                }
                "downloadStatus" -> {
                    try {
                        result.success(UpdateDownloads.status(this))
                    } catch (e: Exception) {
                        result.error("status_failed", e.message, null)
                    }
                }
                "cancelDownload" -> {
                    UpdateDownloads.cancel(this)
                    result.success(null)
                }
                "setDownloadBackground" -> {
                    UpdateDownloads.setBackground(this, call.argument<Boolean>("background") ?: false)
                    result.success(null)
                }
                "installDownload" -> {
                    result.success(UpdateInstaller.install(this, call.argument<String>("sha256")))
                }
                "takeInstallResult" -> {
                    result.success(UpdateInstaller.pendingResult)
                    UpdateInstaller.pendingResult = null
                }
                "canUpdateSilently" -> {
                    result.success(UpdateInstaller.canUpdateSilently(this))
                }
                "takeOpenUpdateRequest" -> {
                    result.success(pendingOpenUpdate)
                    pendingOpenUpdate = false
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        pendingTimerIntentAction = prepareTimerIntent(intent) ?: pendingTimerIntentAction
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

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // A newer activity may already have installed its own listener.
        if (UpdateInstaller.listener === installListener) UpdateInstaller.listener = null
        installListener = null
        installerChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == ACTION_OPEN_UPDATE) {
            installerChannel?.invokeMethod("openUpdate", null)
            return
        }
        setIntent(intent)
        val action = prepareTimerIntent(intent) ?: return
        pendingTimerIntentAction = action
        timerChannel?.invokeMethod("notificationIntent", timerEvent(action))
    }

    private fun timerIntentAction(intent: Intent?): String? = when (intent?.action) {
        ACTION_OPEN_TIMER -> "open"
        ACTION_STOP_TIMER -> "stop"
        else -> null
    }

    private fun prepareTimerIntent(intent: Intent?): String? {
        val action = timerIntentAction(intent) ?: return null
        if (action == "stop") {
            // Freeze the native clock before handing control to Flutter so the
            // confirmation always shows the exact time of the button press.
            WorkoutTimerNotification.pause(this, pendingStop = true)
        }
        return action
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
    
    @Suppress("DEPRECATION")
    private fun requestHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            windowManager.defaultDisplay
        } ?: return
        val highestRate = currentDisplay.supportedModes.maxOfOrNull { it.refreshRate } ?: return
        val params = window.attributes
        // Request refresh rate alone so Android can retain the user's resolution.
        // System display settings and power-saving policies still take precedence.
        params.preferredRefreshRate = highestRate
        window.attributes = params
    }
    
    override fun onResume() {
        super.onResume()
        UpdateDownloads.appInForeground = true
        UpdateInstaller.activity = WeakReference(this)
        // The app is in front, so the update dialog takes over from the
        // "ready to install" notification.
        UpdateDownloads.clearNotification(this)
        requestHighestRefreshRate()
    }

    override fun onPause() {
        UpdateDownloads.appInForeground = false
        super.onPause()
    }
}
