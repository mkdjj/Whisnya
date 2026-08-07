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
    val textLines: List<String> = emptyList(),
    val extraText: String?,
    val bigText: String?,
    val subText: String? = null,
    val tickerText: String? = null,
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
    const val DEFAULT_QQ_PACKAGE = "com.tencent.mobileqq"
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
    private val ignoredTextPrefixes = listOf("qq正在运行", "qq服务", "正在运行")

    fun parse(
        status: StatusBarNotification,
        expectedPackageName: String = QqNativeConfiguration.packageName,
    ): ParsedQqNotification? {
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
            textLines = notification.extras
                .getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
                .orEmpty()
                .map(CharSequence::toString),
            extraText = notification.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
            bigText = notification.extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString(),
            subText = notification.extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString(),
            tickerText = notification.tickerText?.toString(),
            shortcutId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                notification.shortcutId
            } else {
                null
            },
        )
        return parseSnapshot(snapshot, expectedPackageName)
    }

    fun parseSnapshot(
        snapshot: QqNotificationSnapshot,
        expectedPackageName: String = DEFAULT_QQ_PACKAGE,
    ): ParsedQqNotification? {
        if (snapshot.packageName != expectedPackageName.trim() ||
            snapshot.ongoing ||
            snapshot.groupSummary
        ) {
            return null
        }
        val rawTitle = selectConversationTitle(snapshot) ?: return null
        if (snapshot.groupConversation &&
            snapshot.shortcutId.isNullOrBlank() &&
            !hasUnreadCountSuffix(rawTitle)
        ) return null
        val title = normalizeConversationTitle(rawTitle).takeIf(String::isNotEmpty) ?: return null
        val text = firstNonEmpty(
            snapshot.messagingTexts.lastOrNull(),
            snapshot.extraText,
            snapshot.bigText,
            snapshot.textLines.lastOrNull(),
            snapshot.subText,
            snapshot.tickerText,
        )?.trim().orEmpty()
        if (text.isEmpty()) return null
        val normalizedText = text.lowercase()
        val titleCandidates = listOf(
            snapshot.conversationTitle,
            snapshot.title,
            snapshot.messagingPersonName,
        ).mapNotNull { it?.let(::normalizeConversationTitle)?.lowercase() }
        if (titleCandidates.any(ignoredPhrases::contains) ||
            ignoredTextPrefixes.any(normalizedText::startsWith)
        ) return null
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

    private fun selectConversationTitle(snapshot: QqNotificationSnapshot): String? {
        val conversationTitle = snapshot.conversationTitle
        if (!conversationTitle.isNullOrBlank() && !isGenericTitle(conversationTitle)) {
            return conversationTitle
        }
        return firstNonEmpty(
            snapshot.title,
            snapshot.messagingPersonName,
            conversationTitle,
        )
    }

    private fun isGenericTitle(value: String): Boolean {
        val normalized = normalizeConversationTitle(value).lowercase()
        return normalized == "qq" ||
            normalized == "腾讯qq" ||
            normalized.matches(Regex("\\d+\\s*条(?:新|未读)?(?:消息|信息)"))
    }

    private fun hasUnreadCountSuffix(value: String): Boolean =
        unreadCountSuffix.containsMatchIn(normalizeTitle(value))

    private fun firstNonEmpty(vararg values: String?): String? =
        values.firstOrNull { !it.isNullOrBlank() }

    private fun sha256(value: String): String = MessageDigest
        .getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
}
