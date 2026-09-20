package com.mkdjj.whisnya

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** Only app-generated backup files can be exported; no byte arrays cross Flutter. */
class BackupFileBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "whisnya/backup_files")
    private val io = Executors.newSingleThreadExecutor()
    private val registered = mutableMapOf<String, File>()
    private var pending: MethodChannel.Result? = null
    private var exporting: File? = null

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "registerExport" -> {
                        val file = BackupFilePolicy.exportSource(requireNotNull(call.argument<String>("path")), File(activity.applicationInfo.dataDir, "app_flutter/backup_exports"))
                        val token = UUID.randomUUID().toString()
                        registered[token] = file
                        result.success(token)
                    }
                    "saveBackup" -> {
                        check(pending == null)
                        val token = requireNotNull(call.argument<String>("token"))
                        exporting = requireNotNull(registered.remove(token))
                        pending = result
                        activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/zip"
                            putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "Whisnya_backup.zip")
                        }, SAVE)
                    }
                    "pickBackup" -> {
                        check(pending == null)
                        pending = result
                        activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/zip"
                        }, OPEN)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                pending = null
                exporting = null
                result.error("backup_file", "无法打开备份文件选择器", null)
            }
        }
    }

    fun onActivityResult(request: Int, status: Int, data: Intent?): Boolean {
        if (request != SAVE && request != OPEN) return false
        val result = pending ?: return true
        pending = null
        val source = exporting
        exporting = null
        val uri: Uri? = data?.data
        if (status != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        io.execute {
            try {
                val value: Any = if (request == SAVE) {
                    val file = requireNotNull(source)
                    BackupFilePolicy.exportSource(file.path, File(activity.applicationInfo.dataDir, "app_flutter/backup_exports"))
                    // rwt explicitly requests truncation; unsupported providers fail safely.
                    activity.contentResolver.openOutputStream(uri, "rwt").use { output ->
                        requireNotNull(output)
                        file.inputStream().use { input ->
                            val copied = input.copyTo(output, 64 * 1024)
                            check(copied == file.length())
                        }
                        output.flush()
                    }
                    true
                } else {
                    val folder = File(activity.cacheDir, "backup_imports").apply { mkdirs() }
                    val file = File.createTempFile("backup_", ".zip", folder)
                    try {
                        activity.contentResolver.openInputStream(uri).use { input ->
                            requireNotNull(input)
                            file.outputStream().use { output ->
                                val buffer = ByteArray(64 * 1024)
                                var total = 0L
                                while (true) {
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    total += count
                                    check(total <= 512L * 1024 * 1024)
                                    output.write(buffer, 0, count)
                                }
                            }
                        }
                    } catch (error: Exception) { file.delete(); throw error }
                    file.path
                }
                activity.runOnUiThread { result.success(value) }
            } catch (_: Exception) {
                activity.runOnUiThread { result.error("backup_copy", "备份文件复制失败", null) }
            }
        }
        return true
    }

    companion object {
        private const val SAVE = 40811
        private const val OPEN = 40812
    }
}
