package com.itsash.dash

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews

/**
 * Home-screen widget: odometer, last trip, and a Start / Stop trip button.
 *
 * The text lines are formatted by Dart (in the user's unit) and kept in
 * [NativePrefs]. Start opens Dash with [ACTION_START_TRIP] (Android only lets a
 * visible app start location tracking reliably); Stop ends the trip right
 * here, and Dart saves it the next time Dash runs.
 */
class DashWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, views(context)) }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_STOP_TRIP) {
            TripControl.endInBackground(context)
            refresh(context)
            return
        }
        super.onReceive(context, intent)
    }

    companion object {
        const val ACTION_START_TRIP = "com.itsash.dash.START_TRIP"
        const val ACTION_STOP_TRIP = "com.itsash.dash.STOP_TRIP"

        /** Redraws every Dash widget on the home screen. */
        fun refresh(context: Context) {
            val app = context.applicationContext
            val manager = AppWidgetManager.getInstance(app)
            val ids = manager.getAppWidgetIds(ComponentName(app, DashWidget::class.java))
            if (ids.isEmpty()) return
            val v = views(app)
            ids.forEach { manager.updateAppWidget(it, v) }
        }

        private fun views(context: Context): RemoteViews {
            val prefs = NativePrefs(context)
            val active = prefs.tripActive
            val pending = TrackLog.pendingCount(context)
            val v = RemoteViews(context.packageName, R.layout.dash_widget)

            v.setTextViewText(R.id.widget_odometer, prefs.widgetOdometer.ifEmpty { "Open Dash once" })
            val last = when {
                pending > 0 -> "Trip ended. Open Dash to save it."
                prefs.widgetLastTrip.isNotEmpty() -> prefs.widgetLastTrip
                else -> "No trips yet"
            }
            v.setTextViewText(R.id.widget_last_trip, last)
            v.setViewVisibility(R.id.widget_recording, if (active) View.VISIBLE else View.GONE)
            v.setTextViewText(
                R.id.widget_recording,
                if (prefs.paused) context.getString(R.string.widget_paused) else context.getString(R.string.widget_recording),
            )

            val open = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            v.setOnClickPendingIntent(R.id.widget_root, open)

            if (active) {
                v.setTextViewText(R.id.widget_button, context.getString(R.string.widget_stop))
                v.setInt(R.id.widget_button, "setBackgroundResource", R.drawable.widget_button_stop)
                val stop = PendingIntent.getBroadcast(
                    context,
                    1,
                    Intent(context, DashWidget::class.java).setAction(ACTION_STOP_TRIP),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
                v.setOnClickPendingIntent(R.id.widget_button, stop)
            } else {
                v.setTextViewText(R.id.widget_button, context.getString(R.string.widget_start))
                v.setInt(R.id.widget_button, "setBackgroundResource", R.drawable.widget_button)
                val start = PendingIntent.getActivity(
                    context,
                    2,
                    Intent(context, MainActivity::class.java)
                        .setAction(ACTION_START_TRIP)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
                v.setOnClickPendingIntent(R.id.widget_button, start)
            }
            return v
        }
    }
}
