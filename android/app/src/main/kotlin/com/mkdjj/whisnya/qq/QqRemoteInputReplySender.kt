package com.mkdjj.whisnya.qq

import android.app.Notification
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.app.PendingIntent
import android.os.Build

sealed class QqRemoteInputResult {
    data object Sent : QqRemoteInputResult()
    data object Unavailable : QqRemoteInputResult()
    data class Failed(val code: String) : QqRemoteInputResult()
}

object QqRemoteInputReplySender {
    private val replyWords = listOf("回复", "reply", "回复消息", "快速回复")

    fun send(context: Context, notification: Notification, reply: String): QqRemoteInputResult {
        val candidate = notification.actions
            .orEmpty()
            .mapNotNull { action ->
                val inputs = action.remoteInputs.orEmpty().filter { it.allowFreeFormInput }
                if (inputs.isEmpty()) null else Triple(priority(action), action, inputs.first())
            }
            .sortedBy { it.first }
            .firstOrNull() ?: return QqRemoteInputResult.Unavailable
        val action = candidate.second
        val input = candidate.third
        return try {
            val intent = Intent()
            val results = Bundle().apply { putCharSequence(input.resultKey, reply) }
            RemoteInput.addResultsToIntent(arrayOf(input), intent, results)
            action.actionIntent.send(context, 0, intent)
            QqRemoteInputResult.Sent
        } catch (_: PendingIntent.CanceledException) {
            QqRemoteInputResult.Failed("pending_intent_cancelled")
        } catch (_: SecurityException) {
            QqRemoteInputResult.Failed("security")
        } catch (_: RuntimeException) {
            QqRemoteInputResult.Failed("runtime")
        }
    }

    private fun priority(action: Notification.Action): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            action.semanticAction == Notification.Action.SEMANTIC_ACTION_REPLY
        ) return 0
        val title = action.title?.toString()?.lowercase().orEmpty()
        if (replyWords.any(title::contains)) return 1
        return 2
    }
}
