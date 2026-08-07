package com.mkdjj.whisnya.qq

data class QqAccessibilityNodeCandidate(
    val id: String,
    val editable: Boolean,
    val visible: Boolean,
    val enabled: Boolean,
    val supportsSetText: Boolean,
    val focused: Boolean,
    val bottom: Int,
)

object QqAccessibilitySelector {
    fun titleMatches(current: String?, expectedTitles: List<String>): Boolean {
        val normalized = current?.let(QqNotificationParser::normalizeTitle).orEmpty()
        if (normalized.isEmpty()) return false
        return expectedTitles
            .map(QqNotificationParser::normalizeTitle)
            .any { it == normalized }
    }

    fun selectInput(nodes: List<QqAccessibilityNodeCandidate>): QqAccessibilityNodeCandidate? =
        nodes
            .filter { it.editable && it.visible && it.enabled && it.supportsSetText }
            .sortedWith(
                compareByDescending<QqAccessibilityNodeCandidate> { it.focused }
                    .thenByDescending { it.bottom },
            )
            .firstOrNull()

    fun isSendButton(text: String?, contentDescription: String?): Boolean {
        val labels = setOf("发送", "发送消息", "send", "send message")
        fun matches(value: String?): Boolean = value
            ?.trim()
            ?.replace(Regex("\\s+"), " ")
            ?.lowercase() in labels
        return matches(text) || matches(contentDescription)
    }

    fun nodeMatchesTitle(
        text: String?,
        contentDescription: String?,
        expectedTitles: List<String>,
    ): Boolean = titleMatches(text, expectedTitles) ||
        titleMatches(contentDescription, expectedTitles)

    fun <T> onlyCandidate(values: List<T>): T? = values.singleOrNull()
}
