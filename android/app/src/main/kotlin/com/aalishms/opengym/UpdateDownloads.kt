package com.aalishms.opengym

import android.app.DownloadManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import java.io.File

private const val PREFS_NAME = "update_download"
private const val KEY_ID = "downloadId"
private const val KEY_TAG = "tag"
private const val KEY_FILE = "fileName"
private const val KEY_LABEL = "label"
private const val KEY_BACKGROUND = "background"
private const val DIRECTORY = "updates"
private const val APK_MIME = "application/vnd.android.package-archive"
private const val CHANNEL_ID = "app_updates"
private const val NOTIFICATION_ID = 4110
private const val CONTENT_REQUEST = 4111

const val ACTION_OPEN_UPDATE = "com.aalishms.opengym.update.OPEN"

/**
 * The self-update download, run by Android's DownloadManager.
 *
 * The download belongs to the system, not to this process, so it keeps going
 * when the screen is off, when the user switches apps, and even if Android
 * kills OpenGym. Dart polls [status] for progress and hands the finished file
 * to [UpdateInstaller].
 *
 * A download is either one the user asked for, or a *background* one the app
 * starts by itself so the update is ready when the user is. Background
 * downloads only run on an unmetered network, show no system notification, and
 * never post "ready to install" — the user did not ask for anything yet.
 *
 * Only one update download exists at a time. Its id and release tag live in
 * SharedPreferences so a restarted process can find it again.
 */
object UpdateDownloads {
    /** Set by MainActivity so receivers know whether the app is on screen. */
    @Volatile
    var appInForeground = false

    fun start(
        context: Context,
        url: String,
        tag: String,
        fileName: String,
        title: String,
        label: String,
        background: Boolean,
    ) {
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
            // Hidden needs DOWNLOAD_WITHOUT_NOTIFICATION, declared in the manifest.
            .setNotificationVisibility(
                if (background) {
                    DownloadManager.Request.VISIBILITY_HIDDEN
                } else {
                    DownloadManager.Request.VISIBILITY_VISIBLE
                },
            )
            .setAllowedOverMetered(!background)
            .setAllowedOverRoaming(!background)
            .setDestinationInExternalFilesDir(context, DIRECTORY, fileName)
        val id = manager(context).enqueue(request)
        prefs(context).edit()
            .putLong(KEY_ID, id)
            .putString(KEY_TAG, tag)
            .putString(KEY_FILE, fileName)
            .putString(KEY_LABEL, label)
            .putBoolean(KEY_BACKGROUND, background)
            .apply()
    }

    /**
     * Marks the current download as the user's (false) or the app's own (true).
     * It only changes who is told when it finishes; the request is unchanged.
     */
    fun setBackground(context: Context, background: Boolean) {
        val prefs = prefs(context)
        if (prefs.getLong(KEY_ID, -1L) < 0) return
        prefs.edit().putBoolean(KEY_BACKGROUND, background).apply()
    }

    /** The release label ("Version 18") of the current download, if any. */
    fun label(context: Context): String? = prefs(context).getString(KEY_LABEL, null)

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
                "background" to prefs.getBoolean(KEY_BACKGROUND, false),
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

    /** Called by [UpdateDownloadReceiver] when any of our downloads ends. */
    fun onDownloadComplete(context: Context, downloadId: Long) {
        val prefs = prefs(context)
        if (downloadId < 0 || downloadId != prefs.getLong(KEY_ID, -1L)) return
        // In the foreground Dart is already polling and will open the installer.
        if (appInForeground) return
        // A download the app started on its own is offered on the next launch,
        // not announced: nobody asked for it yet.
        if (prefs.getBoolean(KEY_BACKGROUND, false)) return
        val ready = status(context)["state"] == "successful"
        notify(
            context,
            title = if (ready) "Update ready to install" else "Update download failed",
            text = if (ready) "Tap to finish updating OpenGym" else "Open OpenGym to try again",
            action = ACTION_OPEN_UPDATE,
        )
    }

    fun clearNotification(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    /**
     * Posts the one update notification, replacing any earlier one. [action] is
     * the intent action MainActivity opens with, or null for a plain launch.
     */
    fun notify(context: Context, title: String, text: String, action: String?) {
        if (!WorkoutTimerNotification.notificationsAllowed(context)) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "App updates", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Tells you when an update is ready or has been installed"
                    setShowBadge(false)
                },
            )
        }
        val openIntent = Intent(context, MainActivity::class.java).apply {
            this.action = action ?: Intent.ACTION_MAIN
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
            .setContentTitle(title)
            .setContentText(text)
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
    fun apkFile(context: Context): File? {
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
