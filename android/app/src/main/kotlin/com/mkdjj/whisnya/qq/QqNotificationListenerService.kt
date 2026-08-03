package com.mkdjj.whisnya.qq

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class QqNotificationListenerService : NotificationListenerService() {
    override fun onCreate() {
        super.onCreate()
        QqFlutterEngineHolder.getOrCreate()
    }

    override fun onNotificationPosted(status: StatusBarNotification?) {
        val value = status ?: return
        val parsed = QqNotificationParser.parse(value) ?: return
        val now = System.currentTimeMillis()
        if (captureUntil >= now) {
            captureUntil = 0
            QqBridgeChannels.notificationCaptured(parsed)
            return
        }
        if (!QqNativeConfiguration.enabled ||
            !QqNativeConfiguration.runtimeActive ||
            QqNativeConfiguration.mode != "notification"
        ) return
        QqPendingReplyStore.put(value, parsed)
        QqBridgeChannels.incomingNotification(parsed) { result ->
            handleFlutterResult(parsed, result)
        }
    }

    private fun handleFlutterResult(parsed: ParsedQqNotification, result: Map<*, *>?) {
        val resultGeneration = (result?.get("runGeneration") as? Number)?.toLong()
        if (!QqNativeRunGuard.canDeliver(
                QqNativeConfiguration.runtimeActive,
                QqNativeConfiguration.runGeneration,
                resultGeneration,
            )
        ) {
            QqPendingReplyStore.removeNotification(parsed.notificationKey, parsed.messageId)
            return
        }
        if (result?.get("status") != "reply") {
            if (!QqPendingNotificationMatchPolicy.keepIgnored(result?.get("reason") as? String)) {
                QqPendingReplyStore.removeNotification(parsed.notificationKey, parsed.messageId)
            }
            return
        }
        val text = result["text"] as? String
        if (text.isNullOrBlank()) {
            QqPendingReplyStore.removeNotification(parsed.notificationKey, parsed.messageId)
            return
        }
        val pending = QqPendingReplyStore.notificationForDelivery(
            key = parsed.notificationKey,
            messageId = parsed.messageId,
            contactKey = parsed.contactKey,
            text = parsed.text,
        ) ?: run {
            QqBridgeChannels.emit(
                "remoteInputSend",
                mapOf("success" to false, "errorCode" to "notification_context_missing"),
            )
            return
        }
        val deliveryMessageId = pending.parsed.messageId
        val remote = if (QqNativeConfiguration.remoteInputEnabled) {
            QqRemoteInputReplySender.send(
                this,
                pending.statusBarNotification.notification,
                text,
            )
        } else {
            QqRemoteInputResult.Unavailable
        }
        val disposition = when (remote) {
                QqRemoteInputResult.Sent -> {
                    QqPendingReplyStore.removeNotification(
                        parsed.notificationKey,
                        deliveryMessageId,
                    )
                    QqBridgeChannels.emit(
                        "remoteInputSend",
                        mapOf("success" to true, "transport" to "notificationRemoteInput"),
                    )
                    QqRemoteInputDisposition.Sent
                }
                QqRemoteInputResult.Unavailable -> if (QqNativeConfiguration.remoteInputEnabled) {
                    QqRemoteInputDisposition.Unavailable
                } else {
                    QqRemoteInputDisposition.Disabled
                }
                is QqRemoteInputResult.Failed -> {
                    QqBridgeChannels.emit(
                        "remoteInputSend",
                        mapOf("success" to false, "errorCode" to remote.code),
                    )
                    QqRemoteInputDisposition.Failed
                }
            }
        when (QqReplyRoutingPolicy.route(
            disposition,
            QqNativeConfiguration.accessibilityFallbackEnabled,
            QqPendingReplyStore.isDeviceLocked(this),
        )) {
            QqDeliveryRoute.Complete -> return
            QqDeliveryRoute.Abort -> {
                QqPendingReplyStore.removeNotification(
                    parsed.notificationKey,
                    deliveryMessageId,
                )
                QqPendingReplyStore.showFailureNotice(this)
                QqBridgeChannels.emit(
                    "remoteInputSend",
                    mapOf(
                        "success" to false,
                        "errorCode" to QqReplyRoutingPolicy.failureCode(disposition),
                    ),
                )
                return
            }
            QqDeliveryRoute.AbortLocked -> {
                QqPendingReplyStore.showUnlockNotice(this)
                QqPendingReplyStore.removeNotification(
                    parsed.notificationKey,
                    deliveryMessageId,
                )
                QqBridgeChannels.emit(
                    "accessibilitySend",
                    mapOf("success" to false, "errorCode" to "device_locked"),
                )
                return
            }
            QqDeliveryRoute.Accessibility -> Unit
        }
        val expected = (result["expectedTitles"] as? List<*>)
            ?.filterIsInstance<String>()
            .orEmpty()
            .ifEmpty { listOf(parsed.title) }
        val task = QqPendingReplyStore.enqueueAccessibility(
            notificationKey = parsed.notificationKey,
            messageId = deliveryMessageId,
            runGeneration = resultGeneration ?: return,
            contactKey = parsed.contactKey,
            expectedTitles = expected,
            text = text,
            returnAfterSend = QqNativeConfiguration.returnAfterSend,
        ) ?: run {
            QqPendingReplyStore.removeNotification(
                parsed.notificationKey,
                deliveryMessageId,
            )
            QqPendingReplyStore.showFailureNotice(this)
            QqBridgeChannels.emit(
                "accessibilitySend",
                mapOf("success" to false, "errorCode" to "queue_full"),
            )
            return
        }
        QqAccessibilityTaskLauncher.launch(this, task)
    }

    companion object {
        @Volatile private var captureUntil: Long = 0

        fun beginCapture() {
            captureUntil = System.currentTimeMillis() + 60_000
            QqBridgeChannels.emit("notificationCapture", mapOf("active" to true))
        }

        fun cancelCapture() {
            captureUntil = 0
            QqBridgeChannels.emit("notificationCapture", mapOf("active" to false))
        }
    }
}
