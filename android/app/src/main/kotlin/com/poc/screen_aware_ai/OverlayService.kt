package com.poc.screen_aware_ai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.content.pm.ServiceInfo

class OverlayService : Service() {

    companion object {
        var instance: OverlayService? = null
        private const val TAG = "OverlayService"
        const val ACTION_FORCE_STOP = "com.poc.screen_aware_ai.FORCE_STOP"
        private const val ACTION_NOTIFICATION_STOP = "com.poc.screen_aware_ai.NOTIFICATION_STOP"
        private const val CHANNEL_ID = "lucy_stop_controls_v2"
        private const val NOTIFICATION_ID = 2
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_NOTIFICATION_STOP) {
            Log.d(TAG, "Stop notification action tapped — broadcasting FORCE_STOP")
            val stopIntent = Intent(ACTION_FORCE_STOP).apply {
                setPackage(packageName)
            }
            sendBroadcast(stopIntent)
            hideOverlay()
            stopSelf()
            return START_NOT_STICKY
        }

        showOverlay()
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun showOverlay() {
        val notification = createNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        Log.d(TAG, "Stop notification shown")
    }

    fun hideOverlay() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(NOTIFICATION_ID)
        Log.d(TAG, "Stop notification hidden")
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.stop_notification_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = getString(R.string.stop_notification_channel_description)
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun createNotification(): Notification {
        val stopIntent = Intent(this, OverlayService::class.java).apply {
            action = ACTION_NOTIFICATION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            0,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.stop_notification_title))
            .setContentText(getString(R.string.stop_notification_text))
            .setSmallIcon(android.R.drawable.ic_media_pause)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setTicker(getString(R.string.stop_notification_title))
            .addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_media_pause,
                    getString(R.string.stop_notification_action),
                    stopPendingIntent,
                ).build(),
            )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }

        return builder.build()
    }

    override fun onDestroy() {
        hideOverlay()
        instance = null
        super.onDestroy()
    }
}
