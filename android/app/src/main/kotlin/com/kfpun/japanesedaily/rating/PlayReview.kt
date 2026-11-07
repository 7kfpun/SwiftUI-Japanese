package com.kfpun.japanesedaily.rating

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.google.android.play.core.review.ReviewManagerFactory
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents

/** Play In-App Review and the store page; the two ways a good rating leaves the app. */
object PlayReview {
    /**
     * Asks Play for its review sheet over [activity]. Play decides whether it shows and rations it; there
     * is no callback saying what was written, so `review_requested` counts *asks*, not sheets. Quiet where
     * Play is absent (an emulator without Play Store, a sideloaded build).
     */
    fun request(activity: Activity) {
        Track.event(TrackEvents.REVIEW_REQUESTED, mapOf("source" to "rating"))
        val manager = ReviewManagerFactory.create(activity)
        manager.requestReviewFlow().addOnCompleteListener { task ->
            val info = task.result?.takeIf { task.isSuccessful } ?: return@addOnCompleteListener
            if (!activity.isFinishing) manager.launchReviewFlow(activity, info)
        }
    }

    /** The app's Play listing, in the Play Store app when there is one, else on the web. */
    fun openStorePage(context: Context) {
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
