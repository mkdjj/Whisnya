package com.mkdjj.whisnya.qq

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.service.notification.StatusBarNotification
import android.os.Build
import com.mkdjj.whisnya.R
import java.util.ArrayDeque
import java.util.LinkedHashMap

data class QqPendingNotificationContext(
    val statusBarNotification: StatusBarNotification,
    val parsed: ParsedQqNotification,
    val expiresAt: Long,
)

data class PendingAccessibilityReply(
    val id: String,
    val notificationKey: String,
    val messageId: String,
    val contactKey: String,
    val expectedTitles: List<String>,
    val text: String,
    val createdAt: Long,
    val expiresAt: Long,
    val returnAfterSend: Boolean,
    var clicked: Boolean = false,
)

object QqNotificationVersionGuard {
    fun isCurrent(storedMessageId: String?, callbackMessageId: String): Boolean =
        storedMessageId != null && storedMessageId == callbackMessageId
}

object QqPendingReplyStore {
    private const val NOTIFICATION_TTL = 3 * 60 * 1000L
    private const val ACCESSIBILITY_TTL = 30 * 1000L
    private val notifications = LinkedHashMap<String, QqPendingNotificationContext>()
    private val accessibility = ArrayDeque<PendingAccessibilityReply>()

    @Synchronized
    fun put(status: StatusBarNotification, parsed: ParsedQqNotification) {
        prune()
        notifications[parsed.notificationKey] = QqPendingNotificationContext(
            status,
            parsed,
            System.currentTimeMillis() + NOTIFICATION_TTL,
        )
        while (notifications.size > 20) notifications.remove(notifications.keys.first())
    }

    @Synchronized
    fun notification(key: String, messageId: String): QqPendingNotificationContext? {
        prune()
        return notifications[key]?.takeIf {
            QqNotificationVersionGuard.isCurrent(it.parsed.messageId, messageId)
        }
    }

    @Synchronized
    fun removeNotification(key: String, messageId: String) {
        if (QqNotificationVersionGuard.isCurrent(
                notifications[key]?.parsed?.messageId,
                messageId,
            )
        ) {
            notifications.remove(key)
        }
    }

    @Synchronized
    fun enqueueAccessibility(
        notificationKey: String,
        messageId: String,
        contactKey: String,
        expectedTitles: List<String>,
        text: String,
        returnAfterSend: Boolean,
    ): PendingAccessibilityReply? {
        prune()
        if (accessibility.size >= 5) return null
        val now = System.currentTimeMillis()
        return PendingAccessibilityReply(
            id = "$now-${accessibility.size}",
            notificationKey = notificationKey,
            messageId = messageId,
            contactKey = contactKey,
            expectedTitles = expectedTitles
                .map(QqNotificationParser::normalizeTitle)
                .filter(String::isNotBlank)
                .distinct(),
            text = text,
            createdAt = now,
            expiresAt = now + ACCESSIBILITY_TTL,
            returnAfterSend = returnAfterSend,
        ).also(accessibility::addLast)
    }

    @Synchronized
    fun currentAccessibility(): PendingAccessibilityReply? {
        prune()
        return accessibility.firstOrNull()
    }

    @Synchronized
    fun finishAccessibility(id: String): PendingAccessibilityReply? {
        val notificationKey = accessibility.firstOrNull { it.id == id }?.notificationKey
        accessibility.removeAll { it.id == id }
        if (notificationKey != null) notifications.remove(notificationKey)
        prune()
        return accessibility.firstOrNull()
    }

    @Synchronized
    fun cancelAccessibility() {
        accessibility.clear()
    }

    fun isDeviceLocked(context: Context): Boolean =
        context.getSystemService(KeyguardManager::class.java).isDeviceLocked

    fun showUnlockNotice(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.notify(
            14302,
            notificationBuilder(context)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("QQ 自动回复")
                .setContentText("解锁后可继续处理 QQ 消息")
                .setAutoCancel(true)
                .build(),
        )
    }

    fun showFailureNotice(context: Context) {
        if (!QqNativeConfiguration.sendFailureNotice) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.notify(
            14303,
            notificationBuilder(context)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("QQ 自动回复未发送")
                .setContentText("目标或发送方式无法安全确认，请查看诊断日志")
                .setAutoCancel(true)
                .build(),
        )
    }

    @Synchronized
    private fun prune() {
        val now = System.currentTimeMillis()
        notifications.entries.removeAll { it.value.expiresAt <= now }
        accessibility.removeAll { it.expiresAt <= now }
    }

    private fun notificationBuilder(context: Context): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, "whisnya_qq_bridge")
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
}
