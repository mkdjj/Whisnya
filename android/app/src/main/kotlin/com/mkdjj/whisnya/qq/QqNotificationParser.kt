package com.mkdjj.whisnya.qq

import android.app.Notification
import android.app.Person
import android.os.Build
import android.os.Bundle
import android.service.notification.StatusBarNotification
import java.security.MessageDigest

data class QqNotificationSnapshot(
    val packageName: String,
    val notificationKey: String,
    val postTime: Long,
    val ongoing: Boolean,
    val groupSummary: Boolean,
    val groupConversation: Boolean,
    val conversationTitle: String?,
    val title: String?,
    val messagingPersonName: String?,
    val messagingTexts: List<String>,
    val extraText: String?,
    val bigText: String?,
    val shortcutId: String?,
)

data class ParsedQqNotification(
    val messageId: String,
    val contactKey: String,
    val title: String,
    val text: String,
    val packageName: String,
    val notificationKey: String,
    val shortcutId: String?,
    val timestamp: Long,
)

object QqNotificationParser {
    private const val QQ_PACKAGE = "com.tencent.mobileqq"
    private val unreadCountSuffix = Regex(
        "\\s*[（(]\\s*\\d+\\s*条\\s*(?:未读|新)?\\s*(?:消息|信息)\\s*[）)]\\s*$",
    )
    private val ignoredPhrases = listOf(
        "qq正在运行",
        "qq服务",
        "登录",
        "下载",
        "通话",
        "好友申请",
        "正在运行",
    )

    fun parse(status: StatusBarNotification): ParsedQqNotification? {
        val notification = status.notification
        val messages = notification.extras
            .getParcelableArray(Notification.EXTRA_MESSAGES)
            .orEmpty()
            .mapNotNull { it as? Bundle }
        val latestMessage = messages.lastOrNull()
        val snapshot = QqNotificationSnapshot(
            packageName = status.packageName,
            notificationKey = status.key,
            postTime = status.postTime,
            ongoing = notification.flags and Notification.FLAG_ONGOING_EVENT != 0,
            groupSummary = notification.flags and Notification.FLAG_GROUP_SUMMARY != 0,
            groupConversation = notification.extras
                .getBoolean("android.isGroupConversation", false),
            conversationTitle = notification.extras
                .getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)
                ?.toString(),
            title = notification.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
            messagingPersonName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                latestMessage?.getParcelable<Person>("sender_person")?.name?.toString()
                    ?: latestMessage?.getCharSequence("sender")?.toString()
            } else {
                latestMessage?.getCharSequence("sender")?.toString()
            },
            messagingTexts = messages.mapNotNull { it.getCharSequence("text")?.toString() },
            extraText = notification.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
            bigText = notification.extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString(),
            shortcutId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                notification.shortcutId
            } else {
                null
            },
        )
        return parseSnapshot(snapshot)
    }

    fun parseSnapshot(snapshot: QqNotificationSnapshot): ParsedQqNotification? {
        if (snapshot.packageName != QQ_PACKAGE ||
            snapshot.ongoing ||
            snapshot.groupSummary
        ) {
            return null
        }
        val rawTitle = firstNonEmpty(
            snapshot.conversationTitle,
            snapshot.title,
            snapshot.messagingPersonName,
        ) ?: return null
        if (snapshot.groupConversation && !hasUnreadCountSuffix(rawTitle)) return null
        val title = normalizeConversationTitle(rawTitle).takeIf(String::isNotEmpty) ?: return null
        val text = firstNonEmpty(
            snapshot.messagingTexts.lastOrNull(),
            snapshot.extraText,
            snapshot.bigText,
        )?.trim().orEmpty()
        if (text.isEmpty()) return null
        val searchable = "$title\n$text".lowercase()
        if (ignoredPhrases.any(searchable::contains)) return null
        val key = contactKey(snapshot.packageName, title, snapshot.shortcutId)
        val messageId = sha256("${snapshot.notificationKey}\n${snapshot.postTime}\n$text")
        return ParsedQqNotification(
            messageId = messageId,
            contactKey = key,
            title = title,
            text = text,
            packageName = snapshot.packageName,
            notificationKey = snapshot.notificationKey,
            shortcutId = snapshot.shortcutId,
            timestamp = snapshot.postTime,
        )
    }

    fun contactKey(packageName: String, title: String, shortcutId: String?): String =
        sha256(
            "${packageName.trim()}\n${normalizeConversationTitle(title)}\n" +
                shortcutId?.trim().orEmpty(),
        )

    fun normalizeTitle(value: String): String = value.trim().replace(Regex("\\s+"), " ")

    fun normalizeConversationTitle(value: String): String =
        normalizeTitle(value).replace(unreadCountSuffix, "").trim()

    private fun hasUnreadCountSuffix(value: String): Boolean =
        unreadCountSuffix.containsMatchIn(normalizeTitle(value))

    private fun firstNonEmpty(vararg values: String?): String? =
        values.firstOrNull { !it.isNullOrBlank() }

    private fun sha256(value: String): String = MessageDigest
        .getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
}
