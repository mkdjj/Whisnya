package com.mkdjj.whisnya.qq

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class QqNativeConfigurationTest {
    @Test
    fun updateReportsOnlyVisibleChanges() {
        val first = mapOf(
            "mode" to "oneBot",
            "enabledContacts" to 3,
            "lastError" to "",
            "runtimeActive" to true,
        )

        assertTrue(QqNativeConfiguration.update(first))
        assertFalse(QqNativeConfiguration.update(first))
        assertTrue(QqNativeConfiguration.update(first + ("lastError" to "offline")))
    }
}
