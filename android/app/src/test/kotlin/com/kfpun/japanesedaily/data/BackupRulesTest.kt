package com.kfpun.japanesedaily.data

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Progress is on the device only (FOX-146): the database and preferences this layer writes must not
 * reach a cloud backup or a device-to-device transfer. Reads the source files, since a JVM test has
 * no merged manifest to inspect.
 */
class BackupRulesTest {
    private val main = File("src/main")

    @Test
    fun allowBackupIsOff() {
        val manifest = File(main, "AndroidManifest.xml").readText()
        assertTrue(manifest.contains("android:allowBackup=\"false\""))
        assertTrue(manifest.contains("android:fullBackupContent=\"false\""))
        assertTrue(manifest.contains("android:dataExtractionRules=\"@xml/data_extraction_rules\""))
    }

    @Test
    fun everyDomainIsExcludedFromBothCloudBackupAndDeviceTransfer() {
        val rules = File(main, "res/xml/data_extraction_rules.xml").readText()
        for (section in listOf("cloud-backup", "device-transfer")) {
            val body = rules.substringAfter("<$section>").substringBefore("</$section>")
            // The Room database and the DataStore file live in the database and file domains.
            for (domain in listOf("root", "file", "database", "sharedpref", "external")) {
                assertTrue(
                    "$section does not exclude $domain",
                    body.contains("<exclude domain=\"$domain\" path=\".\" />")
                )
            }
            assertTrue("$section must not include anything", !body.contains("<include"))
        }
    }
}
