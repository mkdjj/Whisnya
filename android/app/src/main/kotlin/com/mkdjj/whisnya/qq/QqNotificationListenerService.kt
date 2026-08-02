package com.mkdjj.whisnya.qq

import android.app.PendingIntent
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
        if (!QqNativeConfiguration.enabled || QqNativeConfiguration.mode != "notification") return
        QqPendingReplyStore.put(value, parsed)
        QqBridgeChannels.incomingNotification(parsed) { result ->
            handleFlutterResult(parsed, result)
        }
    }

    private fun handleFlutterResult(parsed: ParsedQqNotification, result: Map<*, *>?) {
        if (result?.get("status") != "reply") {
            QqPendingReplyStore.removeNotification(parsed.notificationKey)
            return
        }
        val text = result["text"] as? String
        if (text.isNullOrBlank()) {
            QqPendingReplyStore.removeNotification(parsed.notificationKey)
            return
        }
        val pending = QqPendingReplyStore.notification(parsed.notificationKey) ?: return
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
                    QqPendingReplyStore.removeNotification(parsed.notificationKey)
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
                QqPendingReplyStore.removeNotification(parsed.notificationKey)
                QqPendingReplyStore.showFailureNotice(this)
                QqBridgeChannels.emit("remoteInputSend", mapOf("success" to false))
                return
            }
            QqDeliveryRoute.AbortLocked -> {
                QqPendingReplyStore.showUnlockNotice(this)
                QqPendingReplyStore.removeNotification(parsed.notificationKey)
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
            contactKey = parsed.contactKey,
            expectedTitles = expected,
            text = text,
            returnAfterSend = QqNativeConfiguration.returnAfterSend,
        ) ?: run {
            QqPendingReplyStore.showFailureNotice(this)
            QqBridgeChannels.emit(
                "accessibilitySend",
                mapOf("success" to false, "errorCode" to "queue_full"),
            )
            return
        }
        try {
            pending.statusBarNotification.notification.contentIntent?.send()
                ?: abortAccessibility(task, "content_intent_missing")
        } catch (_: PendingIntent.CanceledException) {
            abortAccessibility(task, "content_intent_cancelled")
        } catch (_: SecurityException) {
            abortAccessibility(task, "content_intent_security")
        }
    }

    private fun abortAccessibility(task: PendingAccessibilityReply, code: String) {
        QqPendingReplyStore.finishAccessibility(task.id)
        QqPendingReplyStore.showFailureNotice(this)
        QqBridgeChannels.emit(
            "accessibilitySend",
            mapOf("success" to false, "errorCode" to code),
        )
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
