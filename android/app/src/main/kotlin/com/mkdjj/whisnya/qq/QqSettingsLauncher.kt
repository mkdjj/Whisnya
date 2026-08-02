package com.mkdjj.whisnya.qq

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

object QqSettingsLauncher {
    fun notificationListener(context: Context) = open(
        context,
        Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS),
    )

    fun accessibility(context: Context) = open(
        context,
        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS),
    )

    fun batteryOptimization(context: Context) = open(
        context,
        Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:${context.packageName}"),
        ),
    )

    fun appNotification(context: Context) {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:${context.packageName}"))
        }
        open(context, intent)
    }

    private fun open(context: Context, intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }
}
