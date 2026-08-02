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
        val labels = setOf("发送", "Send")
        return text?.trim() in labels || contentDescription?.trim() in labels
    }

    fun <T> onlyCandidate(values: List<T>): T? = values.singleOrNull()
}
