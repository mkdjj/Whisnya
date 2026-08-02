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
