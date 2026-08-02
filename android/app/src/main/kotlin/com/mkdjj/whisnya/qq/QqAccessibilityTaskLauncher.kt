package com.mkdjj.whisnya.qq

import android.app.PendingIntent
import android.content.Context

object QqAccessibilityTaskLauncher {
    fun launch(context: Context, task: PendingAccessibilityReply) {
        if (QqPendingReplyStore.currentAccessibility()?.id != task.id) return
        if (QqPendingReplyStore.isDeviceLocked(context)) {
            QqPendingReplyStore.showUnlockNotice(context)
            QqPendingReplyStore.cancelAccessibility()
            abort("device_locked")
            return
        }
        val pending = QqPendingReplyStore.notification(
            task.notificationKey,
            task.messageId,
        )
        val contentIntent = pending?.statusBarNotification?.notification?.contentIntent
        if (contentIntent == null) {
            finishAndContinue(context, task, "content_intent_missing")
            return
        }
        try {
            contentIntent.send()
        } catch (_: PendingIntent.CanceledException) {
            finishAndContinue(context, task, "content_intent_cancelled")
        } catch (_: SecurityException) {
            finishAndContinue(context, task, "content_intent_security")
        }
    }

    fun finishAndContinue(
        context: Context,
        task: PendingAccessibilityReply,
        errorCode: String? = null,
    ) {
        val next = QqPendingReplyStore.finishAccessibility(task.id)
        if (errorCode != null) {
            QqPendingReplyStore.showFailureNotice(context)
            abort(errorCode)
        }
        if (next != null) launch(context, next)
    }

    private fun abort(code: String) {
        QqBridgeChannels.emit(
            "accessibilitySend",
            mapOf("success" to false, "errorCode" to code),
        )
    }
}
