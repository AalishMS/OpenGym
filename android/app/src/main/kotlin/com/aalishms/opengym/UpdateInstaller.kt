package com.aalishms.opengym

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.lang.ref.WeakReference
import java.security.MessageDigest
import java.util.concurrent.Executors

private const val TAG = "UpdateInstaller"
private const val ACTION_INSTALL_STATUS = "com.aalishms.opengym.update.INSTALL_STATUS"
private const val PREFS_NAME = "update_install"
private const val KEY_LABEL = "label"
private const val KEY_MARKED_AT = "markedAt"
private const val EXTRA_SESSION_ID = "com.aalishms.opengym.update.SESSION_ID"

/** An install older than this cannot be the one that just replaced the app. */
private const val INSTALL_WINDOW_MS = 30 * 60 * 1000L

/** Hidden PackageInstaller extra carrying PackageManager's INSTALL_FAILED code. */
private const val EXTRA_LEGACY_STATUS = "android.content.pm.extra.LEGACY_STATUS"

/**
 * Installs the downloaded update through a PackageInstaller session.
 *
 * Two things make this smoother than handing the APK to the system installer:
 *
 * - On Android 12+, an app that is the installer of record for itself can
 *   update without a confirmation screen (USER_ACTION_NOT_REQUIRED plus the
 *   UPDATE_PACKAGES_WITHOUT_USER_ACTION permission). The first update after a
 *   browser install still asks; from then on OpenGym installed itself, so
 *   later updates go straight through. When Android does want confirmation —
 *   older versions, or a rule we do not meet — it answers
 *   STATUS_PENDING_USER_ACTION and the confirm screen is shown as before.
 * - The APK is hashed while it is copied into the session, so a damaged
 *   download is caught here with a clear message, before Android's own
 *   "problem parsing the package".
 *
 * Results come back through [UpdateInstallReceiver] and are pushed to Dart via
 * [listener]; a successful self-update kills this process, so "installed" is
 * rarely seen and [UpdateAppliedReceiver] reports it after the fact.
 */
object UpdateInstaller {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** Delivers results to Dart while a Flutter engine is attached. */
    @Volatile
    var listener: ((Map<String, Any?>) -> Unit)? = null

    /** A result that arrived while nothing was listening. */
    @Volatile
    var pendingResult: Map<String, Any?>? = null

    /** The activity that may show Android's confirm screen. */
    @Volatile
    var activity: WeakReference<Activity>? = null

    /**
     * The session this process committed. Statuses for any other session are
     * ignored: abandoning an earlier session can still report ABORTED for it.
     */
    @Volatile
    private var currentSessionId = -1

    /**
     * Whether Android is likely to install the next update without asking.
     * A best guess for the UI copy only: Android has the final say.
     */
    fun canUpdateSilently(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        return try {
            context.packageManager.getInstallSourceInfo(context.packageName)
                .installingPackageName == context.packageName
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Starts installing the finished download. Returns false when there is no
     * file to install; otherwise the answer arrives later through [listener].
     */
    fun install(context: Context, expectedSha256: String?): Boolean {
        val file = UpdateDownloads.apkFile(context) ?: return false
        val app = context.applicationContext
        val label = UpdateDownloads.label(context)
        pendingResult = null
        executor.execute {
            val early = try {
                writeAndCommit(app, file, expectedSha256, label)
            } catch (e: Exception) {
                Log.w(TAG, "Could not stage the update", e)
                clearInstalling(app)
                result("failed")
            }
            if (early != null) deliver(early)
        }
        return true
    }

    /** Returns a result to deliver now, or null once the session is committed. */
    private fun writeAndCommit(
        context: Context,
        file: File,
        expectedSha256: String?,
        label: String?,
    ): Map<String, Any?>? {
        val installer = context.packageManager.packageInstaller
        // A session from an earlier attempt (the confirm screen left open, the
        // process killed mid-copy) would otherwise linger until reboot.
        for (old in installer.mySessions) {
            try {
                installer.abandonSession(old.sessionId)
            } catch (_: Exception) {
            }
        }

        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(context.packageName)
            setSize(file.length())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                setInstallReason(PackageManager.INSTALL_REASON_USER)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                setPackageSource(PackageInstaller.PACKAGE_SOURCE_DOWNLOADED_FILE)
            }
        }

        val sessionId = installer.createSession(params)
        currentSessionId = sessionId
        val session = installer.openSession(sessionId)
        var committed = false
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            FileInputStream(file).use { input ->
                session.openWrite("base.apk", 0, file.length()).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        digest.update(buffer, 0, read)
                        output.write(buffer, 0, read)
                    }
                    session.fsync(output)
                }
            }
            val actual = digest.digest().joinToString("") { "%02x".format(it) }
            if (!expectedSha256.isNullOrBlank() && !expectedSha256.equals(actual, ignoreCase = true)) {
                Log.w(TAG, "Update checksum mismatch: expected $expectedSha256, got $actual")
                return result("corrupt")
            }

            markInstalling(context, label)
            val intent = Intent(context, UpdateInstallReceiver::class.java)
                .setAction(ACTION_INSTALL_STATUS)
                .putExtra(EXTRA_SESSION_ID, sessionId)
            // Mutable so the installer can attach its status; the intent is
            // explicit, which Android 14 requires of a mutable PendingIntent.
            // One request code per session, so an older session's
            // PendingIntent keeps its own id rather than taking this one's.
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            val pending = PendingIntent.getBroadcast(context, sessionId, intent, flags)
            session.commit(pending.intentSender)
            committed = true
            return null
        } finally {
            if (!committed) {
                try {
                    session.abandon()
                } catch (_: Exception) {
                }
            }
            session.close()
        }
    }

    /** Called by [UpdateInstallReceiver] with the session's answer. */
    fun onStatus(context: Context, intent: Intent) {
        val sessionId = intent.getIntExtra(EXTRA_SESSION_ID, -1)
        if (sessionId != currentSessionId) {
            Log.i(TAG, "Ignoring status for stale session $sessionId")
            return
        }
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                val host = activity?.get()
                if (confirm != null && host != null && UpdateDownloads.appInForeground) {
                    try {
                        host.startActivity(confirm)
                        // Tells Dart the confirm screen is up, so leaving the
                        // app now means "answering it", and no timeout applies.
                        deliver(result("confirming"))
                        return
                    } catch (e: Exception) {
                        Log.w(TAG, "Could not show the install confirmation", e)
                    }
                }
                // Left the app while the file was being staged. Hand the button
                // back rather than launching a screen over whatever is in front.
                clearInstalling(context)
                deliver(result("canceled"))
            }
            PackageInstaller.STATUS_SUCCESS -> deliver(result("installed"))
            PackageInstaller.STATUS_FAILURE_ABORTED -> {
                clearInstalling(context)
                deliver(result("canceled"))
            }
            else -> {
                clearInstalling(context)
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                Log.w(TAG, "Install failed: status=$status message=$message")
                deliver(result("failed", failureCode(intent, status)))
            }
        }
    }

    /**
     * Takes the label of a recently committed update, so it is announced once.
     * A stale mark (the confirm screen was never answered and the process
     * died) is dropped rather than credited to some later reinstall.
     */
    fun takeInstallingLabel(context: Context): String? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val label = prefs.getString(KEY_LABEL, null)
        val markedAt = prefs.getLong(KEY_MARKED_AT, 0L)
        prefs.edit().clear().apply()
        val age = System.currentTimeMillis() - markedAt
        return if (label != null && age in 0..INSTALL_WINDOW_MS) label else null
    }

    /**
     * PackageManager's INSTALL_FAILED code, which Dart already explains.
     * Falls back to the closest code for the public status.
     */
    private fun failureCode(intent: Intent, status: Int): Int {
        val legacy = intent.getIntExtra(EXTRA_LEGACY_STATUS, 0)
        if (legacy != 0) return legacy
        return when (status) {
            PackageInstaller.STATUS_FAILURE_CONFLICT -> -7 // UPDATE_INCOMPATIBLE
            PackageInstaller.STATUS_FAILURE_STORAGE -> -4 // INSUFFICIENT_STORAGE
            else -> 0
        }
    }

    private fun markInstalling(context: Context, label: String?) {
        // commit(), not apply(): a successful install kills this process, and
        // UpdateAppliedReceiver needs the label in the next one.
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(KEY_LABEL, label ?: "the latest version")
            .putLong(KEY_MARKED_AT, System.currentTimeMillis())
            .commit()
    }

    private fun clearInstalling(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .clear()
            .apply()
    }

    private fun result(outcome: String, code: Int = 0): Map<String, Any?> =
        mapOf("outcome" to outcome, "code" to code)

    private fun deliver(result: Map<String, Any?>) {
        main.post {
            val target = listener
            if (target != null) target(result) else hold(result)
        }
    }

    /**
     * Keeps a result for Dart to collect on resume. "confirming" is progress,
     * not an answer, so it never displaces a real one.
     */
    fun hold(result: Map<String, Any?>) {
        if (result["outcome"] == "confirming" && pendingResult != null) return
        pendingResult = result
    }
}

/** Receives the install session's status. Not exported: only our PendingIntent targets it. */
class UpdateInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        UpdateInstaller.onStatus(context, intent)
    }
}

/**
 * Runs in the new version right after an update OpenGym installed itself. A
 * self-update ends the old process without reopening the app, so this posts
 * "OpenGym updated — tap to open" and frees the downloaded APK.
 */
class UpdateAppliedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        // Only announce updates this app installed, not a manual reinstall.
        val label = UpdateInstaller.takeInstallingLabel(context) ?: return
        UpdateDownloads.cancel(context)
        UpdateDownloads.notify(
            context,
            title = "OpenGym updated",
            text = "$label is installed. Tap to open.",
            action = null,
        )
    }
}
