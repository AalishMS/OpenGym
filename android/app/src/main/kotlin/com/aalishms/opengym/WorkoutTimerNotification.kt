package com.aalishms.opengym

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat

private const val CHANNEL_ID = "workout_timer"
private const val NOTIFICATION_ID = 4102
private const val PREFS_NAME = "workout_timer_notification"
private const val ACTION_PAUSE = "com.aalishms.opengym.timer.PAUSE"
private const val ACTION_RESUME = "com.aalishms.opengym.timer.RESUME"
const val ACTION_OPEN_TIMER = "com.aalishms.opengym.timer.OPEN"
const val ACTION_STOP_TIMER = "com.aalishms.opengym.timer.STOP"

data class WorkoutTimerState(
    val sessionId: String,
    val planId: String?,
    val splitId: String?,
    val planName: String,
    val weekNumber: Int,
    val accumulatedSeconds: Int,
    val runningSinceMillis: Long?,
    val running: Boolean,
    val actionRevision: Long,
    val pendingStop: Boolean,
) {
    fun elapsedSeconds(nowMillis: Long = System.currentTimeMillis()): Int {
        if (!running || runningSinceMillis == null) return accumulatedSeconds
        val delta = ((nowMillis - runningSinceMillis) / 1000L).coerceAtLeast(0L)
        return (accumulatedSeconds.toLong() + delta).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "sessionId" to sessionId,
        "planId" to planId,
        "splitId" to splitId,
        "planName" to planName,
        "weekNumber" to weekNumber,
        "accumulatedSeconds" to accumulatedSeconds,
        "runningSinceMillis" to runningSinceMillis,
        "running" to running,
        "actionRevision" to actionRevision,
        "pendingStop" to pendingStop,
    )

    fun paused(nowMillis: Long, stopRequested: Boolean = false): WorkoutTimerState {
        if (!running && pendingStop == stopRequested) return this
        return copy(
            accumulatedSeconds = elapsedSeconds(nowMillis),
            runningSinceMillis = null,
            running = false,
            actionRevision = nowMillis,
            pendingStop = stopRequested,
        )
    }

    fun resumed(nowMillis: Long): WorkoutTimerState {
        if (running) return this
        return copy(
            runningSinceMillis = nowMillis,
            running = true,
            actionRevision = nowMillis,
            pendingStop = false,
        )
    }
}

object WorkoutTimerNotification {
    fun state(context: Context): WorkoutTimerState? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val sessionId = prefs.getString("sessionId", null) ?: return null
        return WorkoutTimerState(
            sessionId = sessionId,
            planId = prefs.getString("planId", null),
            splitId = prefs.getString("splitId", null),
            planName = prefs.getString("planName", "Workout") ?: "Workout",
            weekNumber = prefs.getInt("weekNumber", 1),
            accumulatedSeconds = prefs.getInt("accumulatedSeconds", 0),
            runningSinceMillis = if (prefs.contains("runningSinceMillis")) prefs.getLong("runningSinceMillis", 0L) else null,
            running = prefs.getBoolean("running", false),
            actionRevision = prefs.getLong("actionRevision", 0L),
            pendingStop = prefs.getBoolean("pendingStop", false),
        )
    }

    fun show(context: Context, arguments: Map<*, *>) {
        val now = System.currentTimeMillis()
        val state = WorkoutTimerState(
            sessionId = arguments["sessionId"] as String,
            planId = arguments["planId"] as String?,
            splitId = arguments["splitId"] as String?,
            planName = arguments["planName"] as String,
            weekNumber = (arguments["weekNumber"] as Number).toInt(),
            accumulatedSeconds = (arguments["accumulatedSeconds"] as Number).toInt(),
            runningSinceMillis = (arguments["runningSinceMillis"] as Number?)?.toLong(),
            running = arguments["running"] as Boolean,
            actionRevision = now,
            pendingStop = false,
        )
        save(context, state)
        post(context, state)
    }

    fun pauseFromDart(context: Context, arguments: Map<*, *>) = show(context, arguments)

    fun pause(context: Context, pendingStop: Boolean = false): WorkoutTimerState? {
        val current = state(context) ?: return null
        val paused = current.paused(System.currentTimeMillis(), pendingStop)
        save(context, paused)
        post(context, paused)
        return paused
    }

    fun resume(context: Context): WorkoutTimerState? {
        val current = state(context) ?: return null
        val resumed = current.resumed(System.currentTimeMillis())
        save(context, resumed)
        post(context, resumed)
        return resumed
    }

    fun acknowledgeStop(context: Context) {
        val current = state(context) ?: return
        if (!current.pendingStop) return
        val acknowledged = current.copy(pendingStop = false, actionRevision = System.currentTimeMillis())
        save(context, acknowledged)
        post(context, acknowledged)
    }

    fun restore(context: Context) {
        state(context)?.let { post(context, it) }
    }

    fun dismiss(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit().clear().apply()
    }

    fun notificationsAllowed(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun save(context: Context, state: WorkoutTimerState) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString("sessionId", state.sessionId)
            .putString("planId", state.planId)
            .putString("splitId", state.splitId)
            .putString("planName", state.planName)
            .putInt("weekNumber", state.weekNumber)
            .putInt("accumulatedSeconds", state.accumulatedSeconds)
            .putBoolean("running", state.running)
            .putLong("actionRevision", state.actionRevision)
            .putBoolean("pendingStop", state.pendingStop)
            .also { editor ->
                if (state.runningSinceMillis == null) editor.remove("runningSinceMillis")
                else editor.putLong("runningSinceMillis", state.runningSinceMillis)
            }
            .apply()
    }

    private fun post(context: Context, state: WorkoutTimerState) {
        if (!notificationsAllowed(context)) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Workout timer", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Shows the active workout timer and its controls"
                    setSound(null, null)
                    enableVibration(false)
                    enableLights(false)
                    setShowBadge(false)
                },
            )
        }

        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_TIMER
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val toggleIntent = Intent(context, WorkoutTimerActionReceiver::class.java).apply {
            action = if (state.running) ACTION_PAUSE else ACTION_RESUME
        }
        val stopIntent = Intent(context, WorkoutTimerActionReceiver::class.java).apply {
            action = ACTION_STOP_TIMER
        }
        val immutable = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(context)
        }
        builder
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle("${state.planName} · Week ${state.weekNumber}")
            .setContentText(if (state.running) "Workout in progress" else "${formatDuration(state.accumulatedSeconds)} · Workout paused")
            .setContentIntent(PendingIntent.getActivity(context, 4100, openIntent, immutable))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setAutoCancel(false)
            .setShowWhen(state.running)
            .setUsesChronometer(state.running)
            .setWhen(System.currentTimeMillis() - state.elapsedSeconds().toLong() * 1000L)
            .addAction(
                Notification.Action.Builder(
                    R.drawable.ic_launcher_monochrome,
                    if (state.running) "Pause" else "Resume",
                    PendingIntent.getBroadcast(context, 4101, toggleIntent, immutable),
                ).build(),
            )
            .addAction(
                Notification.Action.Builder(
                    R.drawable.ic_launcher_monochrome,
                    "Stop",
                    PendingIntent.getBroadcast(context, 4102, stopIntent, immutable),
                ).build(),
            )
        manager.notify(NOTIFICATION_ID, builder.build())
    }

    private fun formatDuration(seconds: Int): String {
        val hours = seconds / 3600
        val minutes = (seconds % 3600) / 60
        val remainder = seconds % 60
        return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, remainder)
        else "%02d:%02d".format(minutes, remainder)
    }
}

class WorkoutTimerActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_PAUSE -> WorkoutTimerNotification.pause(context)
            ACTION_RESUME -> WorkoutTimerNotification.resume(context)
            ACTION_STOP_TIMER -> {
                WorkoutTimerNotification.pause(context, pendingStop = true) ?: return
                context.startActivity(
                    Intent(context, MainActivity::class.java).apply {
                        action = ACTION_STOP_TIMER
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    },
                )
            }
        }
    }
}

class WorkoutTimerBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            WorkoutTimerNotification.restore(context)
        }
    }
}
