package com.aalishms.opengym

import android.app.Activity
import android.app.DownloadManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import java.io.File

private const val PREFS_NAME = "update_download"
private const val KEY_ID = "downloadId"
private const val KEY_TAG = "tag"
private const val KEY_FILE = "fileName"
private const val DIRECTORY = "updates"
private const val APK_MIME = "application/vnd.android.package-archive"
private const val CHANNEL_ID = "app_updates"
private const val NOTIFICATION_ID = 4110
private const val CONTENT_REQUEST = 4111

/** Hidden PackageManager extra the installer fills in when EXTRA_RETURN_RESULT is set. */
private const val EXTRA_INSTALL_RESULT = "android.intent.extra.INSTALL_RESULT"

const val ACTION_OPEN_UPDATE = "com.aalishms.opengym.update.OPEN"
const val INSTALL_REQUEST_CODE = 4112

/**
 * The self-update download, run by Android's DownloadManager.
 *
 * The download belongs to the system, not to this process, so it keeps going
 * when the screen is off, when the user switches apps, and even if Android
 * kills OpenGym. Dart polls [status] for progress and asks for [install] once
 * the app is back in front — Android blocks a background app from opening the
 * installer, so the install step always waits for the user.
 *
 * Only one update download exists at a time. Its id and release tag live in
 * SharedPreferences so a restarted process can find it again.
 */
object UpdateDownloads {
    /** Set by MainActivity so the completion receiver knows whether to notify. */
    @Volatile
    var appInForeground = false

    fun start(context: Context, url: String, tag: String, fileName: String, title: String) {
        require(fileName.isNotBlank() && !fileName.contains('/')) { "Invalid file name" }
        cancel(context)
        val dir = context.getExternalFilesDir(DIRECTORY)
            ?: throw IllegalStateException("App storage is unavailable")
        // DownloadManager renames rather than overwrites, so clear any leftover.
        File(dir, fileName).delete()

        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle(title)
            .setDescription("Downloading update")
            .setMimeType(APK_MIME)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(true)
            .setDestinationInExternalFilesDir(context, DIRECTORY, fileName)
        val id = manager(context).enqueue(request)
        prefs(context).edit()
            .putLong(KEY_ID, id)
            .putString(KEY_TAG, tag)
            .putString(KEY_FILE, fileName)
            .apply()
    }

    /**
     * The current download as a map for Dart. `state` is one of none, pending,
     * running, paused, successful, failed. `reason` is DownloadManager's
     * COLUMN_REASON: a pause reason, an error code, or an HTTP status.
     */
    fun status(context: Context): Map<String, Any?> {
        val prefs = prefs(context)
        val id = prefs.getLong(KEY_ID, -1L)
        val tag = prefs.getString(KEY_TAG, null)
        if (id < 0 || tag == null) return mapOf("state" to "none")

        manager(context).query(DownloadManager.Query().setFilterById(id))?.use { cursor ->
            if (!cursor.moveToFirst()) {
                // Removed from the system's download list behind our back.
                clear(context)
                return mapOf("state" to "none")
            }
            val state = when (cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                DownloadManager.STATUS_PENDING -> "pending"
                DownloadManager.STATUS_RUNNING -> "running"
                DownloadManager.STATUS_PAUSED -> "paused"
                DownloadManager.STATUS_SUCCESSFUL ->
                    if (apkFile(context) != null) "successful" else "none"
                else -> "failed"
            }
            if (state == "none") {
                cancel(context)
                return mapOf("state" to "none")
            }
            return mapOf(
                "state" to state,
                "tag" to tag,
                "downloaded" to cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)),
                "total" to cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)),
                "reason" to cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)),
            )
        }
        return mapOf("state" to "none")
    }

    /** Stops the download if it is running and deletes the APK either way. */
    fun cancel(context: Context) {
        val id = prefs(context).getLong(KEY_ID, -1L)
        if (id >= 0) {
            try {
                manager(context).remove(id)
            } catch (_: Exception) {
                // Already gone; the prefs are what matter.
            }
        }
        apkFile(context)?.delete()
        clear(context)
        clearNotification(context)
    }

    /**
     * Opens the system installer for the finished download. Returns false when
     * there is nothing to install or no installer would take it. The answer
     * arrives in MainActivity.onActivityResult under [INSTALL_REQUEST_CODE].
     */
    fun install(activity: Activity): Boolean {
        val file = apkFile(activity) ?: return false
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.update_provider", file)
        @Suppress("DEPRECATION")
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(uri, APK_MIME)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra(Intent.EXTRA_RETURN_RESULT, true)
        }
        return try {
            activity.startActivityForResult(intent, INSTALL_REQUEST_CODE)
            clearNotification(activity)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    /**
     * Turns the installer's answer into a map for Dart. A successful self-update
     * replaces this process, so "installed" is rarely seen; "canceled" covers
     * the user backing out, and "failed" carries PackageManager's INSTALL_FAILED
     * code (for example -7 when the signing key does not match).
     */
    fun installResult(resultCode: Int, data: Intent?): Map<String, Any?> = mapOf(
        "outcome" to when (resultCode) {
            Activity.RESULT_OK -> "installed"
            Activity.RESULT_CANCELED -> "canceled"
            else -> "failed"
        },
        "code" to (data?.getIntExtra(EXTRA_INSTALL_RESULT, 0) ?: 0),
    )

    /** Called by [UpdateDownloadReceiver] when any of our downloads ends. */
    fun onDownloadComplete(context: Context, downloadId: Long) {
        val prefs = prefs(context)
        if (downloadId < 0 || downloadId != prefs.getLong(KEY_ID, -1L)) return
        // In the foreground Dart is already polling and will open the installer.
        if (appInForeground) return
        val ready = status(context)["state"] == "successful"
        notify(context, ready)
    }

    fun clearNotification(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    private fun notify(context: Context, ready: Boolean) {
        if (!WorkoutTimerNotification.notificationsAllowed(context)) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "App updates", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Tells you when a downloaded update is ready to install"
                    setShowBadge(false)
                },
            )
        }
        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_UPDATE
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(context)
        }
        builder
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(if (ready) "Update ready to install" else "Update download failed")
            .setContentText(if (ready) "Tap to finish updating OpenGym" else "Open OpenGym to try again")
            .setContentIntent(
                PendingIntent.getActivity(
                    context,
                    CONTENT_REQUEST,
                    openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            .setAutoCancel(true)
        manager.notify(NOTIFICATION_ID, builder.build())
    }

    /** The finished APK, preferring the path DownloadManager reports. */
    private fun apkFile(context: Context): File? {
        val prefs = prefs(context)
        val id = prefs.getLong(KEY_ID, -1L)
        if (id >= 0) {
            try {
                manager(context).query(DownloadManager.Query().setFilterById(id))?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val local = cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
                        val path = local?.let { Uri.parse(it).path }
                        if (path != null) {
                            val file = File(path)
                            if (file.isFile && file.length() > 0) return file
                        }
                    }
                }
            } catch (_: Exception) {
                // Fall through to the expected location.
            }
        }
        val name = prefs.getString(KEY_FILE, null) ?: return null
        val file = File(context.getExternalFilesDir(DIRECTORY) ?: return null, name)
        return if (file.isFile && file.length() > 0) file else null
    }

    private fun clear(context: Context) {
        prefs(context).edit().clear().apply()
    }

    private fun manager(context: Context): DownloadManager =
        context.getSystemService(DownloadManager::class.java)

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}

/**
 * Hears DownloadManager finish. DownloadManager addresses this broadcast to our
 * package only, but it is exported (the sender is the system download
 * provider), so the id is checked against the stored one and the real status
 * is read back from DownloadManager rather than trusted from the intent.
 */
class UpdateDownloadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
        val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
        UpdateDownloads.onDownloadComplete(context, id)
    }
}
