package com.mkdjj.whisnya.qq

import android.app.PendingIntent
import android.app.ActivityOptions
import android.os.Build
import android.content.Context

object QqAccessibilityTaskLauncher {
    fun launch(context: Context, task: PendingAccessibilityReply) {
        if (!canDeliver(task)) {
            finishAndContinue(context, task)
            return
        }
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
        val service = QqAccessibilityService.activeInstance()
        if (service == null) {
            finishAndContinue(context, task, "accessibility_service_disconnected")
            return
        }
        try {
            contentIntent.send(
                service,
                0,
                null,
                null,
                null,
                null,
                backgroundLaunchOptions(),
            )
            QqBridgeChannels.emit(
                "accessibilityProgress",
                mapOf("success" to true, "stage" to "fallback_started"),
            )
            service.watch(task)
        } catch (_: PendingIntent.CanceledException) {
            finishAndContinue(context, task, "content_intent_cancelled")
        } catch (_: SecurityException) {
            finishAndContinue(context, task, "content_intent_security")
        }
    }

    fun canDeliver(task: PendingAccessibilityReply): Boolean =
        QqAccessibilityRunGuard.canDeliver(
            runtimeActive = QqNativeConfiguration.runtimeActive,
            currentGeneration = QqNativeConfiguration.runGeneration,
            taskGeneration = task.runGeneration,
            isCurrentTask = QqPendingReplyStore.isAccessibilityCurrent(task.id),
        )

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

    private fun backgroundLaunchOptions(): android.os.Bundle? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return null
        val launchMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
            ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOW_ALWAYS
        } else {
            @Suppress("DEPRECATION")
            ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
        }
        val options = ActivityOptions.makeBasic()
            .setPendingIntentBackgroundActivityStartMode(
                launchMode,
            )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            options.setPendingIntentCreatorBackgroundActivityStartMode(
                launchMode,
            )
        }
        return options.toBundle()
    }
}
