package com.mkdjj.whisnya.qq

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
import com.mkdjj.whisnya.MainActivity
import com.mkdjj.whisnya.R

class QqBridgeForegroundService : Service() {
    override fun onCreate() {
        super.onCreate()
        QqFlutterEngineHolder.getOrCreate()
        createChannel()
        running = true
        showNotification()
        QqBridgeChannels.emit("foregroundService", mapOf("running" to true))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_EXPLICIT -> Unit
            ACTION_PAUSE -> QqBridgeChannels.runtimeControl("pause")
            ACTION_CONTINUE -> QqBridgeChannels.runtimeControl("continue")
            ACTION_STOP -> {
                QqBridgeChannels.runtimeControl("stop")
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            ACTION_REFRESH -> showNotification()
            else -> QqBridgeChannels.runtimeControl("start")
        }
        showNotification()
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        QqBridgeChannels.emit("foregroundService", mapOf("running" to false))
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "QQ 自动回复", NotificationManager.IMPORTANCE_LOW),
        )
    }

    private fun showNotification() {
        val mode = when (QqNativeConfiguration.mode) {
            "oneBot" -> "NapCat / OneBot"
            "notification" -> "通知监听"
            else -> "未启用"
        }
        val text = buildString {
            append(mode)
            append(" · 联系人 ")
            append(QqNativeConfiguration.enabledContacts)
            if (QqNativeConfiguration.lastError.isNotBlank()) {
                append(" · ")
                append(QqNativeConfiguration.lastError.take(40))
            }
        }
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("QQ 自动回复")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(activityIntent())
            .addAction(action("暂停", ACTION_PAUSE, 1))
            .addAction(action("继续", ACTION_CONTINUE, 2))
            .addAction(action("停止", ACTION_STOP, 3))
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun activityIntent(): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun action(title: String, action: String, requestCode: Int): Notification.Action {
        val intent = Intent(this, QqBridgeForegroundService::class.java).setAction(action)
        val pending = PendingIntent.getService(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Action.Builder(null, title, pending).build()
    }

    companion object {
        private const val CHANNEL_ID = "whisnya_qq_bridge"
        private const val NOTIFICATION_ID = 14301
        private const val ACTION_PAUSE = "com.mkdjj.whisnya.qq.PAUSE"
        private const val ACTION_CONTINUE = "com.mkdjj.whisnya.qq.CONTINUE"
        private const val ACTION_STOP = "com.mkdjj.whisnya.qq.STOP"
        private const val ACTION_REFRESH = "com.mkdjj.whisnya.qq.REFRESH"
        private const val ACTION_START_EXPLICIT = "com.mkdjj.whisnya.qq.START_EXPLICIT"

        @Volatile var running: Boolean = false
            private set

        fun start(context: Context) {
            val intent = Intent(context, QqBridgeForegroundService::class.java)
                .setAction(ACTION_START_EXPLICIT)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, QqBridgeForegroundService::class.java))
        }

        fun refresh(context: Context) {
            if (running) {
                context.startService(
                    Intent(context, QqBridgeForegroundService::class.java).setAction(ACTION_REFRESH),
                )
            }
        }
    }
}
