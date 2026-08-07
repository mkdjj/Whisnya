package com.mkdjj.whisnya.qq

import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.LinkedHashMap

private data class HeldQqNotification(
    val statusBarNotification: StatusBarNotification,
    val parsed: ParsedQqNotification,
    val expiresAt: Long,
)

class QqNotificationListenerService : NotificationListenerService() {
    override fun onCreate() {
        super.onCreate()
        instance = this
        QqFlutterEngineHolder.getOrCreate()
    }

    override fun onDestroy() {
        connected = false
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        connected = true
        instance = this
        QqBridgeChannels.notificationListenerState(this, true)
        drainHeldNotifications()
    }

    override fun onListenerDisconnected() {
        connected = false
        QqBridgeChannels.notificationListenerState(this, false)
        requestReconnect(this)
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(status: StatusBarNotification?) {
        val value = status ?: return
        val expectedPackage = QqNativeConfiguration.packageName
        if (value.packageName != expectedPackage) return
        val parsed = QqNotificationParser.parse(value, expectedPackage) ?: run {
            QqBridgeChannels.emit(
                "notificationRejected",
                mapOf("success" to false, "errorCode" to "notification_format_unsupported"),
            )
            return
        }
        val now = System.currentTimeMillis()
        if (captureUntil >= now) {
            captureUntil = 0
            QqBridgeChannels.notificationCaptured(parsed)
            return
        }
        when (dispatchDecision()) {
            QqNotificationDispatchDecision.Hold -> hold(value, parsed)
            QqNotificationDispatchDecision.Dispatch -> dispatch(value, parsed)
            QqNotificationDispatchDecision.Ignore -> Unit
        }
    }

    private fun dispatch(
        statusBarNotification: StatusBarNotification,
        parsed: ParsedQqNotification,
    ) {
        if (!QqNativeConfiguration.enabled ||
            !QqNativeConfiguration.runtimeActive ||
            QqNativeConfiguration.mode != "notification"
        ) return
        QqPendingReplyStore.put(statusBarNotification, parsed)
        QqBridgeChannels.incomingNotification(parsed) { result ->
            handleFlutterResult(parsed, result)
        }
    }

    private fun drainHeldNotifications() {
        if (dispatchDecision() != QqNotificationDispatchDecision.Dispatch) return
        takeHeld().forEach { held ->
            dispatch(held.statusBarNotification, held.parsed)
        }
    }

    private fun dispatchDecision(): QqNotificationDispatchDecision =
        QqNotificationDispatchPolicy.decide(
            dartSynchronized = QqNativeConfiguration.dartSynchronized,
            enabled = QqNativeConfiguration.enabled,
            runtimeActive = QqNativeConfiguration.runtimeActive,
            mode = QqNativeConfiguration.mode,
        )

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
                is QqRemoteInputResult.Failed -> QqRemoteInputDisposition.Failed
            }
        QqRemoteInputFailureReporter.report(
            disposition = disposition,
            concreteFailureCode = (remote as? QqRemoteInputResult.Failed)?.code,
        ) { code ->
            QqBridgeChannels.emit(
                "remoteInputSend",
                mapOf("success" to false, "errorCode" to code),
            )
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
        private const val COLD_START_TTL = 30_000L
        private const val MAX_HELD_NOTIFICATIONS = 10
        @Volatile private var captureUntil: Long = 0
        @Volatile private var instance: QqNotificationListenerService? = null
        @Volatile var connected: Boolean = false
            private set
        private val heldNotifications = LinkedHashMap<String, HeldQqNotification>()

        @Synchronized
        private fun hold(status: StatusBarNotification, parsed: ParsedQqNotification) {
            val now = System.currentTimeMillis()
            heldNotifications.entries.removeAll { it.value.expiresAt <= now }
            heldNotifications[parsed.notificationKey] = HeldQqNotification(
                statusBarNotification = status,
                parsed = parsed,
                expiresAt = now + COLD_START_TTL,
            )
            while (heldNotifications.size > MAX_HELD_NOTIFICATIONS) {
                heldNotifications.remove(heldNotifications.keys.first())
            }
        }

        @Synchronized
        private fun takeHeld(): List<HeldQqNotification> {
            val now = System.currentTimeMillis()
            val ready = heldNotifications.values.filter { it.expiresAt > now }
            heldNotifications.clear()
            return ready
        }

        fun nativeConfigurationUpdated() {
            instance?.drainHeldNotifications()
        }

        fun requestReconnect(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !connected) {
                requestRebind(ComponentName(context, QqNotificationListenerService::class.java))
            }
        }

        fun beginCapture() {
            instance?.let(::requestReconnect)
            captureUntil = System.currentTimeMillis() + 60_000
            QqBridgeChannels.emit("notificationCapture", mapOf("active" to true))
        }

        fun cancelCapture() {
            captureUntil = 0
            QqBridgeChannels.emit("notificationCapture", mapOf("active" to false))
        }
    }
}
