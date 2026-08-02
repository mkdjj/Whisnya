package com.mkdjj.whisnya.qq

object QqNativeConfiguration {
    @Volatile var enabled: Boolean = false
    @Volatile var mode: String = "disabled"
    @Volatile var remoteInputEnabled: Boolean = true
    @Volatile var accessibilityFallbackEnabled: Boolean = false
    @Volatile var returnAfterSend: Boolean = true
    @Volatile var packageName: String = "com.tencent.mobileqq"
    @Volatile var sendButtonViewId: String = ""
    @Volatile var sendFailureNotice: Boolean = true
    @Volatile var enabledContacts: Int = 0
    @Volatile var lastError: String = ""
    @Volatile var runtimeActive: Boolean = false
    @Volatile var runGeneration: Long = 0

    fun update(values: Map<*, *>) {
        enabled = values["enabled"] as? Boolean ?: enabled
        mode = values["mode"] as? String ?: mode
        remoteInputEnabled = values["notificationRemoteInputEnabled"] as? Boolean
            ?: remoteInputEnabled
        accessibilityFallbackEnabled = values["accessibilityFallbackEnabled"] as? Boolean
            ?: accessibilityFallbackEnabled
        returnAfterSend = values["returnAfterAccessibilitySend"] as? Boolean
            ?: returnAfterSend
        packageName = values["notificationPackageName"] as? String ?: packageName
        sendButtonViewId = values["accessibilitySendButtonViewId"] as? String ?: sendButtonViewId
        sendFailureNotice = values["sendFailureNotice"] as? Boolean ?: sendFailureNotice
        enabledContacts = (values["enabledContacts"] as? Number)?.toInt() ?: enabledContacts
        lastError = values["lastError"] as? String ?: lastError
        runtimeActive = values["runtimeActive"] as? Boolean ?: runtimeActive
        runGeneration = (values["runGeneration"] as? Number)?.toLong() ?: runGeneration
    }
}
