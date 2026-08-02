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
}
