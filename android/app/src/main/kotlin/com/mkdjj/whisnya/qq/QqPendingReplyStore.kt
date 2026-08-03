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
    val runGeneration: Long,
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

object QqAccessibilityCompletionGuard {
    fun shouldRemoveNotification(
        storedMessageId: String?,
        completedMessageId: String,
    ): Boolean = QqNotificationVersionGuard.isCurrent(
        storedMessageId,
        completedMessageId,
    )
}

object QqPendingNotificationMatchPolicy {
    fun canUseForDelivery(
        storedContactKey: String,
        storedText: String,
        callbackContactKey: String,
        callbackText: String,
    ): Boolean = storedContactKey == callbackContactKey && storedText == callbackText

    fun keepIgnored(reason: String?): Boolean = reason == "duplicate"
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
    fun notificationForDelivery(
        key: String,
        contactKey: String,
        text: String,
    ): QqPendingNotificationContext? {
        prune()
        return notifications[key]?.takeIf {
            QqPendingNotificationMatchPolicy.canUseForDelivery(
                storedContactKey = it.parsed.contactKey,
                storedText = it.parsed.text,
                callbackContactKey = contactKey,
                callbackText = text,
            )
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
        runGeneration: Long,
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
            runGeneration = runGeneration,
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
    fun isAccessibilityCurrent(id: String): Boolean {
        prune()
        return accessibility.firstOrNull()?.id == id
    }

    @Synchronized
    fun finishAccessibility(id: String): PendingAccessibilityReply? {
        val completed = accessibility.firstOrNull { it.id == id }
        accessibility.removeAll { it.id == id }
        if (completed != null && QqAccessibilityCompletionGuard.shouldRemoveNotification(
                notifications[completed.notificationKey]?.parsed?.messageId,
                completed.messageId,
            )
        ) {
            notifications.remove(completed.notificationKey)
        }
        prune()
        return accessibility.firstOrNull()
    }

    @Synchronized
    fun cancelAccessibility() {
        accessibility.forEach { task ->
            if (QqAccessibilityCompletionGuard.shouldRemoveNotification(
                    notifications[task.notificationKey]?.parsed?.messageId,
                    task.messageId,
                )
            ) {
                notifications.remove(task.notificationKey)
            }
        }
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
