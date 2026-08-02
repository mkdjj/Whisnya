package com.mkdjj.whisnya.qq

import org.junit.Assert.assertEquals
import org.junit.Test

class QqReplyRoutingPolicyTest {
    @Test
    fun `remote input success never enters accessibility`() {
        assertEquals(
            QqDeliveryRoute.Complete,
            QqReplyRoutingPolicy.route(
                QqRemoteInputDisposition.Sent,
                accessibilityFallbackEnabled = true,
                deviceLocked = false,
            ),
        )
    }

    @Test
    fun `remote input failure follows fallback setting`() {
        assertEquals(
            QqDeliveryRoute.Accessibility,
            QqReplyRoutingPolicy.route(
                QqRemoteInputDisposition.Failed,
                accessibilityFallbackEnabled = true,
                deviceLocked = false,
            ),
        )
        assertEquals(
            QqDeliveryRoute.Abort,
            QqReplyRoutingPolicy.route(
                QqRemoteInputDisposition.Failed,
                accessibilityFallbackEnabled = false,
                deviceLocked = false,
            ),
        )
    }

    @Test
    fun `locked device always aborts before accessibility`() {
        assertEquals(
            QqDeliveryRoute.AbortLocked,
            QqReplyRoutingPolicy.route(
                QqRemoteInputDisposition.Unavailable,
                accessibilityFallbackEnabled = true,
                deviceLocked = true,
            ),
        )
    }

    @Test
    fun `stopped or stale runtime generation cannot deliver`() {
        assertEquals(
            false,
            QqNativeRunGuard.canDeliver(
                runtimeActive = false,
                currentGeneration = 4,
                resultGeneration = 4,
            ),
        )
        assertEquals(
            false,
            QqNativeRunGuard.canDeliver(
                runtimeActive = true,
                currentGeneration = 5,
                resultGeneration = 4,
            ),
        )
        assertEquals(
            true,
            QqNativeRunGuard.canDeliver(
                runtimeActive = true,
                currentGeneration = 5,
                resultGeneration = 5,
            ),
        )
    }
}
