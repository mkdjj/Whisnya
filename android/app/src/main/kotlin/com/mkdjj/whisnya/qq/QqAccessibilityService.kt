package com.mkdjj.whisnya.qq

import android.accessibilityservice.AccessibilityService
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent

class QqAccessibilityService : AccessibilityService() {
    companion object {
        private const val PAGE_LOAD_TIMEOUT_MS = 12_000L
        private const val RETRY_DELAY_MS = 250L

        @Volatile
        private var instance: QqAccessibilityService? = null

        fun activeInstance(): QqAccessibilityService? = instance
    }

    private val handler = Handler(Looper.getMainLooper())
    private var scheduledBackTaskId: String? = null
    private var scheduledBackAt: Long = 0
    private var watchedTaskId: String? = null
    private var watchDeadline: Long = 0
    private var lastStage: String? = null
    private var attemptScheduled = false
    private var attemptRunnable: Runnable? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

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
            stopWatching(task.id)
            QqAccessibilityTaskLauncher.finishAndContinue(this, task, "device_locked")
            return
        }
        if (watchedTaskId != task.id) watch(task)
        requestAttempt()
    }

    override fun onInterrupt() {
        val task = QqPendingReplyStore.currentAccessibility()
        if (task != null) {
            stopWatching(task.id)
            QqAccessibilityTaskLauncher.finishAndContinue(
                this,
                task,
                "accessibility_interrupted",
            )
        }
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        val task = QqPendingReplyStore.currentAccessibility()
        if (task != null && QqAccessibilityTaskLauncher.canDeliver(task)) {
            stopWatching(task.id)
            QqAccessibilityTaskLauncher.finishAndContinue(
                this,
                task,
                "accessibility_service_disconnected",
            )
        } else {
            clearWatch()
        }
        super.onDestroy()
    }

    fun watch(task: PendingAccessibilityReply) {
        if (watchedTaskId == task.id) return
        clearWatch()
        watchedTaskId = task.id
        watchDeadline = minOf(
            task.expiresAt,
            System.currentTimeMillis() + PAGE_LOAD_TIMEOUT_MS,
        )
        lastStage = null
        requestAttempt()
    }

    private fun requestAttempt() {
        postAttempt(0)
    }

    private fun scheduleRetry() {
        postAttempt(RETRY_DELAY_MS)
    }

    private fun postAttempt(delayMillis: Long) {
        if (attemptScheduled) return
        attemptScheduled = true
        val runnable = Runnable {
            attemptRunnable = null
            attemptScheduled = false
            attemptCurrentTask()
        }
        attemptRunnable = runnable
        handler.postDelayed(runnable, delayMillis)
    }

    private fun attemptCurrentTask() {
        val task = QqPendingReplyStore.currentAccessibility()
        if (task == null || task.id != watchedTaskId) {
            clearWatch()
            return
        }
        if (!QqAccessibilityTaskLauncher.canDeliver(task)) {
            stopWatching(task.id)
            QqAccessibilityTaskLauncher.finishAndContinue(this, task)
            return
        }
        if (System.currentTimeMillis() >= watchDeadline) {
            stopWatching(task.id)
            QqAccessibilityTaskLauncher.finishAndContinue(this, task, "task_timeout")
            return
        }
        when (val result = QqAccessibilityReplyExecutor.execute(this, task)) {
            QqAccessibilityExecutionResult.Complete -> {
                if (watchedTaskId == task.id) clearWatch()
            }
            is QqAccessibilityExecutionResult.Retry -> {
                reportStage(result.stage)
                scheduleRetry()
            }
        }
    }

    private fun reportStage(stage: String) {
        if (lastStage == stage) return
        lastStage = stage
        QqBridgeChannels.emit(
            "accessibilityProgress",
            mapOf("success" to true, "stage" to stage),
        )
    }

    private fun stopWatching(taskId: String) {
        if (watchedTaskId == taskId) clearWatch()
    }

    private fun clearWatch() {
        watchedTaskId = null
        watchDeadline = 0
        lastStage = null
        attemptScheduled = false
        attemptRunnable?.let(handler::removeCallbacks)
        attemptRunnable = null
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
