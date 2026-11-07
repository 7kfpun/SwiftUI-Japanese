package com.kfpun.japanesedaily.survey

import android.content.Context
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.settings.TextSize
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The context a rating or feedback row carries, read at submit time: premium and tier from Pro, the two
 * progress counts from the database, everything else from [AppInfo]. Shared by the feedback screen and the
 * rating prompt so the two never build it differently.
 */
suspend fun AppContainer.surveyContext(context: Context): Survey.Context = withContext(Dispatchers.IO) {
    val app = context.applicationContext
    AppInfo.surveyContext(
        app,
        prefs,
        vocab.deviceDefaultLanguage(),
        isPremium = pro.isPremium,
        tier = pro.tier,
        challengesPassed = progress.totalPassed(),
        kanaAnswered = progress.kanaResults().size,
        fontScaleMultiplier = TextSize.scale(app)
    )
}
