package com.mkdjj.whisnya.qq

object QqNativeConfiguration {
    @Volatile var mode: String = "disabled"
    @Volatile var enabledContacts: Int = 0
    @Volatile var lastError: String = ""
    @Volatile var runtimeActive: Boolean = false

    @Synchronized
    fun update(values: Map<*, *>): Boolean {
        val nextMode = values["mode"] as? String ?: mode
        val nextEnabledContacts =
            (values["enabledContacts"] as? Number)?.toInt() ?: enabledContacts
        val nextLastError = values["lastError"] as? String ?: lastError
        val nextRuntimeActive = values["runtimeActive"] as? Boolean ?: runtimeActive
        val changed =
            nextMode != mode ||
                nextEnabledContacts != enabledContacts ||
                nextLastError != lastError ||
                nextRuntimeActive != runtimeActive
        mode = nextMode
        enabledContacts = nextEnabledContacts
        lastError = nextLastError
        runtimeActive = nextRuntimeActive
        return changed
    }
}
