package com.mkdjj.whisnya.qq

import android.graphics.Rect
import android.os.Bundle
import android.view.accessibility.AccessibilityNodeInfo

object QqAccessibilityReplyExecutor {
    fun execute(service: QqAccessibilityService, task: PendingAccessibilityReply): Boolean {
        if (task.clicked ||
            task.expiresAt <= System.currentTimeMillis() ||
            !QqAccessibilityTaskLauncher.canDeliver(task)
        ) {
            QqAccessibilityTaskLauncher.finishAndContinue(service, task)
            return false
        }
        val root = service.rootInActiveWindow ?: return false
        if (root.packageName?.toString() != QqNativeConfiguration.packageName) return false
        if (!hasExpectedTitle(root, task.expectedTitles)) return false
        val nodes = descendants(root)
        val inputs = nodes.mapIndexedNotNull { index, node ->
            val candidate = QqAccessibilityNodeCandidate(
                id = index.toString(),
                editable = node.isEditable,
                visible = node.isVisibleToUser,
                enabled = node.isEnabled,
                supportsSetText = node.actionList.any {
                    it.id == AccessibilityNodeInfo.ACTION_SET_TEXT
                },
                focused = node.isFocused,
                bottom = Rect().also(node::getBoundsInScreen).bottom,
            )
            if (candidate.editable) candidate to node else null
        }
        val selected = QqAccessibilitySelector.selectInput(inputs.map { it.first }) ?: return false
        val input = inputs.first { it.first.id == selected.id }.second
        val arguments = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, task.text)
        }
        if (!QqAccessibilityTaskLauncher.canDeliver(task)) {
            QqAccessibilityTaskLauncher.finishAndContinue(service, task)
            return false
        }
        if (!input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)) return false

        val refreshed = service.rootInActiveWindow ?: return false
        if (!hasExpectedTitle(refreshed, task.expectedTitles)) return false
        val send = findSendButton(refreshed) ?: return false
        if (!QqAccessibilityTaskLauncher.canDeliver(task)) {
            QqAccessibilityTaskLauncher.finishAndContinue(service, task)
            return false
        }
        task.clicked = true
        val clicked = send.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        if (!clicked) {
            QqAccessibilityTaskLauncher.finishAndContinue(
                service,
                task,
                "click_failed",
            )
            return false
        }
        val next = QqPendingReplyStore.finishAccessibility(task.id)
        QqBridgeChannels.emit(
            "accessibilitySend",
            mapOf("success" to true, "transport" to "accessibility"),
        )
        val continueQueue = {
            if (next != null) QqAccessibilityTaskLauncher.launch(service, next)
        }
        if (task.returnAfterSend) {
            service.scheduleSingleBack(task.id, continueQueue)
        } else {
            continueQueue()
        }
        return true
    }

    private fun hasExpectedTitle(root: AccessibilityNodeInfo, expected: List<String>): Boolean {
        val rootBounds = Rect().also(root::getBoundsInScreen)
        val maximumBottom = rootBounds.top + rootBounds.height() / 3
        return descendants(root).any { node ->
            if (!node.isVisibleToUser) return@any false
            val bounds = Rect().also(node::getBoundsInScreen)
            bounds.bottom <= maximumBottom &&
                QqAccessibilitySelector.nodeMatchesTitle(
                    node.text?.toString(),
                    node.contentDescription?.toString(),
                    expected,
                )
        }
    }

    private fun findSendButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val configuredId = QqNativeConfiguration.sendButtonViewId
        if (configuredId.isNotBlank()) {
            val configured = try {
                root.findAccessibilityNodeInfosByViewId(configuredId)
                    .filter {
                        it.isVisibleToUser &&
                            it.isEnabled &&
                            it.isClickable &&
                            QqAccessibilitySelector.isSendButton(
                                it.text?.toString(),
                                it.contentDescription?.toString(),
                            )
                    }
            } catch (_: RuntimeException) {
                emptyList()
            }
            if (configured.isNotEmpty()) {
                return QqAccessibilitySelector.onlyCandidate(configured)
            }
        }
        val labeled = descendants(root).filter {
            it.isVisibleToUser &&
                it.isEnabled &&
                it.isClickable &&
                QqAccessibilitySelector.isSendButton(
                    it.text?.toString(),
                    it.contentDescription?.toString(),
                )
        }
        if (labeled.isNotEmpty()) {
            return QqAccessibilitySelector.onlyCandidate(labeled)
        }
        return null
    }

    private fun descendants(root: AccessibilityNodeInfo): List<AccessibilityNodeInfo> {
        val result = ArrayList<AccessibilityNodeInfo>()
        fun visit(node: AccessibilityNodeInfo) {
            result.add(node)
            for (index in 0 until node.childCount) node.getChild(index)?.let(::visit)
        }
        visit(root)
        return result
    }
}
