package com.kfpun.japanesedaily.locale

import android.os.Build
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AppLanguageTest {
    @Test
    fun nineteenLanguagesInIosOrder() {
        assertEquals(
            listOf(
                "en", "zh", "zh-Hant", "id", "ko", "vi", "th", "fil", "my",
                "hi", "bn", "ta", "te", "ne", "es", "fr", "it", "de", "ru"
            ),
            AppLanguage.entries.map { it.id }
        )
    }

    @Test
    fun idsRoundTrip() {
        AppLanguage.entries.forEach { assertEquals(it, AppLanguage.fromId(it.id)) }
        assertNull(AppLanguage.fromId("system"))
        assertNull(AppLanguage.fromId(null))
    }

    @Test
    fun chineseFollowsIos() {
        assertEquals(AppLanguage.SIMPLIFIED_CHINESE, AppLanguage.fromLocaleTag("zh-Hans"))
        assertEquals(AppLanguage.SIMPLIFIED_CHINESE, AppLanguage.fromLocaleTag("zh-CN"))
        assertEquals(AppLanguage.SIMPLIFIED_CHINESE, AppLanguage.fromLocaleTag("zh_SG"))
        assertEquals(AppLanguage.TRADITIONAL_CHINESE, AppLanguage.fromLocaleTag("zh-TW"))
        assertEquals(AppLanguage.TRADITIONAL_CHINESE, AppLanguage.fromLocaleTag("zh-Hant-HK"))
        assertEquals(AppLanguage.TRADITIONAL_CHINESE, AppLanguage.fromLocaleTag("zh"))
    }

    @Test
    fun legacyAndUnknownTags() {
        assertEquals(AppLanguage.INDONESIAN, AppLanguage.fromLocaleTag("in"))
        assertEquals(AppLanguage.FILIPINO, AppLanguage.fromLocaleTag("tl-PH"))
        assertEquals(AppLanguage.GERMAN, AppLanguage.fromLocaleTag("de-AT"))
        assertNull(AppLanguage.fromLocaleTag("ja"))
        assertNull(AppLanguage.fromLocaleTag(""))
        assertNull(AppLanguage.fromLocaleTag(null))
    }

    @Test
    fun platformLocaleWinsOnAndroid13() {
        val tiramisu = Build.VERSION_CODES.TIRAMISU
        assertEquals(AppLanguage.KOREAN, AppLocale.resolve(tiramisu, "ko-KR,en", "de"))
        assertNull(AppLocale.resolve(tiramisu, "", "de"))
        assertEquals(AppLanguage.GERMAN, AppLocale.resolve(tiramisu - 1, "ko", "de"))
        assertNull(AppLocale.resolve(tiramisu - 1, null, null))
    }
}
