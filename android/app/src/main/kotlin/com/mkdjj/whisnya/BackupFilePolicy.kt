package com.mkdjj.whisnya

import java.io.File

internal object BackupFilePolicy {
    fun exportSource(path: String, allowedDirectory: File): File {
        val file = File(path).canonicalFile
        val allowed = allowedDirectory.canonicalFile
        require(file.path.startsWith(allowed.path + File.separator) && file.isFile && file.name == "backup.zip")
        return file
    }
}
