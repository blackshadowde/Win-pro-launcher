package com.vibe.vibe_ai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/** Keeps the built-in FreeLLMAPI server running in the background, with a notification. */
class ServerService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            ServerRuntime.stop()
            shutdown()
            return START_NOT_STICKY
        }
        startInForeground()
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "VibeAI:server").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
        ServerRuntime.onExit = { shutdown() }
        ServerRuntime.start(applicationContext)
        return START_STICKY
    }

    override fun onDestroy() {
        ServerRuntime.onExit = null
        ServerRuntime.stop()
        releaseWakeLock()
        super.onDestroy()
    }

    private fun shutdown() {
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        wakeLock = null
    }

    private fun startInForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "AI server", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while the built-in FreeLLMAPI server is running"
                setShowBadge(false)
            }
        )
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            flags,
        )
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, ServerService::class.java).setAction(ACTION_STOP),
            flags,
        )
        val notification = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_vibe)
            .setContentTitle("AI server running")
            .setContentText("FreeLLMAPI is ready for Vibe AI")
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(@Suppress("DEPRECATION") Notification.Action.Builder(0, "Stop", stop).build())
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        const val ACTION_STOP = "com.vibe.vibe_ai.STOP_SERVER"
        private const val CHANNEL = "server"
        private const val NOTIFICATION_ID = 7
    }
}
