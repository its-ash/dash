package com.itsash.dash

import android.content.Context

/** Starting and ending a trip, shared by the app, the service and the widget. */
object TripControl {
    /** Starts a fresh track log and the recording service. Returns the start time. */
    fun start(ctx: Context): Long {
        val app = ctx.applicationContext
        val prefs = NativePrefs(app)
        val now = System.currentTimeMillis()
        TrackLog.clear(app)
        TrackLog.marker(app, "start", now)
        prefs.paused = false
        prefs.tripActive = true
        try {
            TrackingService.start(app)
        } catch (e: Exception) {
            prefs.tripActive = false
            TrackLog.clear(app)
            DashWidget.refresh(app)
            throw e
        }
        DashWidget.refresh(app)
        return now
    }

    /**
     * Ends the trip without the app: marks the end time, moves the log to
     * `pending/` for Dart to save, and stops the service.
     */
    fun endInBackground(ctx: Context, endMs: Long = System.currentTimeMillis()) {
        val app = ctx.applicationContext
        val prefs = NativePrefs(app)
        if (!prefs.tripActive) return
        TrackLog.marker(app, "stop", endMs)
        prefs.tripActive = false
        prefs.paused = false
        TrackLog.archive(app)
        TrackingService.stop(app)
        DashWidget.refresh(app)
    }
}
