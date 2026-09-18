package com.mkdjj.whisnya.qq

import android.Manifest
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

object QqBridgeChannels {
    private const val METHOD_CHANNEL = "com.mkdjj.whisnya/qq_bridge"
    private const val EVENT_CHANNEL = "com.mkdjj.whisnya/qq_status"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var methodChannel: MethodChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    @Synchronized
    fun attach(app: Application, engine: FlutterEngine) {
        if (methodChannel != null) return
        methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNativeStatus" -> result.success(nativeStatus(app))
                    "startForegroundBridge" -> {
                        QqBridgeForegroundService.start(app)
                        result.success(true)
                    }
                    "stopForegroundBridge" -> {
                        QqBridgeForegroundService.stop(app)
                        result.success(true)
                    }
                    "openBatteryOptimizationSettings" -> success(result) {
                        QqSettingsLauncher.batteryOptimization(app)
                    }
                    "openAppNotificationSettings" -> success(result) {
                        QqSettingsLauncher.appNotification(app)
                    }
                    "updateNativeQqSettings" -> {
                        val changed = QqNativeConfiguration.update(
                            call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(),
                        )
                        if (changed) QqBridgeForegroundService.refresh(app)
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
                    emit("nativeStatus", nativeStatus(app))
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    fun runtimeControl(action: String) {
        invoke("qqRuntimeControl", mapOf("action" to action))
    }

    fun emit(type: String, details: Map<String, Any?> = emptyMap()) {
        mainHandler.post { eventSink?.success(mapOf("type" to type, "details" to details)) }
    }

    private fun invoke(method: String, arguments: Any?) {
        mainHandler.post {
            methodChannel?.invokeMethod(method, arguments, object : MethodChannel.Result {
                override fun success(result: Any?) = Unit

                override fun error(code: String, message: String?, details: Any?) {
                    emit("nativeError", mapOf("code" to code, "message" to (message ?: "")))
                }

                override fun notImplemented() = Unit
            })
        }
    }

    private fun nativeStatus(context: Context): Map<String, Any?> = mapOf(
        "foregroundService" to QqBridgeForegroundService.running,
        "notificationPermission" to hasNotificationPermission(context),
    )

    private fun hasNotificationPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun success(result: MethodChannel.Result, action: () -> Unit) {
        try {
            action()
            result.success(true)
        } catch (_: RuntimeException) {
            result.error("settings_open_failed", "Unable to open system settings.", null)
        }
    }
}
