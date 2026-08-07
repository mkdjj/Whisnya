package com.mkdjj.whisnya.qq

import android.Manifest
import android.app.Application
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

object QqBridgeChannels {
    private const val METHOD_CHANNEL = "com.mkdjj.whisnya/qq_bridge"
    private const val EVENT_CHANNEL = "com.mkdjj.whisnya/qq_status"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var methodChannel: MethodChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var application: Application? = null

    @Synchronized
    fun attach(app: Application, engine: FlutterEngine) {
        if (methodChannel != null) return
        application = app
        methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNativeStatus" -> result.success(nativeStatus(app))
                    "startForegroundBridge" -> {
                        QqNotificationListenerService.requestReconnect(app)
                        QqBridgeForegroundService.start(app)
                        result.success(true)
                    }
                    "stopForegroundBridge" -> {
                        QqBridgeForegroundService.stop(app)
                        result.success(true)
                    }
                    "openNotificationListenerSettings" -> success(result) {
                        QqSettingsLauncher.notificationListener(app)
                    }
                    "openAccessibilitySettings" -> success(result) {
                        QqSettingsLauncher.accessibility(app)
                    }
                    "openBatteryOptimizationSettings" -> success(result) {
                        QqSettingsLauncher.batteryOptimization(app)
                    }
                    "openAppNotificationSettings" -> success(result) {
                        QqSettingsLauncher.appNotification(app)
                    }
                    "isNotificationAccessGranted" -> result.success(hasNotificationAccess(app))
                    "isAccessibilityServiceEnabled" -> result.success(hasAccessibilityAccess(app))
                    "isQqInstalled" -> result.success(isQqInstalled(app))
                    "beginNotificationCapture" -> {
                        QqNotificationListenerService.requestReconnect(app)
                        QqNotificationListenerService.beginCapture()
                        result.success(true)
                    }
                    "cancelNotificationCapture" -> {
                        QqNotificationListenerService.cancelCapture()
                        result.success(true)
                    }
                    "updateNativeQqSettings" -> {
                        QqNativeConfiguration.update(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                        QqNotificationListenerService.nativeConfigurationUpdated()
                        if (QqNativeConfiguration.enabled &&
                            QqNativeConfiguration.mode == "notification"
                        ) {
                            QqNotificationListenerService.requestReconnect(app)
                        }
                        QqBridgeForegroundService.refresh(app)
                        result.success(true)
                    }
                    "cancelPendingAccessibilityReply" -> {
                        QqPendingReplyStore.cancelAccessibility()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    emit("permissionChanged", nativeStatus(app))
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    fun incomingNotification(
        parsed: ParsedQqNotification,
        callback: (Map<*, *>?) -> Unit,
    ) {
        val arguments = mapOf(
            "messageId" to parsed.messageId,
            "externalUserId" to parsed.contactKey,
            "senderDisplayName" to parsed.title,
            "text" to parsed.text,
            "timestamp" to isoTimestamp(parsed.timestamp),
            "rawConversationTitle" to parsed.title,
            "nativeNotificationKey" to parsed.notificationKey,
            "packageName" to parsed.packageName,
            "shortcutId" to parsed.shortcutId,
        )
        invoke("qqIncomingNotification", arguments, callback)
    }

    fun notificationCaptured(parsed: ParsedQqNotification) {
        invoke(
            "qqNotificationCaptured",
            mapOf(
                "title" to parsed.title,
                "contactKey" to parsed.contactKey,
                "shortcutId" to parsed.shortcutId,
                "packageName" to parsed.packageName,
            ),
        ) {}
        emit("notificationCapture", mapOf("active" to false, "captured" to true))
    }

    fun notificationListenerState(context: Context, connected: Boolean) {
        emit(
            "permissionChanged",
            nativeStatus(context) + mapOf("listenerConnected" to connected),
        )
    }

    fun runtimeControl(action: String) {
        invoke("qqRuntimeControl", mapOf("action" to action)) {}
    }

    fun emit(type: String, details: Map<String, Any?> = emptyMap()) {
        mainHandler.post { eventSink?.success(mapOf("type" to type, "details" to details)) }
    }

    private fun invoke(method: String, arguments: Any?, callback: (Map<*, *>?) -> Unit) {
        mainHandler.post {
            methodChannel?.invokeMethod(method, arguments, object : MethodChannel.Result {
                override fun success(result: Any?) = callback(result as? Map<*, *>)
                override fun error(code: String, message: String?, details: Any?) {
                    emit("nativeError", mapOf("code" to code, "message" to (message ?: "")))
                    callback(mapOf("status" to "error", "message" to "Native bridge error"))
                }
                override fun notImplemented() = callback(mapOf("status" to "ignored"))
            })
        }
    }

    private fun nativeStatus(context: Context): Map<String, Any?> = mapOf(
        "foregroundService" to QqBridgeForegroundService.running,
        "notificationAccess" to hasNotificationAccess(context),
        "notificationListenerConnected" to QqNotificationListenerService.connected,
        "accessibilityAccess" to hasAccessibilityAccess(context),
        "notificationPermission" to hasNotificationPermission(context),
        "qqInstalled" to isQqInstalled(context),
        "deviceLocked" to QqPendingReplyStore.isDeviceLocked(context),
    )

    private fun hasNotificationAccess(context: Context): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners",
        ).orEmpty()
        return enabled.split(':').any {
            ComponentName.unflattenFromString(it)?.packageName == context.packageName
        }
    }

    private fun hasAccessibilityAccess(context: Context): Boolean {
        if (Settings.Secure.getInt(
                context.contentResolver,
                Settings.Secure.ACCESSIBILITY_ENABLED,
                0,
            ) != 1
        ) return false
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ).orEmpty()
        return enabled.split(':').any {
            ComponentName.unflattenFromString(it)?.className == QqAccessibilityService::class.java.name
        }
    }

    private fun hasNotificationPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun isQqInstalled(context: Context): Boolean = try {
        context.packageManager.getPackageInfo(QqNativeConfiguration.packageName, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private fun success(result: MethodChannel.Result, action: () -> Unit) {
        try {
            action()
            result.success(true)
        } catch (error: RuntimeException) {
            result.error("settings_open_failed", "无法打开系统设置。", null)
        }
    }

    private fun isoTimestamp(milliseconds: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).run {
            timeZone = TimeZone.getTimeZone("UTC")
            format(Date(milliseconds))
        }
}
