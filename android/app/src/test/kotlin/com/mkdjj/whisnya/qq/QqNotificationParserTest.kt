package com.mkdjj.whisnya.qq

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class QqNotificationParserTest {
    @Test
    fun `ignores non qq ongoing group summary and group conversations`() {
        assertNull(QqNotificationParser.parseSnapshot(snapshot(packageName = "other.app")))
        assertNull(QqNotificationParser.parseSnapshot(snapshot(ongoing = true)))
        assertNull(QqNotificationParser.parseSnapshot(snapshot(groupSummary = true)))
        assertNull(QqNotificationParser.parseSnapshot(snapshot(groupConversation = true)))
    }

    @Test
    fun `prefers conversation title and newest messaging text`() {
        val parsed = QqNotificationParser.parseSnapshot(
            snapshot(
                conversationTitle = " Alice   Zhang ",
                title = "fallback",
                messagingTexts = listOf("old", "new"),
                extraText = "extra",
                shortcutId = "shortcut",
            ),
        )!!
        assertEquals("Alice Zhang", parsed.title)
        assertEquals("new", parsed.text)
        assertEquals(64, parsed.contactKey.length)
        assertEquals(
            parsed.contactKey,
            QqNotificationParser.contactKey(
                "com.tencent.mobileqq",
                "Alice Zhang",
                "shortcut",
            ),
        )
    }

    @Test
    fun `ignores service notifications and empty text`() {
        assertNull(QqNotificationParser.parseSnapshot(snapshot(title = "QQ", extraText = "QQ正在运行")))
        assertNull(QqNotificationParser.parseSnapshot(snapshot(extraText = "")))
    }

    private fun snapshot(
        packageName: String = "com.tencent.mobileqq",
        ongoing: Boolean = false,
        groupSummary: Boolean = false,
        groupConversation: Boolean = false,
        conversationTitle: String? = "Alice",
        title: String? = "Alice",
        messagingTexts: List<String> = emptyList(),
        extraText: String? = "hello",
        shortcutId: String? = null,
    ) = QqNotificationSnapshot(
        packageName = packageName,
        notificationKey = "native-key",
        postTime = 1_785_715_200_000,
        ongoing = ongoing,
        groupSummary = groupSummary,
        groupConversation = groupConversation,
        conversationTitle = conversationTitle,
        title = title,
        messagingPersonName = null,
        messagingTexts = messagingTexts,
        extraText = extraText,
        bigText = null,
        shortcutId = shortcutId,
    )
}
