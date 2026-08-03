package com.mkdjj.whisnya.qq

enum class QqRemoteInputDisposition { Sent, Unavailable, Failed, Disabled }

enum class QqDeliveryRoute { Complete, Accessibility, AbortLocked, Abort }

object QqReplyRoutingPolicy {
    fun route(
        remoteInput: QqRemoteInputDisposition,
        accessibilityFallbackEnabled: Boolean,
        deviceLocked: Boolean,
    ): QqDeliveryRoute {
        if (remoteInput == QqRemoteInputDisposition.Sent) return QqDeliveryRoute.Complete
        if (!accessibilityFallbackEnabled) return QqDeliveryRoute.Abort
        if (deviceLocked) return QqDeliveryRoute.AbortLocked
        return QqDeliveryRoute.Accessibility
    }

    fun failureCode(remoteInput: QqRemoteInputDisposition): String = when (remoteInput) {
        QqRemoteInputDisposition.Unavailable -> "remote_input_unavailable"
        QqRemoteInputDisposition.Disabled -> "remote_input_disabled"
        QqRemoteInputDisposition.Failed -> "remote_input_failed"
        QqRemoteInputDisposition.Sent -> ""
    }
}

object QqNativeRunGuard {
    fun canDeliver(
        runtimeActive: Boolean,
        currentGeneration: Long,
        resultGeneration: Long?,
    ): Boolean = runtimeActive &&
        resultGeneration != null &&
        currentGeneration == resultGeneration
}

object QqAccessibilityRunGuard {
    fun canDeliver(
        runtimeActive: Boolean,
        currentGeneration: Long,
        taskGeneration: Long,
        isCurrentTask: Boolean,
    ): Boolean = isCurrentTask && QqNativeRunGuard.canDeliver(
        runtimeActive,
        currentGeneration,
        taskGeneration,
    )
}
