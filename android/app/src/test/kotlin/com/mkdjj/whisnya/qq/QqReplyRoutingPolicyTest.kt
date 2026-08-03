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
    fun `remote input abort exposes a useful diagnostic code`() {
        assertEquals(
            "remote_input_unavailable",
            QqReplyRoutingPolicy.failureCode(QqRemoteInputDisposition.Unavailable),
        )
        assertEquals(
            "remote_input_disabled",
            QqReplyRoutingPolicy.failureCode(QqRemoteInputDisposition.Disabled),
        )
        assertEquals(
            "remote_input_failed",
            QqReplyRoutingPolicy.failureCode(QqRemoteInputDisposition.Failed),
        )
    }

    @Test
    fun `remote input failure emits its concrete code exactly once`() {
        val emitted = mutableListOf<String>()

        QqRemoteInputFailureReporter.report(
            disposition = QqRemoteInputDisposition.Failed,
            concreteFailureCode = "pending_intent_cancelled",
            emit = emitted::add,
        )

        assertEquals(listOf("pending_intent_cancelled"), emitted)
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

    @Test
    fun `accessibility task cannot continue after pause stop or replacement`() {
        assertEquals(
            false,
            QqAccessibilityRunGuard.canDeliver(
                runtimeActive = false,
                currentGeneration = 8,
                taskGeneration = 8,
                isCurrentTask = true,
            ),
        )
        assertEquals(
            false,
            QqAccessibilityRunGuard.canDeliver(
                runtimeActive = true,
                currentGeneration = 9,
                taskGeneration = 8,
                isCurrentTask = true,
            ),
        )
        assertEquals(
            false,
            QqAccessibilityRunGuard.canDeliver(
                runtimeActive = true,
                currentGeneration = 8,
                taskGeneration = 8,
                isCurrentTask = false,
            ),
        )
        assertEquals(
            true,
            QqAccessibilityRunGuard.canDeliver(
                runtimeActive = true,
                currentGeneration = 8,
                taskGeneration = 8,
                isCurrentTask = true,
            ),
        )
    }
}
