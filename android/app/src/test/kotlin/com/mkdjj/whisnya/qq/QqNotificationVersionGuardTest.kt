package com.mkdjj.whisnya.qq

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class QqNotificationVersionGuardTest {
    @Test
    fun `older merged callback cannot remove newer context with the same key`() {
        val currentStoredMessageId = "message-2"
        assertFalse(
            QqNotificationVersionGuard.isCurrent(
                currentStoredMessageId,
                callbackMessageId = "message-1",
            ),
        )
        assertTrue(
            QqNotificationVersionGuard.isCurrent(
                currentStoredMessageId,
                callbackMessageId = "message-2",
            ),
        )
    }

    @Test
    fun `finishing old accessibility task preserves newer same key context`() {
        assertFalse(
            QqAccessibilityCompletionGuard.shouldRemoveNotification(
                storedMessageId = "message-2",
                completedMessageId = "message-1",
            ),
        )
        assertTrue(
            QqAccessibilityCompletionGuard.shouldRemoveNotification(
                storedMessageId = "message-2",
                completedMessageId = "message-2",
            ),
        )
    }

    @Test
    fun `same message notification update remains usable for delivery`() {
        assertTrue(
            QqPendingNotificationMatchPolicy.canUseForDelivery(
                storedContactKey = "alice",
                storedText = "hello",
                callbackContactKey = "alice",
                callbackText = "hello",
            ),
        )
        assertFalse(
            QqPendingNotificationMatchPolicy.canUseForDelivery(
                storedContactKey = "alice",
                storedText = "different",
                callbackContactKey = "alice",
                callbackText = "hello",
            ),
        )
        assertFalse(
            QqPendingNotificationMatchPolicy.canUseForDelivery(
                storedContactKey = "bob",
                storedText = "hello",
                callbackContactKey = "alice",
                callbackText = "hello",
            ),
        )
    }

    @Test
    fun `duplicate callback keeps the replacement notification context`() {
        assertTrue(QqPendingNotificationMatchPolicy.keepIgnored("duplicate"))
        assertFalse(QqPendingNotificationMatchPolicy.keepIgnored("merged"))
        assertFalse(QqPendingNotificationMatchPolicy.keepIgnored("unknownContact"))
    }
}
