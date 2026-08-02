package com.mkdjj.whisnya.qq

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class QqAccessibilitySelectorTest {
    @Test
    fun `normalizes only whitespace and requires exact title`() {
        assertTrue(QqAccessibilitySelector.titleMatches(" Alice   Zhang ", listOf("Alice Zhang")))
        assertFalse(QqAccessibilitySelector.titleMatches("Alice Zhan", listOf("Alice Zhang")))
        assertFalse(QqAccessibilitySelector.titleMatches("Group · Alice Zhang", listOf("Alice Zhang")))
    }

    @Test
    fun `selects focused or lowest valid editable input`() {
        val nodes = listOf(
            QqAccessibilityNodeCandidate("top", editable = true, visible = true, enabled = true, supportsSetText = true, focused = false, bottom = 100),
            QqAccessibilityNodeCandidate("bottom", editable = true, visible = true, enabled = true, supportsSetText = true, focused = false, bottom = 900),
            QqAccessibilityNodeCandidate("focused", editable = true, visible = true, enabled = true, supportsSetText = true, focused = true, bottom = 500),
        )
        assertEquals("focused", QqAccessibilitySelector.selectInput(nodes)?.id)
    }

    @Test
    fun `accepts exact send labels and never selects an unrelated button`() {
        assertTrue(QqAccessibilitySelector.isSendButton("发送", null))
        assertTrue(QqAccessibilitySelector.isSendButton(null, "Send"))
        assertFalse(QqAccessibilitySelector.isSendButton("转发", null))
    }

    @Test
    fun `requires one unambiguous send candidate`() {
        assertEquals("send", QqAccessibilitySelector.onlyCandidate(listOf("send")))
        assertEquals(null, QqAccessibilitySelector.onlyCandidate(listOf("send-1", "send-2")))
    }
}
