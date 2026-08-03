package com.mkdjj.whisnya.qq

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
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
    fun `unread count suffix keeps the captured contact identity`() {
        val plain = QqNotificationParser.parseSnapshot(
            snapshot(conversationTitle = "Alice", title = "Alice"),
        )!!
        val fullWidth = QqNotificationParser.parseSnapshot(
            snapshot(
                conversationTitle = "Alice（2条未读信息）",
                title = "Alice（2条未读信息）",
            ),
        )!!
        val halfWidth = QqNotificationParser.parseSnapshot(
            snapshot(
                conversationTitle = "Alice (12条新消息)",
                title = "Alice (12条新消息)",
            ),
        )!!

        assertEquals("Alice", fullWidth.title)
        assertEquals("Alice", halfWidth.title)
        assertEquals(plain.contactKey, fullWidth.contactKey)
        assertEquals(plain.contactKey, halfWidth.contactKey)
    }

    @Test
    fun `qq unread count notification is capturable despite legacy group flag`() {
        val parsed = QqNotificationParser.parseSnapshot(
            snapshot(
                groupConversation = true,
                conversationTitle = "Alice（2条未读信息）",
                title = "Alice（2条未读信息）",
            ),
        )

        assertNotNull(parsed)
        assertEquals("Alice", parsed?.title)
    }

    @Test
    fun `group compatibility checks only the selected title candidate`() {
        assertNull(
            QqNotificationParser.parseSnapshot(
                snapshot(
                    groupConversation = true,
                    conversationTitle = "Study Group",
                    title = "Alice（2条未读信息）",
                ),
            ),
        )
        val parsed = QqNotificationParser.parseSnapshot(
            snapshot(
                groupConversation = true,
                conversationTitle = null,
                title = null,
                messagingPersonName = "Alice（2条未读信息）",
            ),
        )
        assertEquals("Alice", parsed?.title)
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
        messagingPersonName: String? = null,
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
        messagingPersonName = messagingPersonName,
        messagingTexts = messagingTexts,
        extraText = extraText,
        bigText = null,
        shortcutId = shortcutId,
    )
}
