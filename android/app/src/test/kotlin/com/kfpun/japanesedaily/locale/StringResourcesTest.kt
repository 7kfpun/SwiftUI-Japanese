package com.kfpun.japanesedaily.locale

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/**
 * Port of the iOS LocalizationTests parity checks, run on the generated resources: every key in
 * every language, the same placeholders, and the language list matching [AppLanguage].
 * Unit tests run from the module directory (android/app).
 */
class StringResourcesTest {
    private val res = File("src/main/res")
    private val folders = AppLanguage.entries.associateWith { folder(it) }
    private val english = strings("values")

    private fun folder(language: AppLanguage): String = when (language) {
        AppLanguage.ENGLISH -> "values"
        AppLanguage.SIMPLIFIED_CHINESE -> "values-b+zh+Hans"
        AppLanguage.TRADITIONAL_CHINESE -> "values-b+zh+Hant"
        AppLanguage.INDONESIAN -> "values-in"
        else -> "values-${language.localeTag}"
    }

    @Test
    fun everyLanguageHasEveryKey() {
        assertTrue(english.size > 300)
        folders.forEach { (language, dir) ->
            val table = strings(dir)
            assertEquals("$dir missing", emptySet<String>(), english.keys - table.keys)
            assertEquals("$dir extra (${language.id})", emptySet<String>(), table.keys - english.keys)
        }
    }

    @Test
    fun noStringIsBlank() {
        folders.values.forEach { dir ->
            val blank = strings(dir).filterValues { it.isBlank() }.keys
            assertTrue("$dir blank: $blank", blank.isEmpty())
        }
    }

    @Test
    fun translationsKeepThePlaceholders() {
        folders.values.forEach { dir ->
            val table = strings(dir)
            val bad = english.keys.filter { placeholders(english.getValue(it)) != placeholders(table.getValue(it)) }
            assertTrue("$dir placeholders differ from en: $bad", bad.isEmpty())
        }
    }

    @Test
    fun placeholdersAreNumberedAndNeverIosStyle() {
        folders.values.forEach { dir ->
            strings(dir).forEach { (name, value) ->
                assertTrue("$dir/$name still has %@: $value", !value.contains("%@"))
            }
        }
    }

    @Test
    fun onlyTheAppLanguagesShipStrings() {
        val found = res.listFiles { f -> File(f, "strings.xml").isFile }.orEmpty().map { it.name }.sorted()
        assertEquals(folders.values.sorted(), found)
    }

    @Test
    fun localeConfigListsEveryAppLanguage() {
        val config = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(File(res, "xml/locales_config.xml"))
        val nodes = config.getElementsByTagName("locale")
        val tags = (0 until nodes.length).map {
            (nodes.item(it) as Element).getAttributeNS("http://schemas.android.com/apk/res/android", "name")
        }
        assertEquals(AppLanguage.entries.map { it.localeTag }, tags)
    }

    /** Placeholder shape: how many `%n$s` and the set of their indexes. */
    private fun placeholders(value: String): List<Int> =
        Regex("%(\\d+)\\${"$"}s").findAll(value).map { it.groupValues[1].toInt() }.sorted().toList()

    private fun strings(dir: String): Map<String, String> {
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(File(res, "$dir/strings.xml"))
        val nodes = doc.getElementsByTagName("string")
        return (0 until nodes.length).associate {
            val e = nodes.item(it) as Element
            e.getAttribute("name") to e.textContent
        }
    }
}
