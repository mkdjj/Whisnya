package com.mkdjj.whisnya

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class BackupFilePolicyTest {
    @Test fun acceptsOnlyGeneratedExportFiles() {
        val root = Files.createTempDirectory("backup_policy").toFile()
        try {
            val allowed = File(root, "backup_exports").apply { mkdirs() }
            val generated = File(allowed, "export_one/backup.zip").apply { requireNotNull(parentFile).mkdirs(); writeText("test") }
            assertEquals(generated.canonicalFile, BackupFilePolicy.exportSource(generated.path, allowed))
            val outside = File(root, "backup.zip").apply { writeText("private") }
            assertThrows(IllegalArgumentException::class.java) { BackupFilePolicy.exportSource(outside.path, allowed) }
            assertThrows(IllegalArgumentException::class.java) { BackupFilePolicy.exportSource(File(allowed, "../backup.zip").path, allowed) }
            val wrongName = File(allowed, "api_config.json").apply { writeText("private") }
            assertThrows(IllegalArgumentException::class.java) { BackupFilePolicy.exportSource(wrongName.path, allowed) }
        } finally { root.deleteRecursively() }
    }
}
