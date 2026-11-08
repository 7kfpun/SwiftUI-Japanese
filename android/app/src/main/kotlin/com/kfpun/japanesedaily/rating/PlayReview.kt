package com.kfpun.japanesedaily.rating

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents

/**
 * The app's Play listing. Play In-App Review is deliberately not used anywhere: Google forbids asking an
 * opinion question before its card, and the rating star row is one (`RatingHost`).
 */
object PlayReview {
    /**
     * Opens the listing, in the Play Store app when there is one, else on the web. [source] says which
     * surface asked (`rating` after a 4- or 5-star pick, `settings` for Rate the app).
     */
    fun openStorePage(context: Context, source: String) {
        Track.event(TrackEvents.STORE_PAGE_OPENED, mapOf("source" to source))
        val id = context.packageName
        val store = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("market://details?id=$id")
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(store)
        } catch (_: ActivityNotFoundException) {
            val web = Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$id"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            runCatching { context.startActivity(web) }
        }
    }
}
