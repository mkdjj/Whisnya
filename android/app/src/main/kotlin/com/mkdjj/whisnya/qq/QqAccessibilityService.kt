package com.mkdjj.whisnya.qq

import android.accessibilityservice.AccessibilityService
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent

class QqAccessibilityService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private var scheduledBackTaskId: String? = null
    private var scheduledBackAt: Long = 0

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val value = event ?: return
        if (value.packageName?.toString() != QqNativeConfiguration.packageName) return
        if (value.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            scheduledBackTaskId != null &&
            value.eventTime > scheduledBackAt + 100
        ) {
            scheduledBackTaskId = null
        }
        val task = QqPendingReplyStore.currentAccessibility() ?: return
        if (!QqAccessibilityTaskLauncher.canDeliver(task)) {
            QqAccessibilityTaskLauncher.finishAndContinue(this, task)
            return
        }
        if (QqPendingReplyStore.isDeviceLocked(this)) {
            QqPendingReplyStore.showUnlockNotice(this)
            return
        }
        QqAccessibilityReplyExecutor.execute(this, task)
    }

    override fun onInterrupt() {
        QqPendingReplyStore.cancelAccessibility()
    }

    fun scheduleSingleBack(taskId: String, after: () -> Unit) {
        scheduledBackTaskId = taskId
        scheduledBackAt = System.currentTimeMillis()
        handler.postDelayed({
            if (scheduledBackTaskId == taskId) {
                scheduledBackTaskId = null
                performGlobalAction(GLOBAL_ACTION_BACK)
            }
            after()
        }, 500)
    }
}
