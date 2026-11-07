package com.kfpun.japanesedaily.ads

import com.kfpun.japanesedaily.BuildConfig

/**
 * Where a banner appears (port of `AdSlot`). [analyticsName] is the slot name iOS logs with `ad_failed`
 * (the raw value, so `select-mode` and `vocab-list` keep their hyphens); [unitId] comes from
 * `secrets.properties`, falling back to Google's test ids in `secrets.example.properties`.
 */
enum class AdSlot(val analyticsName: String, val unitId: String) {
    Today("today", BuildConfig.AD_UNIT_ID_TODAY),
    Progress("progress", BuildConfig.AD_UNIT_ID_PROGRESS),
    Kana("kana", BuildConfig.AD_UNIT_ID_KANA),
    Lessons("lessons", BuildConfig.AD_UNIT_ID_LESSONS),
    SelectMode("select-mode", BuildConfig.AD_UNIT_ID_SELECT_MODE),
    VocabList("vocab-list", BuildConfig.AD_UNIT_ID_VOCAB_LIST),
    Search("search", BuildConfig.AD_UNIT_ID_SEARCH),
    About("about", BuildConfig.AD_UNIT_ID_ABOUT)
}
